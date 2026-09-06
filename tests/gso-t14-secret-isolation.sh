#!/usr/bin/env bash
# GSO-T14 — Secrets et secrets applicatifs du BON hôte uniquement, aucune
# fuite, cohérence structurelle registre / vault / inventory_hostname.
#
# Partage la preuve de GSO-REQ-204 avec GSO-T07. Chemin opérateur réel +
# DOUBLURE (aucun conteneur). GSO-REQ-024, 042, 061, 062, 092, 101, 204.

TEST_ID="GSO-T14"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

VAULT_OK='vault_grav_sites:
  grav-alpha:
    admin_user: alpha-admin
    admin_password: SYNTH-T14-ALPHA-PW
    admin_email: alpha@example.invalid
    secrets:
      - name: alpha-only.php
        content: "SYNTH-T14-ALPHA-CONTENT"
  grav-beta:
    admin_user: beta-admin
    admin_password: SYNTH-T14-BETA-PW
    admin_email: beta@example.invalid
    secrets:
      - name: beta-only.php
        content: "SYNTH-T14-BETA-CONTENT"
vault_retired_grav_sites: {}'

deploy_spy() {  # <site> <vault-yaml> ; echo "<rc> <spydir> <logfile>"
  local site="$1" vault="$2" T spy drc=0
  T="$tmp/$site-$RANDOM"; spy="$T.spy"
  mkdir -p "$spy"
  l4_tmptree l3-prod-ok "$T"
  gso_spy_role_into "$T"
  printf '%s\n' "$vault" > "$T/inventories/production/group_vars/all/vault.yml"
  ( cd "$T" && GSO_SPY_OUTPUT="$spy" bash scripts/deploy.sh "$site" ) > "$T.log" 2>&1 || drc=$?
  echo "$drc $spy $T.log"
}

# --- 1. Isolation : --limit grav-alpha -> secrets de alpha, pas de beta ---
read -r rc spy log < <(deploy_spy grav-alpha "$VAULT_OK")
if [ "$rc" = 0 ]; then pass "déploiement (doublure) de grav-alpha : rc=0"; else fail "échec grav-alpha"; finish; fi
python3 - "$spy/grav-alpha.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
names = [x["name"] for x in s.get("grav_secrets", [])]
ok = names == ["alpha-only.php"]
print("      grav_secrets =", names)
sys.exit(0 if ok else 1)
PY
[ $? -eq 0 ] && pass "grav-alpha ne reçoit QUE son propre secret" || fail "fuite inter-hôtes des secrets"
grep -qE 'SYNTH-T14-BETA' "$log" && { fail "valeur du secret de beta présente dans la sortie alpha"; } || pass "aucune trace du secret de beta dans la sortie alpha"

# --- 2. Réciproque : grav-beta ---
read -r rc spy log < <(deploy_spy grav-beta "$VAULT_OK")
[ "$rc" = 0 ] && pass "déploiement (doublure) de grav-beta : rc=0" || fail "échec grav-beta"
python3 -c '
import json,sys
s=json.load(open(sys.argv[1])); names=[x["name"] for x in s.get("grav_secrets",[])]
print("      grav_secrets =", names); sys.exit(0 if names==["beta-only.php"] else 1)
' "$spy/grav-beta.json"
[ $? -eq 0 ] && pass "grav-beta ne reçoit QUE son propre secret" || fail "fuite inter-hôtes des secrets (réciproque)"
grep -qE 'SYNTH-T14-ALPHA' "$log" && fail "valeur du secret de alpha présente dans la sortie beta" || pass "aucune trace du secret de alpha dans la sortie beta"

# --- 3. Aucune valeur secrète dans AUCUNE sortie capturée ---
if grep -rqE 'SYNTH-T14-ALPHA-PW|SYNTH-T14-BETA-PW|SYNTH-T14-ALPHA-CONTENT|SYNTH-T14-BETA-CONTENT' "$tmp"/*.log; then
  fail "fuite d'une valeur secrète dans une sortie de test"
  grep -rlE 'SYNTH-T14' "$tmp"/*.log | sed 's/^/      | /'
else
  pass "aucune valeur secrète (mot de passe / contenu) dans les sorties"
fi

# --- 4. Cohérence GSO-REQ-204 : le préflight structurel rejette les écarts ---
neg() {  # <label> <site> <vault> ; DOIT échouer sans invoquer la doublure
  local label="$1" site="$2" vault="$3"
  read -r rc spy log < <(deploy_spy "$site" "$vault")
  if [ "$rc" = 0 ]; then
    fail "cas négatif « $label » accepté à tort"
  elif [ -f "$spy/_calls.log" ]; then
    fail "cas négatif « $label » : la doublure a été invoquée malgré l'écart"
  else
    pass "cas négatif « $label » rejeté avant invocation du rôle"
  fi
}
neg "entrée de vault manquante" grav-alpha "$(printf '%s\n' "$VAULT_OK" | sed '/grav-alpha:/,/alpha@example.invalid/d')"
neg "tri-state administrateur partiel" grav-alpha 'vault_grav_sites:
  grav-alpha: {admin_user: u, admin_password: p}
  grav-beta: {admin_user: u, admin_password: p, admin_email: b@example.invalid}
vault_retired_grav_sites: {}'
neg "secret sous forme src" grav-alpha 'vault_grav_sites:
  grav-alpha:
    admin_user: u
    admin_password: p
    admin_email: a@example.invalid
    secrets: [{name: k.php, src: /etc/whatever}]
  grav-beta: {admin_user: u, admin_password: p, admin_email: b@example.invalid}
vault_retired_grav_sites: {}'

finish
