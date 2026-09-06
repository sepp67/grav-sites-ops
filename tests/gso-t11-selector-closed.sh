#!/usr/bin/env bash
# GSO-T11 — Refus d'une cible inconnue ou vide avec code non nul, exercé
# sur le validateur lui-même ; consolide GSO-REQ-138 (sélecteur fermé).
# Voir GSO-REQ-056, GSO-REQ-086, GSO-REQ-093.

TEST_ID="GSO-T11"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"
H="python3 $GSO_SELECT_HARNESS"
F="$DIR/fixtures"

expect_fail() {
  local label="$1" site="$2" root="$3"
  if $H selector "$site" "$root" >/dev/null 2>&1; then
    fail "ACCEPTÉ à tort : $label"
  else
    pass "refusé (rc != 0) : $label"
  fi
}
expect_ok() {
  local label="$1" site="$2" root="$3"
  out="$($H selector "$site" "$root" 2>/dev/null)" && rc=0 || rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "^TARGET "; then
    pass "accepté (rc 0, TARGET émis) : $label"
  else
    fail "REFUSÉ à tort : $label (rc=$rc)"
  fi
}

expect_fail "hôte inconnu"               "grav-zeta"  "$F/l3-prod-ok"
expect_fail "chaîne vide"                ""           "$F/l3-prod-ok"
expect_fail "projet retiré (hors actif)" "grav-gamma" "$F/l3-prod-ok"
expect_fail "actif ET retiré (conflit)"  "grav-beta"  "$F/l3-prod-retired-conflict"
expect_fail "registre incohérent (L1)"   "grav-alpha" "$F/l3-prod-broken-registry"

expect_ok   "hôte actif started"         "grav-alpha" "$F/l3-prod-ok"
expect_ok   "hôte actif stopped"         "grav-beta"  "$F/l3-prod-ok"

t="$($H selector grav-alpha "$F/l3-prod-ok" 2>/dev/null | sed -n 's/^TARGET //p')"
if [ "$t" = "grav-alpha" ]; then
  pass "la cible résolue est le littéral exact demandé (grav-alpha)"
else
  fail "cible résolue inattendue : '$t'"
fi

# --- GSO-REQ-018 : aucune variable de sélection parallèle ---
pat="grav_site""_target"
hits="$(git grep -nI -e "$pat" -- ':!docs/' ':!tests/gso-t11-selector-closed.sh' || true)"
if [ -n "$hits" ]; then
  fail "variable de sélection parallèle présente :"
  printf '%s\n' "$hits" | sed 's/^/      | /'
else
  pass "aucune variable de sélection parallèle (GSO-REQ-018)"
fi

finish
