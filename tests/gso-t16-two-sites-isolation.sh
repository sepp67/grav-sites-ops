#!/usr/bin/env bash
# GSO-T16 — Deux sites déclarés : isolation des variables et des secrets à la
# traduction, SANS conteneur Docker réel (GSO-D07, GSO-REQ-142 versant
# traduction). La preuve fonctionnelle de deux instances réelles sur un même
# moteur appartient à `ansible-role-grav-site` (molecule/multi_instance) et
# n'est pas dupliquée ici — cohérent avec l'invariant « une VM par projet ».

TEST_ID="GSO-T16"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
T="$tmp/tree"
l4_tmptree l3-prod-ok "$T"          # registre = grav-alpha + grav-beta
gso_spy_role_into "$T"
cat > "$T/inventories/production/group_vars/all/vault.yml" <<'YML'
vault_grav_sites:
  grav-alpha:
    admin_user: a-adm
    admin_password: SYNTH-T16-A-PW
    admin_email: a@example.invalid
    secrets: [{name: a.php, content: "SYNTH-T16-A-CONTENT"}]
  grav-beta:
    admin_user: b-adm
    admin_password: SYNTH-T16-B-PW
    admin_email: b@example.invalid
    secrets: [{name: b.php, content: "SYNTH-T16-B-CONTENT"}]
vault_retired_grav_sites: {}
YML

containers_before="$(docker ps -aq 2>/dev/null | sort || true)"

run_one() {  # <site>
  local site="$1" spy="$tmp/spy-$1"
  mkdir -p "$spy"
  ( cd "$T" && GSO_SPY_OUTPUT="$spy" bash scripts/deploy.sh "$site" ) > "$tmp/$site.log" 2>&1
}

run_one grav-alpha
run_one grav-beta

# --- 1. Chaque exécution ne touche QUE son site ---
for s in grav-alpha grav-beta; do
  other=$([ "$s" = grav-alpha ] && echo grav-beta || echo grav-alpha)
  if [ -f "$tmp/spy-$s/$s.json" ] && [ ! -f "$tmp/spy-$s/$other.json" ]; then
    pass "$s : la doublure ne capture que $s (jamais $other)"
  else
    fail "$s : capture croisée détectée"
  fi
  calls="$(grep -c . "$tmp/spy-$s/_calls.log" 2>/dev/null || echo 0)"
  [ "$calls" = 1 ] && pass "$s : rôle invoqué exactement une fois" || fail "$s : $calls invocations"
done

# --- 2. Les deux jeux de variables sont disjoints (secrets + mots de passe) ---
python3 - "$tmp/spy-grav-alpha/grav-alpha.json" "$tmp/spy-grav-beta/grav-beta.json" <<'PY'
import json, sys
a = json.load(open(sys.argv[1])); b = json.load(open(sys.argv[2]))
an = [x["name"] for x in a.get("grav_secrets", [])]
bn = [x["name"] for x in b.get("grav_secrets", [])]
ac = [x["content"] for x in a.get("grav_secrets", [])]
bc = [x["content"] for x in b.get("grav_secrets", [])]
rc = 0
if an != ["a.php"] or bn != ["b.php"]:
    print(f"      FAIL noms de secrets croisés : {an} / {bn}"); rc = 1
if set(ac) & set(bc):
    print("      FAIL contenus de secrets partagés"); rc = 1
if a.get("grav_container_name") == b.get("grav_container_name"):
    print("      FAIL même container_name pour les deux sites"); rc = 1
if a.get("grav_admin_password") == b.get("grav_admin_password"):
    print("      FAIL même mot de passe admin pour les deux sites"); rc = 1
if rc == 0:
    print("      OK   variables et secrets des deux sites entièrement disjoints")
sys.exit(rc)
PY
[ $? -eq 0 ] && pass "isolation complète des variables et secrets entre les deux sites" \
             || fail "isolation des deux sites rompue"

# --- 3. Aucun conteneur Docker réel créé ---
containers_after="$(docker ps -aq 2>/dev/null | sort || true)"
if [ "$containers_before" = "$containers_after" ]; then
  pass "aucun conteneur Docker créé (doublure — la liste docker ps -a est inchangée)"
else
  fail "des conteneurs ont été créés : $(comm -13 <(echo "$containers_before") <(echo "$containers_after"))"
fi

# --- 4. Aucune fuite de valeur secrète ---
if grep -rqE 'SYNTH-T16-[AB]-(PW|CONTENT)' "$tmp"/grav-*.log; then
  fail "fuite d'une valeur secrète dans une sortie"
else
  pass "aucune valeur secrète dans les sorties des deux déploiements"
fi

# --- 5. Pas de preuve multi-conteneurs dupliquée dans grav-sites-ops ---
if git grep -qIE 'multi_instance|deux conteneurs réels|two real containers' -- 'playbooks/' 'scripts/'; then
  fail "grav-sites-ops tente de prouver le multi-instance réel (doit rester au rôle)"
else
  pass "aucune preuve multi-instance réelle dans grav-sites-ops (déléguée au rôle, GSO-D07)"
fi

finish
