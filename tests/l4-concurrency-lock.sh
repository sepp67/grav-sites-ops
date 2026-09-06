#!/usr/bin/env bash
# L4 — Verrou de concurrence de scripts/deploy.sh (GSO-REQ-096).
#
# Preuve d'un mécanisme L4, sans numéro GSO-T (traçabilité explicite,
# cohérent avec la convention du préflight pour L5/L9). Doublure locale de
# `ansible-playbook` : aucun conteneur, aucune connexion.
#
# Prouve : une tentative concurrente échoue proprement SANS lancer le rôle ;
# le verrou est libéré après succès ET après échec.

TEST_ID="L4-LOCK"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"; rm -f "${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/grav-sites-ops/locks/l4lock-"*.lock' EXIT

T="$tmp/tree"
l4_tmptree l3-prod-ok "$T"
gso_spy_role_into "$T"
cat > "$T/inventories/production/group_vars/all/vault.yml" <<'YML'
vault_grav_sites:
  grav-alpha: {admin_user: u, admin_password: p, admin_email: a@example.invalid}
  grav-beta: {admin_user: u, admin_password: p, admin_email: b@example.invalid}
vault_retired_grav_sites: {}
YML

# Doublure de ansible-playbook : journalise puis renvoie le code voulu.
mkdir -p "$tmp/fakebin"
cat > "$tmp/fakebin/ansible-playbook" <<'SH'
#!/usr/bin/env bash
echo "FAKE-ANSIBLE-PLAYBOOK $*" >> "$FAKE_AP_LOG"
exit "${FAKE_AP_RC:-0}"
SH
chmod +x "$tmp/fakebin/ansible-playbook"
export FAKE_AP_LOG="$tmp/ap.log"
: > "$FAKE_AP_LOG"

lock_dir="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/grav-sites-ops/locks"
run_deploy() {  # renvoie le code
  local rc=0
  ( cd "$T" && PATH="$tmp/fakebin:$PATH" bash scripts/deploy.sh grav-alpha ) > "$tmp/last.log" 2>&1 || rc=$?
  echo "$rc"
}

# --- 1. Déploiement nominal : la doublure ansible-playbook EST appelée ---
export FAKE_AP_RC=0
rc="$(run_deploy)"
if [ "$rc" = 0 ] && grep -q 'FAKE-ANSIBLE-PLAYBOOK.*--limit grav-alpha' "$FAKE_AP_LOG"; then
  pass "chemin nominal : verrou acquis puis ansible-playbook appelé avec --limit grav-alpha"
else
  sed 's/^/      | /' "$tmp/last.log" | tail -8
  fail "chemin nominal cassé (rc=$rc)"
fi

# --- 2. Verrou libéré après succès : une 2e exécution passe ---
: > "$FAKE_AP_LOG"
rc="$(run_deploy)"
[ "$rc" = 0 ] && grep -q FAKE "$FAKE_AP_LOG" \
  && pass "verrou libéré après succès (2e exécution aboutit)" \
  || fail "verrou non libéré après succès"

# --- 3. Tentative concurrente : verrou tenu -> échec propre, rôle NON lancé ---
: > "$FAKE_AP_LOG"
exec 8>"$lock_dir/grav-alpha.lock"
flock 8                                   # ce shell détient le verrou
rc="$(run_deploy)"                        # tentative concurrente
flock -u 8; exec 8>&-                     # libération
if [ "$rc" = 75 ] && [ ! -s "$FAKE_AP_LOG" ]; then
  pass "tentative concurrente : code 75, ansible-playbook JAMAIS appelé"
else
  fail "concurrence mal gérée (rc=$rc, ap.log $( [ -s "$FAKE_AP_LOG" ] && echo non-vide || echo vide ))"
fi

# --- 4. Verrou libéré après ÉCHEC du playbook ---
export FAKE_AP_RC=2
: > "$FAKE_AP_LOG"
rc="$(run_deploy)"                       # doit échouer (rc 2) mais libérer le verrou
[ "$rc" = 2 ] && pass "échec du playbook propagé (rc=2)" || fail "code d'échec non propagé (rc=$rc)"
export FAKE_AP_RC=0
: > "$FAKE_AP_LOG"
rc="$(run_deploy)"                       # le verrou doit être libre
[ "$rc" = 0 ] && grep -q FAKE "$FAKE_AP_LOG" \
  && pass "verrou libéré après échec (exécution suivante aboutit)" \
  || fail "verrou resté tenu après un échec"

# --- 5. deploy.sh n'accepte que SITE ---
if ( cd "$T" && PATH="$tmp/fakebin:$PATH" bash scripts/deploy.sh grav-alpha -i /tmp/x ) >/dev/null 2>&1; then
  fail "deploy.sh a accepté un argument supplémentaire"
else
  pass "deploy.sh refuse tout argument autre que SITE"
fi

finish
