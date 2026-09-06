#!/usr/bin/env bash
# GSO-T08 — Refus sans inventaire explicite / imposé, et impossibilité de
# substituer la racine du dépôt ou l'inventaire fixé (GSO-REQ-053).

TEST_ID="GSO-T08"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"
S="$REPO_ROOT/scripts/validate-target.sh"
P="$REPO_ROOT/scripts/preflight.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- 1. Racine déterminée depuis l'emplacement du fichier, une seule fois ---
if grep -q 'def repo_root() -> str:' "$REPO_ROOT/scripts/lib/gso_validate.py" \
   && grep -q 'os.path.realpath(__file__)' "$REPO_ROOT/scripts/lib/gso_validate.py"; then
  pass "racine du dépôt dérivée de l'emplacement canonique du script (realpath __file__)"
else
  fail "repo_root() ne dérive pas la racine de __file__"
fi
if grep -q 'FIXED_INVENTORY = os.path.join("inventories", "production", "hosts.yml")' "$REPO_ROOT/scripts/lib/gso_validate.py"; then
  pass "inventaire imposé codé en dur : inventories/production/hosts.yml"
else
  fail "chemin d'inventaire imposé introuvable"
fi

# --- 2. Les deux wrappers refusent toute option ---
for w in "$S" "$P"; do
  for opt in "--root" "--inventory" "-i" "--limit"; do
    if bash "$w" grav-alpha "$opt" /tmp/evil >/dev/null 2>&1; then
      fail "$(basename "$w") a accepté l'option $opt"
    else
      pass "$(basename "$w") refuse l'option $opt"
    fi
  done
done

# --- 3. Aucune variable d'environnement ne substitue racine ou inventaire ---
mkdir -p "$tmp/evil/inventories/production/group_vars/all"
cp "$DIR/fixtures/l3-prod-ok/inventories/production/hosts.yml" "$tmp/evil/inventories/production/hosts.yml"
cp "$DIR/fixtures/l3-prod-ok/inventories/production/group_vars/all/grav_sites.yml" \
   "$tmp/evil/inventories/production/group_vars/all/grav_sites.yml"
if env GRAV_SITES_OPS_ROOT="$tmp/evil" GRAV_SITES_OPS_INVENTORY="$tmp/evil/inventories/production/hosts.yml" \
       ANSIBLE_INVENTORY="$tmp/evil/inventories/production/hosts.yml" \
       PWD="$tmp/evil" \
       bash "$S" grav-alpha >/dev/null 2>&1; then
  fail "une variable d'environnement a permis de substituer racine/inventaire"
else
  pass "aucune variable d'environnement ne substitue la racine ou l'inventaire"
fi

# --- 4. Exécution depuis un autre répertoire courant : même racine canonique ---
out="$(cd "$tmp" && bash "$S" grav-alpha 2>&1 || true)"
if printf '%s' "$out" | grep -qF "$REPO_ROOT/inventories/production/hosts.yml"; then
  pass "depuis un autre cwd, la racine reste celle du dépôt ($REPO_ROOT)"
else
  fail "la racine dépend du répertoire courant : $out"
fi

# --- 5. Une arborescence synthétique externe n'est pas sélectionnable par l'opérateur ---
l3_tmptree l3-prod-ok "$tmp/tree"
# a) le wrapper DU DÉPÔT, lancé depuis l'arbre synthétique, résout quand même le dépôt (échec)
if (cd "$tmp/tree" && bash "$S" grav-alpha >/dev/null 2>&1); then
  fail "le wrapper du dépôt a sélectionné une cible dans une arborescence externe"
else
  pass "le wrapper du dépôt ignore l'arborescence externe (résout la racine du dépôt)"
fi
# b) seule une copie complète (scripts inclus) résout sa propre racine — mécanisme de test
if (cd / && bash "$tmp/tree/scripts/validate-target.sh" grav-alpha >/dev/null 2>&1); then
  pass "seule une copie complète du dépôt (scripts inclus) résout sa propre racine — voie de test, pas d'opérateur"
else
  fail "la copie de test ne résout pas sa propre racine"
fi

# --- 6. Dépôt réel : aucun inventaire de production => refus ---
if bash "$S" grav-alpha >/dev/null 2>&1; then
  fail "sélection acceptée dans le dépôt réel (aucun inventaire de production ne doit exister)"
else
  pass "refus dans le dépôt réel — inventaire de production absent par conception"
fi
if make -s validate SITE=grav-alpha >/dev/null 2>&1; then
  fail "make validate a réussi dans le dépôt réel"
else
  pass "make validate relaie le refus du sélecteur (rc != 0)"
fi

finish
