#!/usr/bin/env python3
"""Validation partagée de `grav-sites-ops` — registre, vault, sélecteur, préflight.

**Une seule** implémentation des règles de validation, utilisée à la fois par
les tests (GSO-T05..T12) et par le préflight opérateur
(`scripts/validate-target.sh`, `scripts/preflight.sh`). Read-only : ne déploie
rien, n'ouvre aucun vault chiffré, ne contacte aucune machine, ne modifie aucun
fichier (GSO-REQ-026, 095, 107, 130). Échoue fermé : tout écart → code ≠ 0.

Sous-commandes :
    registry  --inventory <hosts.yml> [--context example|production]
    vault     --inventory <hosts.yml> [--vault <f>] [--registry <f>]
    selector  <SITE> [--root <dir>] [--action deploy|restart|stop|check]
    preflight <SITE> [--root <dir>] [--action ...]   (selector + registry + vault)

`--root` (sélecteur/préflight) : racine d'arborescence, RÉSERVÉE AUX TESTS.
Par défaut, la racine est le dépôt et l'inventaire est **fixé** à
`inventories/production/hosts.yml` — jamais remplaçable par une option.
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import re
import subprocess
import sys

try:
    import yaml
except ImportError:
    print("FAIL  PyYAML absent", file=sys.stderr)
    sys.exit(2)

# --------------------------------------------------------------------------- #
# Constantes de schéma
# --------------------------------------------------------------------------- #
REG_MANDATORY = [
    "project_name", "image", "version", "digest",
    "container_name", "base_directory", "bind_address", "http_port",
]
REG_OPTIONAL = {"state", "force_pull", "manage_docker", "site_check_path", "extra_environment"}
ALLOWED_STATES = {"started", "stopped", "restarted"}
RUNTIME_KEYS = {"grav_runtime", "grav_runtime_version", "runtime_version", "runtime"}
DOC_NETS = [
    ipaddress.ip_network("192.0.2.0/24"),
    ipaddress.ip_network("198.51.100.0/24"),
    ipaddress.ip_network("203.0.113.0/24"),
    ipaddress.ip_network("127.0.0.0/8"),
]

ADMIN_TRISTATE = ("admin_user", "admin_password", "admin_email")
ADMIN_OPTIONAL = ("admin_fullname", "admin_title", "admin_language", "admin_type")
ADMIN_ALL = ADMIN_TRISTATE + ADMIN_OPTIONAL
ADMIN_TYPE_VALUES = {"", "admin", "api", "both"}
VAULT_ENTRY_ALLOWED = set(ADMIN_ALL) | {"secrets"}
VAULT_ROOTS = ["vault_grav_sites", "vault_retired_grav_sites"]
SECRET_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")

SITE_RE = re.compile(r"^[a-z][a-z0-9-]*$")
GLOBAL_TOKENS = {"all", "*", "grav_servers", "ungrouped", "localhost", "none"}
FIXED_INVENTORY = os.path.join("inventories", "production", "hosts.yml")


# --------------------------------------------------------------------------- #
# Rapporteur
# --------------------------------------------------------------------------- #
class Reporter:
    def __init__(self, quiet: bool = False) -> None:
        self.checks = 0
        self.errors: list[str] = []
        self.quiet = quiet

    def ok(self, msg: str) -> None:
        self.checks += 1
        if not self.quiet:
            print(f"PASS  {msg}")

    def fail(self, msg: str) -> None:
        self.checks += 1
        self.errors.append(msg)
        if not self.quiet:
            print(f"FAIL  {msg}")

    def check(self, cond: bool, ok_msg: str, err_msg: str) -> bool:
        if cond:
            self.ok(ok_msg)
        else:
            self.fail(err_msg)
        return cond

    def note(self, msg: str) -> None:
        if not self.quiet:
            print(f"SKIP  {msg}")


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
def load_yaml(path: str):
    with open(path, encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def is_doc_addr(value: str) -> bool:
    try:
        addr = ipaddress.ip_address(value)
    except ValueError:
        return False
    return any(addr in net for net in DOC_NETS)


def collect_grav_servers(inv: dict) -> list[str]:
    hosts: list[str] = []

    def walk(groups: dict) -> None:
        if not isinstance(groups, dict):
            return
        for name, body in groups.items():
            body = body or {}
            if name == "grav_servers":
                hosts.extend((body.get("hosts") or {}).keys())
            walk(body.get("children") or {})

    walk({"all": (inv or {}).get("all", {}) or {}})
    return sorted(set(hosts))


def ansible_inventory_hosts(inv_path: str) -> tuple[dict, list[str]]:
    """Retourne (json complet, hôtes de grav_servers) via ansible-inventory.

    Local pur : `ansible-inventory --list` ne se connecte à rien.
    """
    out = subprocess.run(
        ["ansible-inventory", "-i", inv_path, "--list"],
        capture_output=True, text=True, check=True,
    ).stdout
    data = json.loads(out)
    hosts = data.get("grav_servers", {}).get("hosts", [])
    return data, sorted(hosts)


def gv_dir(inv_path: str) -> str:
    return os.path.join(os.path.dirname(inv_path), "group_vars", "all")


def retired_path_for(inv_path: str) -> str:
    return os.path.normpath(
        os.path.join(os.path.dirname(inv_path) or ".", "..", "..", "registry", "retired-sites.yml")
    )


# --------------------------------------------------------------------------- #
# Règles registre
# --------------------------------------------------------------------------- #
def validate_registry(inv_path: str, context: str, r: Reporter) -> dict:
    reg_path = os.path.join(gv_dir(inv_path), "grav_sites.yml")
    if not r.check(os.path.isfile(inv_path), f"inventaire présent : {inv_path}",
                   f"inventaire introuvable : {inv_path}"):
        return {}
    if not r.check(os.path.isfile(reg_path), f"registre présent : {reg_path}",
                   f"registre introuvable : {reg_path}"):
        return {}

    inv = load_yaml(inv_path)
    reg_doc = load_yaml(reg_path)

    r.check(isinstance(reg_doc, dict) and list((reg_doc or {}).keys()) == ["grav_sites"],
            "registre : unique clé racine `grav_sites`",
            f"registre : clés racines inattendues {list((reg_doc or {}).keys())}")
    sites = (reg_doc or {}).get("grav_sites") or {}
    hosts = collect_grav_servers(inv)
    r.check(len(hosts) > 0, f"inventaire : {len(hosts)} hôte(s) dans grav_servers",
            "inventaire : groupe grav_servers vide ou absent")

    host_set, site_set = set(hosts), set(sites.keys())
    r.check(host_set == site_set,
            f"correspondance totale hôtes/registre ({len(host_set)} clés)",
            f"correspondance rompue : hôtes sans entrée={sorted(host_set - site_set)} ; "
            f"entrées sans hôte={sorted(site_set - host_set)}")

    if context == "example":
        gs = ((inv or {}).get("all", {}).get("children", {}) or {}).get("grav_servers", {}) or {}
        for h, hv in (gs.get("hosts") or {}).items():
            ah = str((hv or {}).get("ansible_host", ""))
            r.check(is_doc_addr(ah), f"{h}: ansible_host documentaire ({ah})",
                    f"{h}: ansible_host non documentaire en contexte example ({ah})")

    seen = {"project_name": {}, "container_name": {}, "base_directory": {}, "endpoint": {}}
    for key, entry in sites.items():
        entry = entry or {}
        for field in REG_MANDATORY:
            non_empty = field == "digest" or (entry.get(field) not in (None, "", {}))
            r.check(field in entry and non_empty,
                    f"{key}: champ obligatoire `{field}` présent",
                    f"{key}: champ obligatoire `{field}` absent ou vide")
        unknown = set(entry) - set(REG_MANDATORY) - REG_OPTIONAL
        r.check(not unknown, f"{key}: aucun champ inconnu",
                f"{key}: champ(s) hors schéma {sorted(unknown)}")
        r.check(not (set(entry) & RUNTIME_KEYS),
                f"{key}: pas de version de runtime déclarée",
                f"{key}: déclaration de runtime interdite (GSO-REQ-011)")

        image = str(entry.get("image", ""))
        r.check(":" not in image.rsplit("/", 1)[-1] and "@" not in image.rsplit("/", 1)[-1],
                f"{key}: image sans tag ni digest incorporé",
                f"{key}: image avec tag/digest incorporé ({image}) (GSO-REQ-010)")
        r.check("latest" not in image.lower().split("/"),
                f"{key}: image sans `latest`",
                f"{key}: image utilise `latest` (GSO-REQ-020)")

        version = entry.get("version")
        r.check(isinstance(version, str) and version.strip() not in ("", "latest"),
                f"{key}: version humaine explicite ({version})",
                f"{key}: version manquante, vide ou `latest` (GSO-REQ-021/154)")
        digest = entry.get("digest", "")
        r.check(digest == "" or re.fullmatch(r"sha256:[0-9a-f]{64}", str(digest)),
                f"{key}: digest vide ou sha256 valide",
                f"{key}: digest mal formé ({digest!r})")

        addr = str(entry.get("bind_address", ""))
        try:
            ipaddress.IPv4Address(addr)
            addr_ok = True
        except ipaddress.AddressValueError:
            addr_ok = False
        r.check(addr_ok, f"{key}: bind_address IPv4 littérale ({addr})",
                f"{key}: bind_address non IPv4 ({addr!r}) (GSO-REQ-065)")
        if context == "example" and addr_ok:
            r.check(is_doc_addr(addr), f"{key}: bind_address documentaire",
                    f"{key}: bind_address non documentaire en contexte example ({addr})")
        port = entry.get("http_port")
        r.check(isinstance(port, int) and 1 <= port <= 65535,
                f"{key}: http_port valide ({port})",
                f"{key}: http_port invalide ({port!r}) (GSO-REQ-065)")
        base = str(entry.get("base_directory", ""))
        r.check(base.startswith("/") and not re.match(r"^/(home|Users|root)/", base),
                f"{key}: base_directory chemin absolu non workstation",
                f"{key}: base_directory suspect ({base!r})")
        state = entry.get("state", "started")
        r.check(state in ALLOWED_STATES, f"{key}: state non destructif ({state})",
                f"{key}: state hors {sorted(ALLOWED_STATES)} ({state!r}) (GSO-REQ-051)")

        for field in ("project_name", "container_name", "base_directory"):
            val = entry.get(field)
            if val in (None, ""):
                continue
            r.check(seen[field].get(val) is None, f"{key}: {field} unique",
                    f"{key}: {field} `{val}` déjà utilisé par `{seen[field].get(val)}` (GSO-REQ-050)")
            seen[field][val] = key
        endpoint = f"{addr}:{port}"
        r.check(seen["endpoint"].get(endpoint) is None, f"{key}: endpoint {endpoint} unique",
                f"{key}: endpoint {endpoint} déjà utilisé par `{seen['endpoint'].get(endpoint)}` (GSO-REQ-050)")
        seen["endpoint"][endpoint] = key

    rp = retired_path_for(inv_path)
    if os.path.isfile(rp):
        retired = (load_yaml(rp) or {}).get("retired_grav_sites") or {}
        overlap = site_set & set(retired.keys())
        r.check(not overlap, "aucune clé active dans retired_grav_sites",
                f"clés simultanément actives et retirées : {sorted(overlap)} (GSO-REQ-052)")
    else:
        r.note("registry/retired-sites.yml absent (attendu avant le lot L8)")
    return sites


# --------------------------------------------------------------------------- #
# Règles vault
# --------------------------------------------------------------------------- #
def _validate_admin(key: str, entry: dict, r: Reporter) -> None:
    n = sum(1 for f in ADMIN_TRISTATE if str(entry.get(f, "")).strip())
    r.check(n in (0, 3), f"{key}: bootstrap admin tri-state cohérent ({n}/3)",
            f"{key}: bootstrap admin partiel ({n}/3) — tous présents ou tous absents (GSO-REQ-062)")
    r.check(entry.get("admin_type", "") in ADMIN_TYPE_VALUES,
            f"{key}: admin_type valide", f"{key}: admin_type hors {sorted(ADMIN_TYPE_VALUES)}")
    unknown = set(entry) - VAULT_ENTRY_ALLOWED
    r.check(not unknown, f"{key}: aucun champ non autorisé",
            f"{key}: champ(s) non autorisé(s) {sorted(unknown)}")


def _validate_secrets(key: str, entry: dict, r: Reporter) -> None:
    if "secrets" not in entry:
        return
    secrets = entry["secrets"]
    if not isinstance(secrets, list) or not secrets:
        r.fail(f"{key}: `secrets` doit être une liste non vide")
        return
    for i, s in enumerate(secrets):
        tag = f"{key}.secrets[{i}]"
        if not isinstance(s, dict):
            r.fail(f"{tag}: élément non-dictionnaire")
            continue
        r.check(set(s.keys()) == {"name", "content"}, f"{tag}: clés exactement {{name, content}}",
                f"{tag}: clés {sorted(s.keys())} — attendu name + content (forme `src` interdite, GSO-REQ-203)")
        name = str(s.get("name", ""))
        r.check(bool(SECRET_NAME_RE.match(name)) and ".." not in name and "/" not in name and ":" not in name,
                f"{tag}: name conforme", f"{tag}: name invalide (lettres/chiffres/._- , jamais .. / :)")
        r.check(isinstance(s.get("content"), str) and str(s.get("content")).strip() != "",
                f"{tag}: content inline non vide", f"{tag}: content absent ou vide")


def validate_vault(inv_path: str, vault_path: str | None, registry_path: str | None, r: Reporter) -> None:
    reg_path = registry_path or os.path.join(gv_dir(inv_path), "grav_sites.yml")
    vpath = vault_path or os.path.join(gv_dir(inv_path), "vault.yml.example")
    for label, p in (("inventaire", inv_path), ("registre", reg_path), ("vault", vpath)):
        if not r.check(os.path.isfile(p), f"{label} présent", f"{label} introuvable : {p}"):
            return

    with open(vpath, encoding="utf-8") as fh:
        head = fh.read(32)
    r.check(not head.startswith("$ANSIBLE_VAULT"), "vault d'exemple en clair (non chiffré)",
            "vault chiffré — le modèle .example doit rester en clair")

    inv = load_yaml(inv_path)
    registry = (load_yaml(reg_path) or {}).get("grav_sites") or {}
    vault_doc = load_yaml(vpath) or {}
    r.check(sorted(vault_doc.keys()) == sorted(VAULT_ROOTS),
            "vault : racines exactement {vault_grav_sites, vault_retired_grav_sites}",
            f"vault : racines {sorted(vault_doc.keys())} — attendu {sorted(VAULT_ROOTS)}")
    active = vault_doc.get("vault_grav_sites") or {}
    retired = vault_doc.get("vault_retired_grav_sites") or {}
    r.check(isinstance(retired, dict), "vault_retired_grav_sites est un dictionnaire",
            "vault_retired_grav_sites doit être un dictionnaire")

    hosts = set(collect_grav_servers(inv))
    reg_keys, vault_keys = set(registry.keys()), set(active.keys())
    r.check(hosts == reg_keys == vault_keys,
            f"correspondance exacte inventaire/registre/vault ({len(vault_keys)} clés)",
            f"correspondance rompue : orphelins vault={sorted(vault_keys - reg_keys)} ; "
            f"manquants vault={sorted(reg_keys - vault_keys)} ; hors inventaire={sorted(vault_keys - hosts)}")
    overlap = vault_keys & set(retired.keys())
    r.check(not overlap, "aucune clé simultanément active et retirée dans le vault",
            f"clés à la fois actives et retirées : {sorted(overlap)}")

    leaked = [(k, sorted(set(e or {}) & (set(ADMIN_ALL) | {'secrets'})))
              for k, e in registry.items() if set(e or {}) & (set(ADMIN_ALL) | {"secrets"})]
    r.check(not leaked, "registre grav_sites : aucun champ secret / admin / secrets",
            f"registre grav_sites contient des champs interdits : {leaked}")

    for key, entry in {**active, **retired}.items():
        entry = entry or {}
        _validate_admin(key, entry, r)
        _validate_secrets(key, entry, r)


# --------------------------------------------------------------------------- #
# Sélecteur fermé
# --------------------------------------------------------------------------- #
def validate_selector(site: str | None, root: str, action: str, r: Reporter) -> str | None:
    # 1. SITE obligatoire (GSO-REQ-083)
    if not r.check(bool(site) and site.strip() != "", "SITE fourni et non vide",
                   "SITE absent ou vide (GSO-REQ-083)"):
        return None

    # 2. Forme fermée (GSO-REQ-084, GSO-REQ-138)
    form_ok = bool(SITE_RE.fullmatch(site))
    r.check(form_ok, f"SITE respecte ^[a-z][a-z0-9-]*$ ({site!r})",
            f"SITE {site!r} viole ^[a-z][a-z0-9-]*$ — espace, glob, virgule, deux-points, "
            f"majuscule ou caractère de shell interdit (GSO-REQ-084)")
    # 3. Jamais une cible globale (GSO-REQ-138 ; user)
    r.check(site not in GLOBAL_TOKENS, f"SITE n'est pas un jeton global ({site!r})",
            f"SITE {site!r} est une cible globale interdite (all/*/groupe)")
    if not form_ok or site in GLOBAL_TOKENS:
        return None

    # 4. Inventaire imposé, non remplaçable (GSO-REQ-053, GSO-T08)
    inv_path = os.path.join(root, FIXED_INVENTORY)
    if not r.check(os.path.isfile(inv_path),
                   f"inventaire imposé présent : {FIXED_INVENTORY}",
                   f"inventaire imposé absent : {os.path.join(root, FIXED_INVENTORY)} "
                   f"(aucune option ne peut le remplacer — GSO-REQ-053)"):
        return None

    # 5. Parsing de l'inventaire imposé (local, aucune connexion)
    try:
        _, hosts = ansible_inventory_hosts(inv_path)
    except (subprocess.CalledProcessError, json.JSONDecodeError) as exc:
        r.fail(f"inventaire imposé invalide : {exc}")
        return None

    # 6. Cible = exactement un hôte actif de grav_servers (GSO-REQ-017, 057, 086, 138)
    if not r.check(site in hosts,
                   f"SITE correspond à un hôte actif unique de grav_servers ({site})",
                   f"SITE {site!r} ne correspond à aucun hôte actif de grav_servers "
                   f"(inconnu, retiré ou groupe) — GSO-REQ-086"):
        return None
    r.check(hosts.count(site) == 1, "résolution non ambiguë (1 hôte)",
            f"SITE {site!r} résout plusieurs hôtes (GSO-REQ-017/057)")

    # 7. Cohérence registre + retiré (réutilise validate_registry)
    reg_reporter = Reporter(quiet=True)
    sites = validate_registry(inv_path, "production", reg_reporter)
    r.check(not reg_reporter.errors,
            "registre cohérent (validateur partagé)",
            f"registre incohérent : {'; '.join(reg_reporter.errors[:3])}")
    r.check(site in sites, f"SITE possède une entrée de registre ({site})",
            f"SITE {site!r} sans entrée dans grav_sites (GSO-REQ-085 §13.3.5)")

    rp = retired_path_for(inv_path)
    if os.path.isfile(rp):
        retired = (load_yaml(rp) or {}).get("retired_grav_sites") or {}
        r.check(site not in retired, f"SITE n'est pas un projet retiré ({site})",
                f"SITE {site!r} est présent dans retired_grav_sites (GSO-REQ-052)")

    # 8. Cohérence vault si un modèle en clair est résolvable (sinon : L4)
    vpath = os.path.join(gv_dir(inv_path), "vault.yml.example")
    if not os.path.isfile(vpath):
        vpath = os.path.join(gv_dir(inv_path), "vault.yml")
        try:
            with open(vpath, encoding="utf-8") as fh:
                if fh.read(14) == "$ANSIBLE_VAULT":
                    vpath = None
        except OSError:
            vpath = None
    if vpath and os.path.isfile(vpath):
        v_reporter = Reporter(quiet=True)
        validate_vault(inv_path, vpath, None, v_reporter)
        r.check(not v_reporter.errors, "vault cohérent (validateur partagé)",
                f"vault incohérent : {'; '.join(v_reporter.errors[:3])}")
        vault_active = (load_yaml(vpath) or {}).get("vault_grav_sites") or {}
        r.check(site in vault_active, f"SITE possède une entrée de vault ({site})",
                f"SITE {site!r} sans entrée dans vault_grav_sites")
    else:
        r.note("aucun modèle de vault en clair résolvable ici — contrôle vault délégué au préflight de déploiement (L4, GSO-REQ-204)")

    return site if not r.errors else None


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _finish(r: Reporter, label: str) -> int:
    print("----")
    if r.errors:
        print(f"{label} : {len(r.errors)} erreur(s) sur {r.checks} contrôles")
        return 1
    print(f"{label} : {r.checks} contrôles OK")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="gso_validate")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("registry")
    p.add_argument("--inventory", required=True)
    p.add_argument("--context", choices=["example", "production"], default="example")

    p = sub.add_parser("vault")
    p.add_argument("--inventory", required=True)
    p.add_argument("--vault")
    p.add_argument("--registry")

    for name in ("selector", "preflight"):
        p = sub.add_parser(name)
        p.add_argument("site", nargs="?")
        p.add_argument("--root", default=".")
        p.add_argument("--action", choices=["deploy", "restart", "stop", "check"], default="deploy")

    args = ap.parse_args(argv)
    r = Reporter()

    if args.cmd == "registry":
        validate_registry(args.inventory, args.context, r)
        return _finish(r, "registry")
    if args.cmd == "vault":
        validate_vault(args.inventory, args.vault, args.registry, r)
        return _finish(r, "vault")

    resolved = validate_selector(args.site, args.root, args.action, r)
    if args.cmd == "preflight" and resolved and not r.errors:
        inv_path = os.path.join(args.root, FIXED_INVENTORY)
        validate_registry(inv_path, "production", r)
        vpath = os.path.join(gv_dir(inv_path), "vault.yml.example")
        if os.path.isfile(vpath):
            validate_vault(inv_path, vpath, None, r)
    rc = _finish(r, args.cmd)
    if rc == 0 and resolved:
        print(f"TARGET {resolved}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
