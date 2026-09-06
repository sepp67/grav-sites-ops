#!/usr/bin/env bash
# GSO-T09 — Refus sans SITE (transmis ensuite à --limit).
#
# `SITE` absent ou vide DOIT provoquer un échec sûr, avant toute mutation
# (GSO-REQ-083, GSO-REQ-016, GSO-REQ-038).

TEST_ID="GSO-T09"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"
S="$REPO_ROOT/scripts/validate-target.sh"
ROOT="$DIR/fixtures/l3-prod-ok"

# --- SITE totalement absent ---
if bash "$S" --root "$ROOT" >/dev/null 2>&1; then
  fail "sélection acceptée sans SITE"
else
  pass "refus quand SITE est absent (rc != 0)"
fi

# --- SITE chaîne vide ---
if bash "$S" "" --root "$ROOT" >/dev/null 2>&1; then
  fail "sélection acceptée avec SITE vide"
else
  pass "refus quand SITE est vide (rc != 0)"
fi

# --- SITE = espaces uniquement ---
if bash "$S" "   " --root "$ROOT" >/dev/null 2>&1; then
  fail "sélection acceptée avec SITE = espaces"
else
  pass "refus quand SITE ne contient que des espaces (rc != 0)"
fi

finish
