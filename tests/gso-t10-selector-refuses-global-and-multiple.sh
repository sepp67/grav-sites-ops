#!/usr/bin/env bash
# GSO-T10 — Refus de `all`, d'un groupe, d'un motif, d'une sélection
# multiple et de tout caractère de shell (GSO-REQ-057, 084, 138 ; §14.1).

TEST_ID="GSO-T10"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"
S="$REPO_ROOT/scripts/validate-target.sh"
ROOT="$DIR/fixtures/l3-prod-ok"

refused=0
try_refuse() {
  local label="$1" site="$2"
  if bash "$S" "$site" --root "$ROOT" >/dev/null 2>&1; then
    fail "ACCEPTÉ à tort : $label"
    refused=1
  else
    pass "refusé : $label"
  fi
}

try_refuse "all"                     "all"
try_refuse "étoile"                  "*"
try_refuse "groupe grav_servers"     "grav_servers"
try_refuse "groupe ungrouped"        "ungrouped"
try_refuse "localhost"               "localhost"
try_refuse "liste (virgule)"         "grav-alpha,grav-beta"
try_refuse "liste (espace)"          "grav-alpha grav-beta"
try_refuse "motif glob"              "grav-*"
try_refuse "motif crochets"          "grav-[ab]"
try_refuse "deux-points"             "grav-alpha:8080"
try_refuse "slash"                   "grav-alpha/x"
try_refuse "traversée .."            "../grav-alpha"
try_refuse "substitution shell"      'grav-$(id)'
try_refuse "backtick"                'grav-`id`'
try_refuse "point-virgule"           "grav-alpha;true"
try_refuse "pipe"                    "grav-alpha|true"
try_refuse "majuscule"               "Grav-Alpha"
try_refuse "underscore"              "grav_alpha"

# --- Contrôle positif : un littéral valide passe ---
if bash "$S" grav-alpha --root "$ROOT" >/dev/null 2>&1; then
  pass "contrôle positif : littéral valide 'grav-alpha' accepté"
else
  fail "contrôle positif en échec : 'grav-alpha' aurait dû être accepté"
fi

finish
