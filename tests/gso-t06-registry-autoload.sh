#!/usr/bin/env bash
# GSO-T06 — Registre actif chargé automatiquement.
#
# Vérifie que `grav_sites` est chargé par le mécanisme standard
# `group_vars/all/` d'Ansible (sans `include_vars`, sans chemin de
# workstation), et que le registre d'exemple est structurellement cohérent
# avec l'inventaire (GSO-REQ-012, GSO-REQ-013, GSO-REQ-048, GSO-REQ-050,
# GSO-REQ-128).

TEST_ID="GSO-T06"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

INV="inventories/example/hosts.yml"
REG="inventories/example/group_vars/all/grav_sites.yml"

for f in "$INV" "$REG"; do
  [ -f "$f" ] || { fail "fichier absent : $f"; finish; }
done

tmp="$(gso_mktemp_dir t06)"
trap 'rm -rf "$tmp"' EXIT

# --- 1. Emplacement : group_vars/all/ adjacent à l'inventaire ---
case "$REG" in
  "$(dirname "$INV")"/group_vars/all/*) pass "registre dans group_vars/all/ adjacent à l'inventaire" ;;
  *) fail "registre hors group_vars/all/ adjacent : $REG" ;;
esac

# --- 2. Chargement automatique effectif (via ansible-inventory) ---
if ! ansible-inventory -i "$INV" --list > "$tmp/inv.json" 2> "$tmp/err"; then
  sed 's/^/      | /' "$tmp/err"
  fail "ansible-inventory a échoué"
  finish
fi

if python3 - "$tmp/inv.json" "$REG" <<'PY'
import json
import sys

try:
    import yaml
except ImportError:
    print("      PyYAML absent")
    sys.exit(2)

data = json.load(open(sys.argv[1], encoding="utf-8"))
on_disk = (yaml.safe_load(open(sys.argv[2], encoding="utf-8")) or {}).get("grav_sites")

rc = 0
hosts = data.get("grav_servers", {}).get("hosts", [])
if not hosts:
    print("      aucun hôte grav_servers")
    sys.exit(1)

for h in hosts:
    loaded = data.get("_meta", {}).get("hostvars", {}).get(h, {}).get("grav_sites")
    if loaded is None:
        print(f"      {h}: grav_sites non chargé automatiquement")
        rc = 1
    elif loaded != on_disk:
        print(f"      {h}: grav_sites chargé != contenu du fichier")
        rc = 1
    else:
        print(f"      {h}: grav_sites chargé automatiquement depuis group_vars/all/")

sys.exit(rc)
PY
then
  pass "grav_sites chargé automatiquement pour tous les hôtes"
else
  fail "grav_sites non chargé automatiquement"
fi

# --- 3. Aucun include_vars du registre (GSO-REQ-012) ---
iv="$(git grep -nIE 'include_vars.*(grav_sites|group_vars)' -- ':!tests/' ':!docs/' || true)"
if [ -n "$iv" ]; then
  fail "include_vars du registre détecté"
  printf '%s\n' "$iv" | sed 's/^/      | /'
else
  pass "aucun include_vars du registre"
fi

# --- 4. Cohérence structurelle du registre (validateur statique L1) ---
if python3 "$GSO_VALIDATE" registry --inventory "$INV" --context example \
  | sed 's/^/      /'; then
  pass "validateur registre : registre d'exemple cohérent"
else
  fail "validateur registre : incohérence détectée"
fi

# --- 5. Cas négatif : le validateur DOIT rejeter une fixture cassée ---
FIX="$DIR/fixtures/l1-broken/inventories/example/hosts.yml"
if [ -f "$FIX" ]; then
  if python3 "$GSO_VALIDATE" registry --inventory "$FIX" --context example \
      > "$tmp/neg.out" 2>&1; then
    fail "validateur registre accepte à tort la fixture volontairement cassée"
  else
    n="$(grep -c '^FAIL' "$tmp/neg.out" || true)"
    pass "validateur registre rejette la fixture cassée ($n écart(s) détecté(s))"
  fi
else
  fail "fixture négative absente : $FIX"
fi

finish
