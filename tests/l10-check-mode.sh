#!/usr/bin/env bash
# L10 — GSO-REQ-091 : le mode `--check` n'est PAS un déploiement fonctionnel.
#
# Preuve dédiée différée de L4 à L10 (rapport L4 §Verdict). NON numérotée : le
# préflight n'attribue aucun GSO-T à cette exigence. 100 % local, doublure de
# rôle, sans Docker / réseau / connexion.
#
# Prouve :
#   - comportement : `ansible-playbook deploy-site.yml --check` s'exécute
#     (assertions + préflight structurel), mais N'APPLIQUE RIEN — la doublure
#     du rôle ne produit aucun fichier de sortie, aucune ligne de _calls.log ;
#   - documentation : aucun document opérateur ne présente `--check` comme
#     équivalent à un déploiement ou à une preuve de santé ; `docs/OPERATIONS.md`
#     porte explicitement l'avertissement.

TEST_ID="L10-CHECK-MODE"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

tmp="$(gso_mktemp_dir l10-check)"
trap 'rm -rf "$tmp"' EXIT
gso_isolate_runtime "$tmp"

T="$tmp/tree"
l4_tmptree l3-prod-ok "$T"
gso_spy_role_into "$T"
cat > "$T/inventories/production/group_vars/all/vault.yml" <<'YML'
vault_grav_sites:
  grav-alpha: {admin_user: a, admin_password: SYNTH-L10-CHECK-PW, admin_email: a@example.invalid}
  grav-beta:  {admin_user: b, admin_password: SYNTH-L10-CHECK-PW2, admin_email: b@example.invalid}
vault_retired_grav_sites: {}
YML

# --------------------------------------------------------------------------
# 1. Comportement : --check s'exécute mais n'applique rien
# --------------------------------------------------------------------------
spy="$tmp/spy"; mkdir -p "$spy"
rc=0
( cd "$T" && GSO_SPY_OUTPUT="$spy" ansible-playbook \
    -i inventories/production/hosts.yml playbooks/deploy-site.yml \
    --limit grav-alpha --check ) > "$tmp/check.log" 2>&1 || rc=$?

if [ "$rc" = 0 ]; then
  pass "deploy-site.yml --check : s'exécute sans erreur (rc=0)"
else
  sed 's/^/   | /' "$tmp/check.log" | tail -20
  fail "deploy-site.yml --check a échoué (rc=$rc)"
  finish
fi

# les assertions du play ET le préflight structurel ont bien tourné
grep -q 'TASK \[Assertion : --limit' "$tmp/check.log" && grep -q 'TASK \[Préflight structurel local' "$tmp/check.log" \
  && pass "--check : les assertions et le préflight structurel s'exécutent" \
  || fail "--check : les contrôles amont n'ont pas tourné"

# RIEN n'a été appliqué : la doublure n'a produit aucun artefact
if [ ! -e "$spy/grav-alpha.json" ] && [ ! -e "$spy/_calls.log" ]; then
  pass "--check : la doublure du rôle n'a produit AUCUN fichier (rien appliqué)"
else
  fail "--check : un artefact a été écrit ($(ls "$spy"))"
fi

# le journal signale explicitement le mode check (aucun 'changed' réel)
grep -qiE 'check mode|DRY RUN|--check' "$tmp/check.log" \
  && pass "--check : le journal indique le mode simulation" \
  || info "--check : le journal ne marque pas explicitement le mode (toléré)"

# --------------------------------------------------------------------------
# 2. Comparaison : le MÊME chemin en mode réel APPLIQUE (via la doublure)
# --------------------------------------------------------------------------
spy2="$tmp/spy2"; mkdir -p "$spy2"
( cd "$T" && GSO_SPY_OUTPUT="$spy2" bash scripts/deploy.sh grav-alpha ) > "$tmp/real.log" 2>&1
if [ -e "$spy2/grav-alpha.json" ] && [ -e "$spy2/_calls.log" ]; then
  pass "mode réel : la doublure produit ses artefacts (le contraste avec --check est démontré)"
else
  fail "mode réel : la doublure n'a rien produit"
fi

# --------------------------------------------------------------------------
# 3. Documentation : --check jamais présenté comme un déploiement / une santé
# --------------------------------------------------------------------------
docs="$(git ls-files 'docs/*.md' | grep -v 'CONTRAT-ARCHITECTURAL.md')"
bad=0
while IFS= read -r d; do
  [ -z "$d" ] && continue
  # une phrase qui associe --check à « déploiement » / « prouve » / « santé » /
  # « équivalent » / « suffit » dans la même ligne.
  if grep -nEi -- '--check' "$d" | grep -Ei 'déploiement (fonctionnel|réussi)|équivaut|équivalent (à|d.un)|prouve (le|la|un)|preuve de (déploiement|santé)|suffit (à|pour)|remplace un déploiement' ; then
    fail "$d : présente --check comme un déploiement / une preuve (GSO-REQ-091)"
    bad=1
  fi
done <<< "$docs"
[ "$bad" -eq 0 ] && pass "aucun document opérateur ne présente --check comme un déploiement fonctionnel (GSO-REQ-091)"

if grep -qEi -e '--check' docs/OPERATIONS.md && grep -qiE 'ne (constitue|prouve) pas|pas (un déploiement|une preuve|équivalent)|complémentaire' docs/OPERATIONS.md; then
  pass "docs/OPERATIONS.md porte l'avertissement explicite sur --check (contrat §13.8)"
else
  fail "docs/OPERATIONS.md ne documente pas la limite de --check"
fi

# --------------------------------------------------------------------------
# 4. Aucun résidu, aucune fuite
# --------------------------------------------------------------------------
grep -qE 'SYNTH-L10-CHECK' "$tmp/check.log" "$tmp/real.log" && fail "fuite d'une valeur secrète" \
  || pass "aucune valeur secrète dans les sorties"
gso_assert_runtime_clean
finish
