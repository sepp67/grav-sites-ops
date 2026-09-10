#!/usr/bin/env bash
# GSO-T09 — Refus sans SITE (transmis ensuite à --limit).
# GSO-REQ-083, GSO-REQ-016, GSO-REQ-038.

TEST_ID="GSO-T09"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"
S="$REPO_ROOT/scripts/validate-target.sh"

tmp="$(gso_mktemp_dir t09)"
trap 'rm -rf "$tmp"' EXIT
l3_tmptree l3-prod-ok "$tmp/tree"
W="$tmp/tree/scripts/validate-target.sh"   # copie complète : racine = $tmp/tree

# --- SITE absent (wrapper du dépôt ET copie de test) ---
for w in "$S" "$W"; do
  if bash "$w" >/dev/null 2>&1; then
    fail "$(basename "$(dirname "$(dirname "$w")")")/… : sélection acceptée sans SITE"
  else
    pass "refus sans SITE ($w)"
  fi
done

# --- SITE vide / espaces (contre une arborescence par ailleurs valide) ---
if bash "$W" "" >/dev/null 2>&1; then
  fail "sélection acceptée avec SITE vide"
else
  pass "refus quand SITE est vide (rc != 0)"
fi
if bash "$W" "   " >/dev/null 2>&1; then
  fail "sélection acceptée avec SITE = espaces"
else
  pass "refus quand SITE ne contient que des espaces (rc != 0)"
fi

finish
