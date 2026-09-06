#!/usr/bin/env python3
"""Validateur statique du modèle de vault d'exemple — lot L2.

Vérifie la cohérence structurelle du couple (inventaire, registre, vault
d'exemple) sans jamais afficher de valeur du vault. Read-only.

Exigences couvertes : GSO-REQ-024, 061, 062, 069, 098 (versant contenu),
203, et la disjonction actif/retiré (GSO-REQ-073).

Usage :
    vault_lint.py --inventory inventories/example/hosts.yml
    vault_lint.py --inventory <hosts.yml> --vault <chemin/vault.yml.example>

Ne lit ni ne déchiffre aucun vault opérationnel : opère uniquement sur le
modèle `.example` en clair.
"""

from __future__ import annotations

import argparse
import os
import re
import sys

try:
    import yaml
except ImportError:
    print("FAIL  PyYAML absent", file=sys.stderr)
    sys.exit(2)

ADMIN_TRISTATE = ("admin_user", "admin_password", "admin_email")
ADMIN_OPTIONAL = ("admin_fullname", "admin_title", "admin_language", "admin_type")
ADMIN_ALL = ADMIN_TRISTATE + ADMIN_OPTIONAL
ADMIN_TYPE_VALUES = {"", "admin", "api", "both"}
ENTRY_ALLOWED = set(ADMIN_ALL) | {"secrets"}
SECRET_NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
VAULT_ROOTS = ["vault_grav_sites", "vault_retired_grav_sites"]

errors: list[str] = []
checks = 0


def check(ok: bool, ok_msg: str, err_msg: str) -> None:
    global checks
    checks += 1
    if ok:
        print(f"PASS  {ok_msg}")
    else:
        print(f"FAIL  {err_msg}")
        errors.append(err_msg)


def load_yaml(path: str):
    with open(path, encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def collect_hosts(inv: dict) -> set[str]:
    hosts: set[str] = set()

    def walk(groups: dict) -> None:
        if not isinstance(groups, dict):
            return
        for name, body in groups.items():
            body = body or {}
            if name == "grav_servers":
                hosts.update((body.get("hosts") or {}).keys())
            walk(body.get("children") or {})

    walk({"all": (inv or {}).get("all", {}) or {}})
    return hosts


def validate_admin(entry_key: str, entry: dict, *, retired: bool) -> None:
    set_count = sum(1 for f in ADMIN_TRISTATE if str(entry.get(f, "")).strip())
    check(
        set_count in (0, 3),
        f"{entry_key}: bootstrap admin tri-state cohérent ({set_count}/3)",
        f"{entry_key}: bootstrap admin partiel ({set_count}/3) — "
        f"user/password/email doivent être tous présents ou tous absents (GSO-REQ-062)",
    )
    atype = entry.get("admin_type", "")
    check(
        atype in ADMIN_TYPE_VALUES,
        f"{entry_key}: admin_type valide",
        f"{entry_key}: admin_type hors {sorted(ADMIN_TYPE_VALUES)}",
    )
    unknown = set(entry) - ENTRY_ALLOWED
    check(
        not unknown,
        f"{entry_key}: aucun champ non autorisé",
        f"{entry_key}: champ(s) non autorisé(s) {sorted(unknown)}",
    )


def validate_secrets(entry_key: str, entry: dict) -> None:
    if "secrets" not in entry:
        return
    secrets = entry["secrets"]
    if not isinstance(secrets, list) or not secrets:
        check(False, "", f"{entry_key}: `secrets` doit être une liste non vide")
        return
    for i, s in enumerate(secrets):
        tag = f"{entry_key}.secrets[{i}]"
        if not isinstance(s, dict):
            check(False, "", f"{tag}: élément non-dictionnaire")
            continue
        check(
            set(s.keys()) == {"name", "content"},
            f"{tag}: clés exactement {{name, content}}",
            f"{tag}: clés {sorted(s.keys())} — attendu exactement name + content "
            f"(forme `src` interdite, GSO-REQ-203)",
        )
        name = str(s.get("name", ""))
        check(
            bool(SECRET_NAME_RE.match(name))
            and ".." not in name and "/" not in name and ":" not in name,
            f"{tag}: name conforme",
            f"{tag}: name invalide (lettres/chiffres/._- , jamais .. / :)",
        )
        content = s.get("content")
        check(
            isinstance(content, str) and content.strip() != "",
            f"{tag}: content inline non vide",
            f"{tag}: content absent ou vide",
        )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--inventory", required=True)
    ap.add_argument("--vault")
    ap.add_argument("--registry")
    args = ap.parse_args()

    inv_path = args.inventory
    inv_dir = os.path.dirname(inv_path)
    gv = os.path.join(inv_dir, "group_vars", "all")
    reg_path = args.registry or os.path.join(gv, "grav_sites.yml")
    vault_path = args.vault or os.path.join(gv, "vault.yml.example")

    for label, path in (("inventaire", inv_path), ("registre", reg_path), ("vault", vault_path)):
        check(os.path.isfile(path), f"{label} présent", f"{label} introuvable : {path}")
    if errors:
        return finish()

    # Le modèle d'exemple doit être en clair, jamais chiffré.
    with open(vault_path, encoding="utf-8") as fh:
        head = fh.read(32)
    check(
        not head.startswith("$ANSIBLE_VAULT"),
        "vault d'exemple en clair (non chiffré)",
        "vault d'exemple chiffré — le modèle .example doit rester en clair",
    )

    inv = load_yaml(inv_path)
    registry = (load_yaml(reg_path) or {}).get("grav_sites") or {}
    vault_doc = load_yaml(vault_path) or {}

    # --- Racines du vault : exactement les deux dictionnaires attendus ---
    check(
        sorted(vault_doc.keys()) == sorted(VAULT_ROOTS),
        "vault : racines exactement {vault_grav_sites, vault_retired_grav_sites}",
        f"vault : racines {sorted(vault_doc.keys())} — attendu {sorted(VAULT_ROOTS)}",
    )
    active = vault_doc.get("vault_grav_sites") or {}
    retired = vault_doc.get("vault_retired_grav_sites") or {}
    check(isinstance(retired, dict),
          "vault_retired_grav_sites est un dictionnaire",
          "vault_retired_grav_sites doit être un dictionnaire (vide ou peuplé)")

    hosts = collect_hosts(inv)
    reg_keys = set(registry.keys())
    vault_keys = set(active.keys())

    # --- Correspondance exacte inventaire / registre / vault ---
    check(
        hosts == reg_keys == vault_keys,
        f"correspondance exacte inventaire/registre/vault ({len(vault_keys)} clés)",
        "correspondance rompue : "
        f"orphelins vault={sorted(vault_keys - reg_keys)} ; "
        f"manquants vault={sorted(reg_keys - vault_keys)} ; "
        f"hors inventaire={sorted(vault_keys - hosts)}",
    )

    # --- Disjonction actif / retiré (GSO-REQ-073) ---
    overlap = vault_keys & set(retired.keys())
    check(not overlap, "aucune clé simultanément active et retirée dans le vault",
          f"clés à la fois dans vault_grav_sites et vault_retired_grav_sites : {sorted(overlap)}")

    # --- Le registre non secret ne contient aucun secret (GSO-REQ-203/024) ---
    leaked = []
    for k, e in registry.items():
        e = e or {}
        bad = set(e) & (set(ADMIN_ALL) | {"secrets"})
        if bad:
            leaked.append((k, sorted(bad)))
    check(not leaked, "registre grav_sites : aucun champ secret / admin / secrets",
          f"registre grav_sites contient des champs interdits : {leaked}")

    # --- Validation entrée par entrée (actif puis retiré) ---
    for key, entry in active.items():
        entry = entry or {}
        validate_admin(key, entry, retired=False)
        validate_secrets(key, entry)
    for key, entry in retired.items():
        entry = entry or {}
        validate_admin(key, entry, retired=True)
        validate_secrets(key, entry)

    return finish()


def finish() -> int:
    print("----")
    if errors:
        print(f"vault_lint : {len(errors)} erreur(s) sur {checks} contrôles")
        return 1
    print(f"vault_lint : {checks} contrôles OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
