#!/usr/bin/env bash
# GSO-T20 — `check-all` non mutant, sans invocation du rôle (lot L6).
#
# 100 % local, déterministe, LECTURE SEULE. Prouve (contrat §13.7, §16.9,
# §18.10 ; GSO-REQ-090/104/119/124/125/144) :
#   - check-site.yml ET check-all.yml n'invoquent JAMAIS sepp67.grav_site
#     (aucun include_role / import_role) — garde statique ;
#   - aucune tâche mutante (docker run/rm/stop/... ; écriture de fichiers du
#     rôle ; pull) dans les playbooks de contrôle ;
#   - `check-all` parcourt tout `grav_servers` et agrège un verdict ;
#   - la cohérence déclarative du parc est vérifiée SANS connexion aux VM :
#     un registre incohérent fait échouer `check-all` avant tout parcours ;
#   - `check-all.sh` n'accepte aucun argument ; aucune variable de
#     confirmation ne peut transformer `check-all` en mutation (GSO-REQ-104) ;
#   - parc conforme -> code 0 ; un hôte en dérive -> code != 0 ;
#   - aucune valeur secrète dans la sortie ; aucun résidu.

TEST_ID="GSO-T20"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

tmp="$(gso_mktemp_dir t20)"
trap 'rm -rf "$tmp"' EXIT
gso_isolate_runtime "$tmp"

code_only() { grep -vE '^[[:space:]]*#' "$1"; }

# --------------------------------------------------------------------------
# 1. Gardes statiques sur les playbooks de contrôle
# --------------------------------------------------------------------------
# Capture d'abord (le `$( )` de `code_only` — un `grep -vE` externe — va à son
# terme), grep ensuite sur la valeur déjà capturée (here-string) — jamais
# `code_only "$f" | grep -q` : SIGPIPE possible sous `set -o pipefail` si un
# grep -q aval sort tôt -> faux négatif sur ce garde-fou.
for pb in check-site.yml check-all.yml; do
  f="playbooks/$pb"
  [ -f "$f" ] || { fail "playbook manquant : $pb"; continue; }
  fc="$(code_only "$f" || true)"
  if grep -qE '(include_role|import_role)' <<<"$fc"; then
    fail "$pb : invoque le rôle (interdit — GSO-REQ-090)"
  else
    pass "$pb : aucun include_role / import_role"
  fi
  if grep -qE 'gather_facts:[[:space:]]*false' "$f"; then
    pass "$pb : gather_facts false (GSO-REQ-124)"
  else
    fail "$pb : gather_facts non désactivé"
  fi
done
# cas négatif synthétique (fichier temporaire, dépôt courant jamais touché) :
# un include_role DOIT être détecté par cette même logique.
_neg="$tmp/sigpipe-neg-t20.yml"
printf 'tasks:\n  - include_role:\n      name: sepp67.grav_site\n' > "$_neg"
_neg_fc="$(code_only "$_neg" || true)"
grep -qE '(include_role|import_role)' <<<"$_neg_fc" \
  && pass "cas négatif : un include_role synthétique est bien détecté par cette logique" \
  || fail "cas négatif : un include_role synthétique n'est PAS détecté (faux négatif)"

# _shared/observe.yml (collecte partagée) : lecture seule uniquement
if git grep -nIE 'ansible\.builtin\.(copy|template|file|lineinfile|blockinfile|replace|shell)|state:[[:space:]]*(present|absent|started|stopped|restarted)|docker[[:space:]]+(run|rm|stop|start|restart|pull|create|kill)|force_pull|community\.docker' -- playbooks/check-site.yml playbooks/check-all.yml playbooks/_shared/observe.yml ; then
  fail "playbooks de contrôle : tâche potentiellement mutante détectée"
else
  pass "playbooks de contrôle : modules en lecture seule uniquement (slurp/stat/command/uri/set_fact/assert/debug)"
fi

# GSO-REQ-104 : aucune bascule de check-all vers une mutation
_ca_fc="$(code_only playbooks/check-all.yml || true)"
if grep -qE '_gso_intent|_shared/mutate\.yml|deploy-site\.yml|i_understand|--extra-vars|include_role|import_role' <<<"$_ca_fc"; then
  fail "check-all.yml : référence une intention mutante ou une confirmation de mutation"
else
  pass "check-all.yml : aucune bascule possible vers une mutation (GSO-REQ-104)"
fi
# cas négatif synthétique : une référence _gso_intent DOIT être détectée
_neg_intent='vars:
  _gso_intent: deploy'
grep -qE '_gso_intent|_shared/mutate\.yml|deploy-site\.yml|i_understand|--extra-vars|include_role|import_role' <<<"$_neg_intent" \
  && pass "cas négatif : une référence _gso_intent synthétique est bien détectée par cette logique" \
  || fail "cas négatif : une référence _gso_intent synthétique n'est PAS détectée (faux négatif)"

# le chemin de contrôle ne prend PAS le verrou de mutation
if grep -qE 'flock|site-mutation\.sh|/locks/' scripts/lib/site-check.sh scripts/check-site.sh scripts/check-all.sh; then
  fail "le chemin de contrôle acquiert le verrou de mutation (interdit : un check ne doit pas bloquer un déploiement)"
else
  pass "le chemin de contrôle ne prend aucun verrou de mutation"
fi

# --------------------------------------------------------------------------
# 2. check-all.sh : interface fermée
# --------------------------------------------------------------------------
if ( cd "$tmp" && bash "$REPO_ROOT/scripts/check-all.sh" un-argument ) >/dev/null 2>&1; then
  fail "check-all.sh a accepté un argument"
else
  pass "check-all.sh refuse tout argument"
fi
if grep -qE 'site-check\.sh"? +check-all\.yml' scripts/check-all.sh \
   && grep -qE 'site-check\.sh"? +check-site\.yml' scripts/check-site.sh; then
  pass "check-site.sh / check-all.sh passent par scripts/lib/site-check.sh (chemin commun)"
else
  fail "les wrappers de contrôle n'empruntent pas le chemin commun"
fi

# --------------------------------------------------------------------------
# 3. check-all de bout en bout (fausse CLI docker, lecture seule)
# --------------------------------------------------------------------------
gso_fake_docker_into "$tmp"
export PATH="$tmp/fakebin:$PATH"

mk_parc() {  # <mode: ok|drift|broken> -> echo path
  local mode="$1"
  local T="$tmp/parc-$mode-$RANDOM"
  l4_tmptree l3-prod-ok "$T"
  gso_spy_role_into "$T"
  mkdir -p "$T/sites/grav-alpha" "$T/sites/grav-beta" "$T/fakedocker"
  cat > "$T/inventories/production/hosts.yml" <<YML
all:
  children:
    grav_servers:
      hosts:
        grav-alpha: {ansible_connection: local, ansible_host: 127.0.0.1}
        grav-beta: {ansible_connection: local, ansible_host: 127.0.0.1}
YML
  cat > "$T/inventories/production/group_vars/all/grav_sites.yml" <<YML
grav_sites:
  grav-alpha:
    project_name: alpha
    image: reg.invalid/alpha
    version: "1.0.0"
    digest: ""
    container_name: gso-t20-alpha
    base_directory: $T/sites/grav-alpha
    bind_address: 127.0.0.1
    http_port: 18200
    state: started
    site_check_path: /
  grav-beta:
    project_name: beta
    image: reg.invalid/beta
    version: "3.1.0"
    digest: ""
    container_name: gso-t20-beta
    base_directory: $T/sites/grav-beta
    bind_address: 127.0.0.1
    http_port: 18201
    state: stopped
    site_check_path: /
YML
  cat > "$T/inventories/production/group_vars/all/vault.yml" <<YML
vault_grav_sites:
  grav-alpha: {admin_user: a, admin_password: SYNTH-T20-A-PW, admin_email: a@example.invalid}
  grav-beta: {admin_user: b, admin_password: SYNTH-T20-B-PW, admin_email: b@example.invalid}
vault_retired_grav_sites: {}
YML
  cat > "$T/sites/grav-alpha/.deployed_state.yml" <<'YML'
image: reg.invalid/alpha
declared_version: "1.0.0"
digest: ""
effective_reference: reg.invalid/alpha:1.0.0
deployed_at: "2026-09-01T10:00:00Z"
YML
  cat > "$T/sites/grav-beta/.deployed_state.yml" <<'YML'
image: reg.invalid/beta
declared_version: "3.1.0"
digest: ""
effective_reference: reg.invalid/beta:3.1.0
deployed_at: "2026-09-01T10:00:00Z"
YML
  printf '%s\n' '[{"Config":{"Image":"reg.invalid/alpha:1.0.0"},"State":{"Running":true,"Health":{"Status":"healthy"}},"NetworkSettings":{"Ports":{"18200/tcp":[{"HostPort":"18200"}]}}}]' > "$T/fakedocker/gso-t20-alpha.json"
  printf '%s\n' '[{"Config":{"Image":"reg.invalid/beta:3.1.0"},"State":{"Running":false,"Health":{"Status":"none"}},"NetworkSettings":{"Ports":{}}}]' > "$T/fakedocker/gso-t20-beta.json"
  case "$mode" in
    drift)  sed -i 's#reg.invalid/alpha:1.0.0#reg.invalid/alpha:0.0.9#' "$T/sites/grav-alpha/.deployed_state.yml" ;;
    broken) sed -i '/grav-beta:/,/site_check_path: \//d' "$T/inventories/production/group_vars/all/grav_sites.yml" ;;  # hôte sans entrée de registre
  esac
  echo "$T"
}

run_all() {  # <tree> -> "<rc> <logfile>"
  local T="$1" rc=0
  ( cd "$T" && FAKE_DOCKER_DIR="$T/fakedocker" bash scripts/check-all.sh ) > "$T.log" 2>&1 || rc=$?
  echo "$rc $T.log"
}

# --- 3a. parc conforme -> code 0, les deux hôtes vus ---
T="$(mk_parc ok)"
read -r rc log < <(run_all "$T")
[ "$rc" = 0 ] && pass "check-all parc conforme : code 0" || { sed 's/^/   | /' "$log" | tail -20; fail "parc conforme : code $rc"; }
grep -q 'grav-alpha : IN_SYNC' "$log" && grep -q 'grav-beta : IN_SYNC' "$log" \
  && pass "check-all a parcouru tout grav_servers (alpha + beta)" || fail "parcours du parc incomplet"
grep -qE 'SYNTH-T20-[AB]-PW' "$log" && fail "fuite d'une valeur secrète" || pass "aucune valeur secrète dans la sortie"
[ ! -e "$T/roles/sepp67.grav_site/_calls.log" ] && pass "rôle jamais invoqué par check-all" || fail "check-all a invoqué le rôle"
grep -q 'FAKE-DOCKER-REFUS' "$log" && fail "check-all a tenté une sous-commande docker mutante" || pass "check-all : aucune sous-commande docker mutante"

# --- 3b. non mutation : mtime des .deployed_state.yml inchangés ---
a1="$(stat -c %Y "$T/sites/grav-alpha/.deployed_state.yml")"; b1="$(stat -c %Y "$T/sites/grav-beta/.deployed_state.yml")"
_x=$(run_all "$T")
a2="$(stat -c %Y "$T/sites/grav-alpha/.deployed_state.yml")"; b2="$(stat -c %Y "$T/sites/grav-beta/.deployed_state.yml")"
{ [ "$a1" = "$a2" ] && [ "$b1" = "$b2" ]; } && pass "check-all : aucun .deployed_state.yml modifié (GSO-REQ-119)" || fail "check-all a modifié un fichier du rôle"

# --- 3c. un hôte en dérive -> code != 0, l'hôte est nommé ---
T="$(mk_parc drift)"
read -r rc log < <(run_all "$T")
{ [ "$rc" != 0 ] && grep -qE 'grav-alpha : REFERENCE_DRIFT' "$log" && grep -qE 'non conformes : grav-alpha' "$log"; } \
  && pass "check-all : un hôte en dérive -> code $rc, hôte nommé" || { sed 's/^/   | /' "$log" | tail -20; fail "dérive de parc mal signalée (rc=$rc)"; }

# --- 3d. registre incohérent -> échec AVANT tout parcours, sans contact VM ---
T="$(mk_parc broken)"
read -r rc log < <(run_all "$T")
{ [ "$rc" != 0 ] && ! grep -q 'grav-alpha : ' "$log"; } \
  && pass "registre incohérent -> check-all échoue avant le parcours (GSO-REQ-125), sans contact VM" \
  || { sed 's/^/   | /' "$log" | tail -15; fail "check-all n'a pas échoué fermé sur un registre incohérent (rc=$rc)"; }

# --- 3e. codes stables au rejeu ---
T="$(mk_parc ok)"
read -r r1 _ < <(run_all "$T"); read -r r2 _ < <(run_all "$T")
[ "$r1" = 0 ] && [ "$r2" = 0 ] && pass "check-all : code stable au rejeu" || fail "check-all : codes instables ($r1,$r2)"

# --- 3f. fixtures inchangées ---
cur="$(cd "$REPO_ROOT" && git status --porcelain -- tests/fixtures/)"
[ -z "$cur" ] && pass "fixtures inchangées" || fail "fixtures modifiées : $cur"

gso_assert_runtime_clean
finish
