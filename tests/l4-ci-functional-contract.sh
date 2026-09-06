#!/usr/bin/env bash
# L4 — Garde-fou statique du contrat d'exécution de GSO-T15.
#
# La CI standard ne doit ni exécuter GSO-T15, ni tirer une image, ni
# dépendre d'une référence flottante ou d'un secret d'accès à un registre
# (GSO-REQ-030, GSO-REQ-108). GSO-T15 est un test d'acceptation LOCAL qui
# ÉCHOUE — jamais un SKIP ni un succès — si ses préconditions manquent.

TEST_ID="L4-CI-CONTRACT"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"
CI=".github/workflows/ci.yml"
[ -f "$CI" ] || { fail "workflow CI absent : $CI"; finish; }

# Lignes exécutables (hors commentaires YAML).
ci_code() { grep -vE '^[[:space:]]*#' "$CI"; }

# --- 1. Aucune étape de la CI n'exécute GSO-T15 ni la gate fonctionnelle ---
hits="$(ci_code | grep -nE '(run:|bash|make).*(gso-t15|test-functional|--functional|GSO_RUN_FUNCTIONAL=1)' || true)"
if [ -n "$hits" ]; then
  fail "la CI exécute GSO-T15 / la gate fonctionnelle :"
  printf '%s\n' "$hits" | sed 's/^/      | /'
else
  pass "la CI n'exécute pas GSO-T15 ni la gate fonctionnelle"
fi

# --- 2. Aucun pull d'image dans la CI ---
hits="$(ci_code | grep -nE 'docker[[:space:]]+pull|docker[[:space:]]+compose[[:space:]]+pull|pull_policy|^[[:space:]]*pull:[[:space:]]*(always|missing)' || true)"
if [ -n "$hits" ]; then
  fail "la CI tire une image :"
  printf '%s\n' "$hits" | sed 's/^/      | /'
else
  pass "la CI ne tire aucune image"
fi

# --- 3. Aucune référence d'image flottante dans la CI ---
if ci_code | grep -qE ':latest|@latest|image:[[:space:]]*[^@]*$'; then
  fail "référence d'image flottante (latest / sans digest) dans la CI"
else
  pass "aucune référence d'image flottante dans la CI"
fi

# --- 4. Aucun secret / identifiant de registre requis par la CI ---
hits="$(ci_code | grep -nE '\$\{\{[[:space:]]*secrets\.|docker[[:space:]]+login|GHCR_(TOKEN|PAT)|REGISTRY_(USER|USERNAME|PASSWORD|TOKEN)|registry-(url|username|password)|username:.*ghcr' || true)"
if [ -n "$hits" ]; then
  fail "la CI requiert un secret / identifiant de registre :"
  printf '%s\n' "$hits" | sed 's/^/      | /'
else
  pass "la CI ne requiert aucun secret ni identifiant de registre"
fi

# --- 5. run-all.sh classe GSO-T15 comme fonctionnel (hors batterie par défaut) ---
if grep -qE 'gso-t15-\*\)' "$DIR/run-all.sh" && grep -qE 'FUNCTIONAL' "$DIR/run-all.sh"; then
  pass "run-all.sh n'exécute GSO-T15 que sur --functional"
else
  fail "run-all.sh n'isole pas GSO-T15 du sous-ensemble reproductible"
fi

# --- 6. GSO-T15 échoue (jamais SKIP/succès) si une précondition manque ---
t15="$DIR/gso-t15-real-deploy.sh"
if grep -qE 'GSO_SKIP_DOCKER|skip .*conteneur|^\s*skip\b.*docker' "$t15"; then
  fail "GSO-T15 contient un chemin de SKIP silencieux"
elif grep -qE 'BLOCAGE.*Docker' "$t15" && grep -qE 'fail "BLOCAGE' "$t15"; then
  pass "GSO-T15 bloque explicitement (fail) sur précondition manquante"
else
  fail "GSO-T15 ne garantit pas un échec sur précondition manquante"
fi

# --- 7. Le digest épinglé est documenté (docs/TESTING.md) et unique ---
if [ -f docs/TESTING.md ] && grep -qF 'sha256:d130f333c6566a26856c271656b21ce2d06793f9c4af24e620b53da14e4d640f' docs/TESTING.md; then
  pass "digest exact de l'image de GSO-T15 documenté dans docs/TESTING.md"
else
  fail "digest de l'image de GSO-T15 absent de docs/TESTING.md"
fi

finish
