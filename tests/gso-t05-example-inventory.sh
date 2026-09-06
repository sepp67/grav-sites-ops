#!/usr/bin/env bash
# GSO-T05 — Inventaire d'exemple parsable.
#
# Vérifie que `inventories/example/hosts.yml` est syntaxiquement valide,
# expose le groupe `grav_servers`, et ne peut pas être confondu avec un
# inventaire de production (GSO-REQ-006, GSO-REQ-058, GSO-REQ-068).

TEST_ID="GSO-T05"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

INV="inventories/example/hosts.yml"

if [ ! -f "$INV" ]; then
  fail "inventaire d'exemple absent : $INV"
  finish
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- 1. Parsing Ansible ---
if ansible-inventory -i "$INV" --list > "$tmp/inv.json" 2> "$tmp/err"; then
  pass "ansible-inventory parse $INV"
else
  sed 's/^/      | /' "$tmp/err"
  fail "inventaire non parsable"
  finish
fi

# --- 2. Structure : groupe grav_servers, hôtes, ansible_host ---
if python3 - "$tmp/inv.json" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1], encoding="utf-8"))
rc = 0

if "grav_servers" not in data:
    print("      groupe grav_servers absent")
    rc = 1
else:
    hosts = data["grav_servers"].get("hosts", [])
    if not hosts:
        print("      grav_servers ne contient aucun hôte")
        rc = 1
    else:
        print(f"      grav_servers : {len(hosts)} hôte(s) ({', '.join(hosts)})")
    for h in hosts:
        hv = data.get("_meta", {}).get("hostvars", {}).get(h, {})
        if "ansible_host" not in hv:
            print(f"      {h}: ansible_host manquant")
            rc = 1
        else:
            print(f"      {h}: ansible_host = {hv['ansible_host']}")

extra = set(data) - {"_meta", "all", "ungrouped", "grav_servers"}
if extra:
    print(f"      groupes inattendus : {sorted(extra)}")
    rc = 1
else:
    print("      aucun groupe fonctionnel hors grav_servers")

sys.exit(rc)
PY
then
  pass "structure de l'inventaire d'exemple conforme"
else
  fail "structure de l'inventaire d'exemple non conforme"
fi

# --- 3. Non-confusion avec la production ---
if git ls-files | grep -q '^inventories/production/'; then
  fail "des fichiers inventories/production/ sont suivis (interdit à ce stade)"
else
  pass "aucun fichier inventories/production/ suivi"
fi

case "$INV" in
  */example/*) pass "l'inventaire vit sous inventories/example/" ;;
  *) fail "chemin d'inventaire inattendu : $INV" ;;
esac

finish
