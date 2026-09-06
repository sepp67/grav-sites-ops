#!/usr/bin/env python3
"""Validateur statique de la couche de données déclaratives — lot L1.

Vérifie la cohérence interne d'un couple (inventaire, registre `grav_sites`)
sans rien déployer et sans ouvrir de vault. Read-only (GSO-REQ-130).

Exigences couvertes (structurellement) : GSO-REQ-010, 011, 013, 020, 021,
048, 049, 050, 051, 054, 065, 068, 100, 128, 154.

Usage :
    registry_lint.py --inventory inventories/example/hosts.yml [--context example|production]

Le contexte `example` (défaut) impose des données synthétiques (adresses
TEST-NET, registre d'images `.invalid`, chemins hors workstation).
"""

from __future__ import annotations

import argparse
import ipaddress
import os
import re
import sys

try:
    import yaml
except ImportError:
    print("FAIL  PyYAML absent", file=sys.stderr)
    sys.exit(2)

MANDATORY = [
    "project_name",
    "image",
    "version",
    "digest",
    "container_name",
    "base_directory",
    "bind_address",
    "http_port",
]
ALLOWED_STATES = {"started", "stopped", "restarted"}
KNOWN_OPTIONAL = {
    "state",
    "force_pull",
    "manage_docker",
    "site_check_path",
    "extra_environment",
}
RUNTIME_KEYS = {"grav_runtime", "grav_runtime_version", "runtime_version", "runtime"}
DOC_NETS = [
    ipaddress.ip_network("192.0.2.0/24"),
    ipaddress.ip_network("198.51.100.0/24"),
    ipaddress.ip_network("203.0.113.0/24"),
    ipaddress.ip_network("127.0.0.0/8"),
]

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


def is_doc_addr(value: str) -> bool:
    try:
        addr = ipaddress.ip_address(value)
    except ValueError:
        return False
    return any(addr in net for net in DOC_NETS)


def collect_hosts(inv: dict) -> list[str]:
    """Retourne les hôtes du groupe grav_servers, où qu'il soit dans l'arbre."""
    hosts: list[str] = []

    def walk(groups: dict) -> None:
        if not isinstance(groups, dict):
            return
        for name, body in groups.items():
            body = body or {}
            if name == "grav_servers":
                hosts.extend((body.get("hosts") or {}).keys())
            walk(body.get("children") or {})

    root = (inv or {}).get("all", {}) or {}
    walk({"all": root})
    return sorted(set(hosts))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--inventory", required=True)
    ap.add_argument("--context", choices=["example", "production"], default="example")
    args = ap.parse_args()

    inv_path = args.inventory
    inv_dir = os.path.dirname(inv_path)
    reg_path = os.path.join(inv_dir, "group_vars", "all", "grav_sites.yml")

    check(os.path.isfile(inv_path), f"inventaire présent : {inv_path}",
          f"inventaire introuvable : {inv_path}")
    check(os.path.isfile(reg_path), f"registre présent : {reg_path}",
          f"registre introuvable : {reg_path}")
    if errors:
        return finish()

    inv = load_yaml(inv_path)
    reg_doc = load_yaml(reg_path)

    # --- GSO-REQ-128 : dictionnaire racine unique `grav_sites` ---
    check(
        isinstance(reg_doc, dict) and list(reg_doc.keys()) == ["grav_sites"],
        "registre : unique clé racine `grav_sites`",
        f"registre : clés racines inattendues {list((reg_doc or {}).keys())}",
    )
    sites = (reg_doc or {}).get("grav_sites") or {}
    hosts = collect_hosts(inv)

    check(len(hosts) > 0, f"inventaire : {len(hosts)} hôte(s) dans grav_servers",
          "inventaire : groupe grav_servers vide ou absent")

    # --- GSO-REQ-013 : correspondance totale hôtes <-> entrées ---
    host_set, site_set = set(hosts), set(sites.keys())
    check(host_set == site_set,
          f"correspondance totale hôtes/registre ({len(host_set)} clés)",
          f"correspondance rompue : hôtes sans entrée={sorted(host_set - site_set)} ; "
          f"entrées sans hôte={sorted(site_set - host_set)}")

    # --- GSO-REQ-068/100 : adresses d'inventaire documentaires en contexte example ---
    if args.context == "example":
        allb = (inv or {}).get("all", {})
        gs = (allb.get("children", {}) or {}).get("grav_servers", {}) or {}
        for h, hv in (gs.get("hosts") or {}).items():
            ah = str((hv or {}).get("ansible_host", ""))
            check(is_doc_addr(ah),
                  f"{h}: ansible_host documentaire ({ah})",
                  f"{h}: ansible_host non documentaire en contexte example ({ah})")

    # --- Validation entrée par entrée ---
    seen = {"project_name": {}, "container_name": {}, "base_directory": {}, "endpoint": {}}
    for key, entry in sites.items():
        entry = entry or {}
        pfx = f"{key}"

        for field in MANDATORY:
            present = field in entry
            value = entry.get(field)
            non_empty = field == "digest" or (value not in (None, "", {}))
            check(present and non_empty,
                  f"{pfx}: champ obligatoire `{field}` présent",
                  f"{pfx}: champ obligatoire `{field}` absent ou vide")

        unknown = set(entry) - set(MANDATORY) - KNOWN_OPTIONAL
        check(not unknown, f"{pfx}: aucun champ inconnu",
              f"{pfx}: champ(s) hors schéma {sorted(unknown)}")

        runtime_leak = set(entry) & RUNTIME_KEYS
        check(not runtime_leak,
              f"{pfx}: pas de version de runtime déclarée",
              f"{pfx}: déclaration de runtime interdite {sorted(runtime_leak)} (GSO-REQ-011)")

        image = str(entry.get("image", ""))
        last_seg = image.rsplit("/", 1)[-1]
        check(":" not in last_seg and "@" not in last_seg,
              f"{pfx}: image sans tag ni digest incorporé",
              f"{pfx}: image avec tag/digest incorporé ({image}) (GSO-REQ-010)")
        check("latest" not in image.lower().split("/"),
              f"{pfx}: image sans `latest`",
              f"{pfx}: image utilise `latest` ({image}) (GSO-REQ-020)")

        version = entry.get("version")
        check(isinstance(version, str) and version.strip() not in ("", "latest"),
              f"{pfx}: version humaine explicite ({version})",
              f"{pfx}: version manquante, vide ou `latest` ({version!r}) (GSO-REQ-021/154)")

        digest = entry.get("digest", "")
        check(digest == "" or re.fullmatch(r"sha256:[0-9a-f]{64}", str(digest)) is not None,
              f"{pfx}: digest vide ou sha256 valide",
              f"{pfx}: digest mal formé ({digest!r})")

        addr = str(entry.get("bind_address", ""))
        try:
            ipaddress.IPv4Address(addr)
            addr_ok = True
        except ipaddress.AddressValueError:
            addr_ok = False
        check(addr_ok, f"{pfx}: bind_address IPv4 littérale ({addr})",
              f"{pfx}: bind_address non IPv4 ({addr!r}) (GSO-REQ-065)")
        if args.context == "example" and addr_ok:
            check(is_doc_addr(addr),
                  f"{pfx}: bind_address documentaire",
                  f"{pfx}: bind_address non documentaire en contexte example ({addr})")

        port = entry.get("http_port")
        check(isinstance(port, int) and 1 <= port <= 65535,
              f"{pfx}: http_port valide ({port})",
              f"{pfx}: http_port invalide ({port!r}) (GSO-REQ-065)")

        base = str(entry.get("base_directory", ""))
        check(base.startswith("/") and not re.match(r"^/(home|Users|root)/", base),
              f"{pfx}: base_directory chemin absolu non workstation",
              f"{pfx}: base_directory suspect ({base!r})")

        state = entry.get("state", "started")
        check(state in ALLOWED_STATES,
              f"{pfx}: state non destructif ({state})",
              f"{pfx}: state hors {sorted(ALLOWED_STATES)} ({state!r}) (GSO-REQ-051)")

        for field, label in (("project_name", "project_name"),
                             ("container_name", "container_name"),
                             ("base_directory", "base_directory")):
            val = entry.get(field)
            if val in (None, ""):
                continue
            prev = seen[field].get(val)
            check(prev is None,
                  f"{pfx}: {label} unique",
                  f"{pfx}: {label} `{val}` déjà utilisé par `{prev}` (GSO-REQ-050)")
            seen[field][val] = key

        endpoint = f"{addr}:{port}"
        prev = seen["endpoint"].get(endpoint)
        check(prev is None,
              f"{pfx}: endpoint {endpoint} unique",
              f"{pfx}: endpoint {endpoint} déjà utilisé par `{prev}` (GSO-REQ-050)")
        seen["endpoint"][endpoint] = key

    # --- GSO-REQ-052 : disjonction avec le registre retiré (si présent) ---
    retired_path = os.path.normpath(
        os.path.join(inv_dir or ".", "..", "..", "registry", "retired-sites.yml")
    )
    if os.path.isfile(retired_path):
        retired = (load_yaml(retired_path) or {}).get("retired_grav_sites") or {}
        overlap = site_set & set(retired.keys())
        check(not overlap, "aucune clé active dans retired_grav_sites",
              f"clés simultanément actives et retirées : {sorted(overlap)} (GSO-REQ-052)")
    else:
        print("SKIP  registry/retired-sites.yml absent (attendu avant le lot L8)")

    return finish()


def finish() -> int:
    print("----")
    if errors:
        print(f"registry_lint : {len(errors)} erreur(s) sur {checks} contrôles")
        return 1
    print(f"registry_lint : {checks} contrôles OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
