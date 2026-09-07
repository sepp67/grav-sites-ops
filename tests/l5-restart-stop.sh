#!/usr/bin/env bash
# L5 — Comportement de restart et stop (preuve L5, sans numéro GSO-T :
# le préflight ne prévoit aucun scénario GSO-T dédié à L5).
#
# 100 % local, déterministe, DOUBLURE du rôle : aucun conteneur Docker créé,
# arrêté ou redémarré. Prouve : une invocation unique par intention ; l'état
# exact transmis au rôle ; l'isolation du site ; le refus (SITE absent, arg
# en trop, cible invalide/absente/retirée/incohérente) sans invocation du
# rôle ; le MÊME verrou que deploy ; l'échec concurrent (code 75) sans
# invocation ; la libération du verrou après succès et après échec ;
# l'absence de fuite de secret ; l'absence de modification des fixtures.
#
# GSO-REQ-088 (restart : version/digest inchangés) et GSO-REQ-089 (stop :
# aucune suppression — aucune orchestration destructive).

TEST_ID="L5-RESTART-STOP"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"; rm -f "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/grav-sites-ops/locks/grav-alpha.lock"' EXIT

VAULT='vault_grav_sites:
  grav-alpha:
    admin_user: alpha-admin
    admin_password: SYNTH-L5-ALPHA-PW
    admin_email: alpha@example.invalid
    secrets:
      - name: alpha-only.php
        content: "SYNTH-L5-ALPHA-CONTENT"
  grav-beta:
    admin_user: beta-admin
    admin_password: SYNTH-L5-BETA-PW
    admin_email: beta@example.invalid
    secrets:
      - name: beta-only.php
        content: "SYNTH-L5-BETA-CONTENT"
vault_retired_grav_sites: {}'

containers_before="$(docker ps -aq 2>/dev/null | sort || true)"

mk_tree() {  # -> echo path
  local T="$tmp/tree-$RANDOM"
  l4_tmptree l3-prod-ok "$T"
  gso_spy_role_into "$T"
  printf '%s\n' "$VAULT" > "$T/inventories/production/group_vars/all/vault.yml"
  echo "$T"
}

RUN_N=0
run() {  # <tree> <wrapper> <args...> -> "<rc> <spydir> <logfile>"
  local T="$1"; shift
  local wrapper="$1"; shift
  RUN_N=$((RUN_N + 1))
  local spy="$T.spy.$RUN_N" log="$T.log.$RUN_N" rc=0
  mkdir -p "$spy"
  ( cd "$T" && GSO_SPY_OUTPUT="$spy" bash "scripts/$wrapper" "$@" ) > "$log" 2>&1 || rc=$?
  echo "$rc $spy $log"
}

# --------------------------------------------------------------------------
# 1. restart : état 'restarted', version/digest INCHANGÉS, 1 invocation
# --------------------------------------------------------------------------
T="$(mk_tree)"
read -r rc spy log < <(run "$T" restart-site.sh grav-alpha)
if [ "$rc" = 0 ]; then pass "restart-site.sh grav-alpha : rc=0"; else sed 's/^/      | /' "$log" | tail -12; fail "restart a échoué"; fi
python3 - "$spy/grav-alpha.json" "$T/inventories/production/group_vars/all/grav_sites.yml" <<'PY'
import json, sys, yaml
s = json.load(open(sys.argv[1]))
reg = yaml.safe_load(open(sys.argv[2]))["grav_sites"]["grav-alpha"]
rc = 0
if s.get("grav_state") != "restarted":
    print(f"      FAIL grav_state = {s.get('grav_state')!r} (attendu 'restarted')"); rc = 1
for k in ("version", "digest", "container_name", "base_directory", "image"):
    want = reg.get(k, "")
    if str(s.get("grav_" + k)) != str(want):
        print(f"      FAIL grav_{k} = {s.get('grav_'+k)!r} != registre {want!r}"); rc = 1
if rc == 0:
    print("      OK   grav_state=restarted ; version/digest/image/container/base_directory inchangés (GSO-REQ-088)")
sys.exit(rc)
PY
[ $? -eq 0 ] && pass "restart : traduction fermée conforme (GSO-REQ-088)" || fail "restart : traduction incorrecte"
n="$(grep -c . "$spy/_calls.log" 2>/dev/null || echo 0)"
[ "$n" = 1 ] && pass "restart : rôle invoqué exactement une fois" || fail "restart : $n invocations"
grep -qE 'SYNTH-L5-(ALPHA|BETA)' "$log" && fail "restart : fuite d'une valeur secrète" || pass "restart : aucune valeur secrète dans la sortie"
python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); sys.exit(0 if [x["name"] for x in s.get("grav_secrets",[])]==["alpha-only.php"] else 1)' "$spy/grav-alpha.json" \
  && pass "restart : seul le secret de grav-alpha est transmis" || fail "restart : fuite inter-hôtes"

# --------------------------------------------------------------------------
# 2. stop : état 'stopped', aucune orchestration destructive, 1 invocation
# --------------------------------------------------------------------------
T="$(mk_tree)"
read -r rc spy log < <(run "$T" stop-site.sh grav-beta)
[ "$rc" = 0 ] && pass "stop-site.sh grav-beta : rc=0" || { sed 's/^/      | /' "$log" | tail -12; fail "stop a échoué"; }
st="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("grav_state"))' "$spy/grav-beta.json" 2>/dev/null)"
[ "$st" = stopped ] && pass "stop : grav_state = stopped" || fail "stop : grav_state = '$st'"
n="$(grep -c . "$spy/_calls.log" 2>/dev/null || echo 0)"
[ "$n" = 1 ] && pass "stop : rôle invoqué exactement une fois" || fail "stop : $n invocations"
# aucune tâche destructive dans stop-site.yml / mutate.yml / translate.yml
if git grep -nIE 'state:[[:space:]]*absent|docker_compose_v2.*down|--volumes|remove_volumes|docker[[:space:]]+rm|prune' -- playbooks/ ; then
  fail "stop : orchestration destructive présente dans les playbooks"
else
  pass "stop : aucune orchestration destructive dans les playbooks (GSO-REQ-089)"
fi
grep -qE 'SYNTH-L5-(ALPHA|BETA)' "$log" && fail "stop : fuite d'une valeur secrète" || pass "stop : aucune valeur secrète dans la sortie"

# --------------------------------------------------------------------------
# 3. Refus : SITE absent, argument en trop, cible invalide/inconnue/retirée/incohérente
# --------------------------------------------------------------------------
neg() {  # <label> <wrapper> <args...>
  local label="$1"; shift; local w="$1"; shift
  local T rc spy
  T="$(mk_tree)"; spy="$T.negspy-$RANDOM"; mkdir -p "$spy"
  ( cd "$T" && GSO_SPY_OUTPUT="$spy" bash "scripts/$w" "$@" ) > "$T.neglog" 2>&1 && rc=0 || rc=$?
  if [ "$rc" -eq 0 ]; then
    fail "refus « $label » : accepté à tort"
  elif [ -f "$spy/_calls.log" ]; then
    fail "refus « $label » : rôle invoqué malgré le refus"
  else
    pass "refus « $label » : rc=$rc, rôle non invoqué"
  fi
}
neg "restart sans SITE"            restart-site.sh
neg "restart argument en trop"     restart-site.sh grav-alpha extra
neg "restart SITE invalide (shell)" restart-site.sh 'grav-$(id)'
neg "restart cible inconnue"       restart-site.sh grav-zeta
neg "restart cible retirée"        restart-site.sh grav-gamma
neg "stop sans SITE"               stop-site.sh
neg "stop argument en trop"        stop-site.sh grav-beta -e grav_state=absent
neg "stop --limit"                 stop-site.sh grav-beta --limit all

# incohérence registre : fixture dédiée
Tb="$tmp/broken"; l4_tmptree l3-prod-broken-registry "$Tb"; gso_spy_role_into "$Tb"
printf '%s\n' "$VAULT" > "$Tb/inventories/production/group_vars/all/vault.yml"
sb="$Tb.spy"; mkdir -p "$sb"
( cd "$Tb" && GSO_SPY_OUTPUT="$sb" bash scripts/restart-site.sh grav-alpha ) >/dev/null 2>&1 && rc=0 || rc=$?
if [ "$rc" -ne 0 ] && [ ! -f "$sb/_calls.log" ]; then
  pass "refus « restart sur registre incohérent » : rc=$rc, rôle non invoqué"
else
  fail "restart accepté sur un registre incohérent"
fi

# --------------------------------------------------------------------------
# 4. MÊME verrou que deploy — échec concurrent (code 75) sans invocation
# --------------------------------------------------------------------------
lock_dir="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/grav-sites-ops/locks"
grep -q 'lock_base.*grav-sites-ops/locks' scripts/lib/site-mutation.sh \
  && grep -q '\${SITE}\.lock' scripts/lib/site-mutation.sh \
  && pass "verrou unique par site, partagé par deploy/restart/stop (même fichier)" \
  || fail "le verrou n'est pas partagé par les trois intentions"

T="$(mk_tree)"; spy="$T.lockspy"; mkdir -p "$spy"
mkdir -p "$lock_dir"
exec 8>"$lock_dir/grav-alpha.lock"; flock 8
( cd "$T" && GSO_SPY_OUTPUT="$spy" bash scripts/restart-site.sh grav-alpha ) > "$T.lockneg" 2>&1 && rc=0 || rc=$?
flock -u 8; exec 8>&-
if [ "$rc" = 75 ] && [ ! -f "$spy/_calls.log" ]; then
  pass "restart concurrent (verrou tenu) : code 75, rôle non invoqué"
else
  fail "concurrence restart mal gérée (rc=$rc)"
fi

# verrou libéré après le succès de restart (§1) et après un échec
T="$(mk_tree)"
FAKE_AP="$tmp/fakebin"; mkdir -p "$FAKE_AP"
printf '#!/usr/bin/env bash\nexit "${FAKE_AP_RC:-0}"\n' > "$FAKE_AP/ansible-playbook"; chmod +x "$FAKE_AP/ansible-playbook"
( cd "$T" && PATH="$FAKE_AP:$PATH" FAKE_AP_RC=3 bash scripts/restart-site.sh grav-alpha ) >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" = 3 ] && pass "restart : code d'échec du playbook propagé (rc=3, non masqué)" || fail "restart : code d'échec non propagé (rc=$rc)"
if ( exec 7>"$lock_dir/grav-alpha.lock"; flock -n 7 ); then
  pass "verrou libéré après échec de restart"
else
  fail "verrou resté tenu après échec de restart"
fi

# --------------------------------------------------------------------------
# 5. Aucune fixture modifiée, aucun conteneur Docker touché
# --------------------------------------------------------------------------
for f in l3-prod-ok l3-prod-broken-registry; do
  cur="$(cd "$REPO_ROOT" && git status --porcelain -- "tests/fixtures/$f")"
  [ -z "$cur" ] && pass "fixture tests/fixtures/$f inchangée" || { fail "fixture $f modifiée : $cur"; }
done
containers_after="$(docker ps -aq 2>/dev/null | sort || true)"
[ "$containers_before" = "$containers_after" ] \
  && pass "aucun conteneur Docker créé, arrêté ou redémarré pendant les tests L5" \
  || fail "la liste des conteneurs a changé : $(comm -3 <(echo "$containers_before") <(echo "$containers_after"))"

finish
