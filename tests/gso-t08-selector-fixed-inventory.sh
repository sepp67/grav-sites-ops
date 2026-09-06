#!/usr/bin/env bash
# GSO-T08 — Refus sans inventaire explicite / imposé.
#
# L'inventaire opérationnel est FIXÉ par le dépôt à
# `inventories/production/hosts.yml` et ne peut être ni omis ni remplacé par
# une option utilisateur (GSO-REQ-053).

TEST_ID="GSO-T08"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"
S="$REPO_ROOT/scripts/validate-target.sh"
FIX="$DIR/fixtures"

# --- 1. Chemin d'inventaire figé dans le code, une seule fois ---
n="$(grep -c 'inventories.*production.*hosts.yml' "$REPO_ROOT/scripts/lib/gso_validate.py" || true)"
if grep -q 'FIXED_INVENTORY = os.path.join("inventories", "production", "hosts.yml")' "$REPO_ROOT/scripts/lib/gso_validate.py"; then
  pass "inventaire imposé codé en dur : inventories/production/hosts.yml"
else
  fail "chemin d'inventaire imposé introuvable dans gso_validate.py"
fi

# --- 2. Aucune option -i / --inventory / --limit acceptée ---
for opt in "-i" "--inventory" "--limit"; do
  if bash "$S" grav-alpha --root "$FIX/l3-prod-ok" "$opt" /tmp/evil-inventory >/dev/null 2>&1; then
    fail "l'option $opt a été acceptée (substitution d'inventaire possible)"
  else
    pass "option $opt refusée"
  fi
done

# --- 3. Arborescence sans inventaire de production : refus ---
if bash "$S" grav-alpha --root "$FIX/l3-prod-no-inv" >/dev/null 2>&1; then
  fail "sélection acceptée alors que l'inventaire imposé est absent"
else
  pass "refus quand inventories/production/hosts.yml est absent (rc != 0)"
fi

# --- 4. Dans le dépôt réel (pas d'inventaire de production) : refus ---
if bash "$S" grav-alpha >/dev/null 2>&1; then
  fail "sélection acceptée dans le dépôt réel (aucun inventaire de production ne doit exister)"
else
  pass "refus dans le dépôt réel — inventaire de production absent par conception"
fi

# --- 5. La cible Makefile `validate` câble correctement le sélecteur ---
if make -s validate SITE=grav-alpha >/dev/null 2>&1; then
  fail "make validate a réussi dans le dépôt réel (impossible sans inventaire de production)"
else
  pass "make validate relaie le refus du sélecteur (rc != 0)"
fi

finish
