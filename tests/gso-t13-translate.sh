#!/usr/bin/env bash
# GSO-T13 — Traduction du registre et de `grav_secrets` vers `grav_*`.
#
# Exécute le VRAI chemin opérateur (scripts/deploy.sh -> sélecteur -> verrou
# -> deploy-site.yml -> assertions -> préflight -> traduction) mais remplace
# `sepp67.grav_site` par une DOUBLURE qui capture les variables transmises,
# SANS conteneur ni connexion (GSO-REQ-015, 018, 061, 063, 087, 111, 203).

TEST_ID="GSO-T13"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

tmp="$(gso_mktemp_dir t13)"
trap 'rm -rf "$tmp"' EXIT
gso_isolate_runtime "$tmp"        # verrous de site-mutation.sh confines dans $tmp
T="$tmp/tree"
l4_tmptree l3-prod-ok "$T"
gso_spy_role_into "$T"

# Vault synthétique (clair) aligné sur le registre de la fixture.
cat > "$T/inventories/production/group_vars/all/vault.yml" <<'YML'
vault_grav_sites:
  grav-alpha:
    admin_user: alpha-admin
    admin_password: SYNTH-T13-ALPHA-PW
    admin_email: alpha@example.invalid
    admin_fullname: Alpha Admin
    admin_type: both
    secrets:
      - name: email-private.php
        content: "SYNTH-T13-SECRET-ALPHA"
  grav-beta:
    admin_user: beta-admin
    admin_password: SYNTH-T13-BETA-PW
    admin_email: beta@example.invalid
vault_retired_grav_sites: {}
YML

mkdir -p "$tmp/spy"
if ( cd "$T" && GSO_SPY_OUTPUT="$tmp/spy" bash scripts/deploy.sh grav-alpha ) > "$tmp/run.log" 2>&1; then
  pass "chemin opérateur complet exécuté (doublure), rc=0"
else
  sed 's/^/      | /' "$tmp/run.log" | tail -15
  fail "le chemin opérateur a échoué"
  finish
fi

spy="$tmp/spy/grav-alpha.json"
[ -f "$spy" ] || { fail "la doublure n'a pas capturé les variables"; finish; }

# --- Traduction des champs non secrets ---
python3 - "$spy" "$T/inventories/production/group_vars/all/grav_sites.yml" <<'PY'
import json, sys
try:
    import yaml
except ImportError:
    print("      PyYAML absent"); sys.exit(2)
spy = json.load(open(sys.argv[1]))
reg = (yaml.safe_load(open(sys.argv[2])) or {})["grav_sites"]["grav-alpha"]
want = {
    "grav_image": reg["image"], "grav_version": reg["version"],
    "grav_digest": reg.get("digest", ""), "grav_container_name": reg["container_name"],
    "grav_base_directory": reg["base_directory"], "grav_bind_address": reg["bind_address"],
    "grav_state": reg.get("state", "started"),
    "grav_site_check_path": reg.get("site_check_path", "/"),
}
rc = 0
for k, v in want.items():
    got = spy.get(k)
    if str(got) != str(v):
        print(f"      FAIL {k}: attendu {v!r}, obtenu {got!r}"); rc = 1
    else:
        print(f"      OK   {k} = {got}")
if int(str(spy.get("grav_http_port"))) != int(reg["http_port"]):
    print(f"      FAIL grav_http_port: {spy.get('grav_http_port')!r} != {reg['http_port']}"); rc = 1
else:
    print(f"      OK   grav_http_port = {spy.get('grav_http_port')}")
sys.exit(rc)
PY
[ $? -eq 0 ] && pass "traduction exacte du registre non secret vers grav_*" \
             || fail "traduction du registre incorrecte"

# --- grav_secrets sous la forme name + content, jamais src ---
python3 - "$spy" <<'PY'
import json, sys
spy = json.load(open(sys.argv[1]))
sec = spy.get("grav_secrets")
rc = 0
if not isinstance(sec, list) or len(sec) != 1:
    print(f"      FAIL grav_secrets doit être une liste d'un élément : {sec!r}"); sys.exit(1)
e = sec[0]
if set(e.keys()) != {"name", "content"}:
    print(f"      FAIL clés {sorted(e)} — attendu exactement name + content"); rc = 1
if "src" in e:
    print("      FAIL forme `src` présente"); rc = 1
if e.get("name") != "email-private.php" or e.get("content") != "SYNTH-T13-SECRET-ALPHA":
    print(f"      FAIL contenu du secret altéré : {e!r}"); rc = 1
print("      OK   grav_secrets = [{name, content}], aucune transformation, pas de src")
sys.exit(rc)
PY
[ $? -eq 0 ] && pass "grav_secrets traduit tel quel (name + content), jamais src" \
             || fail "grav_secrets mal traduit"

# --- Bootstrap administrateur tri-state ---
python3 - "$spy" <<'PY'
import json, sys
spy = json.load(open(sys.argv[1]))
tri = [spy.get("grav_admin_user"), spy.get("grav_admin_password"), spy.get("grav_admin_email")]
if all(tri):
    print("      OK   tri-state complet (user+password+email)"); sys.exit(0)
print(f"      FAIL tri-state incohérent : {tri!r}"); sys.exit(1)
PY
[ $? -eq 0 ] && pass "bootstrap administrateur tri-state transmis complet" \
             || fail "bootstrap administrateur incohérent"

# --- Une seule invocation ---
n="$(grep -c . "$tmp/spy/_calls.log" 2>/dev/null || echo 0)"
[ "$n" = "1" ] && pass "rôle invoqué exactement une fois (GSO-REQ-087)" \
               || fail "rôle invoqué $n fois"

# --- Aucune fuite de valeur secrète dans les sorties ---
if grep -qE 'SYNTH-T13-ALPHA-PW|SYNTH-T13-SECRET-ALPHA|SYNTH-T13-BETA-PW' "$tmp/run.log"; then
  fail "fuite d'une valeur secrète dans la sortie du déploiement"
else
  pass "aucune valeur secrète dans la sortie (no_log)"
fi

# --- Second contrôle de cible DANS le playbook : refus d'un --limit incorrect ---
# (deploy-site.yml appelé directement pour contourner le sélecteur : l'assertion
#  interne doit à elle seule bloquer avant toute invocation du rôle.)
pb_neg() {  # <label> <limit-args...>
  local label="$1"; shift
  local spy="$tmp/spyneg-$RANDOM" rc=0
  mkdir -p "$spy"
  ( cd "$T" && GSO_SPY_OUTPUT="$spy" ANSIBLE_ROLES_PATH="$T/roles" \
      ansible-playbook -i inventories/production/hosts.yml playbooks/deploy-site.yml "$@" ) \
      > "$tmp/neg.log" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ]; then
    fail "second contrôle « $label » : playbook accepté à tort"
  elif [ -f "$spy/_calls.log" ]; then
    fail "second contrôle « $label » : rôle invoqué malgré le --limit incorrect"
  else
    pass "second contrôle « $label » : refusé avant invocation du rôle"
  fi
}
pb_neg "sans --limit"          # aucun ansible_limit
pb_neg "--limit all" --limit all
pb_neg "--limit multiple" --limit grav-alpha,grav-beta
pb_neg "--limit groupe" --limit grav_servers

gso_assert_runtime_clean

finish
