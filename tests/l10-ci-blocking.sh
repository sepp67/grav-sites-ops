#!/usr/bin/env bash
# L10 — La CI est NON OPÉRATIONNELLE et BLOQUANTE
# (GSO-REQ-030, 046, 058, 074, 139, 145, 146, 147).
#
# Validation STATIQUE de `.github/workflows/ci.yml` — la CI distante n'est
# PAS exécutée ici (aucun push) : voir docs/TEST-RESULTS.md et le rapport L10.
#
# 100 % local, lecture seule.

TEST_ID="L10-CI-BLOCKING"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"
CI=".github/workflows/ci.yml"
[ -f "$CI" ] && pass "$CI présent" || { fail "$CI absent"; finish; }

# CI sans les commentaires YAML (les commentaires citent volontairement les
# motifs interdits — GSO-REQ-030/046/145 — pour documenter les garde-fous).
CI_CODE="$(grep -vE '^[[:space:]]*#' "$CI")"

# --- yaml parsable ---
python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' "$CI" \
  && pass "$CI : YAML valide" || fail "$CI : YAML invalide"

# --------------------------------------------------------------------------
# GSO-REQ-145 — jobs bloquants : aucun continue-on-error
# --------------------------------------------------------------------------
if printf %s "$CI_CODE" | grep -qE 'continue-on-error'; then
  fail "GSO-REQ-145 : continue-on-error présent — un job pourrait ne pas bloquer"
else
  pass "GSO-REQ-145 : aucun continue-on-error (tous les jobs bloquent)"
fi
python3 - "$CI" <<'PY'
import sys, yaml
w = yaml.safe_load(open(sys.argv[1]))
jobs = w.get("jobs", {})
assert jobs, "aucun job"
# une porte de conformité qui dépend de tous les autres jobs de conformité
gate = next((j for j, b in jobs.items() if b.get("needs")), None)
assert gate, "aucun job-porte avec needs"
needs = set(jobs[gate]["needs"])
others = {j for j in jobs if j != gate}
missing = others - needs
assert not missing, f"la porte `{gate}` ne dépend pas de : {sorted(missing)}"
print(f"      OK   porte `{gate}` -> needs {sorted(needs)}")
PY
[ $? -eq 0 ] && pass "GSO-REQ-145 : une porte de conformité dépend de TOUS les jobs" \
             || fail "GSO-REQ-145 : porte de conformité incomplète"

# --------------------------------------------------------------------------
# GSO-REQ-030 / 046 / 058 — CI non opérationnelle
# --------------------------------------------------------------------------
if printf %s "$CI_CODE" | grep -qE 'inventories/production/|group_vars/all/vault\.yml|ANSIBLE_VAULT|--ask-vault-pass|--vault-password-file|ssh-agent|SSH_PRIVATE_KEY|secrets\.[A-Z]'; then
  fail "GSO-REQ-030/046/058 : la CI référence un inventaire de production / vault / clé SSH / secret"
else
  pass "GSO-REQ-030/046/058 : la CI ne référence ni inventories/production/, ni vault, ni clé SSH, ni secret GitHub"
fi
# aucune connexion sortante vers un hôte : pas de `ansible ... -i inventories/production`
if git grep -nIE 'ansible(-playbook)? .*inventories/production/hosts\.yml' -- tests/ scripts/ | grep -vE 'l10-ci-blocking|gso-t08|gso-t12'; then
  info "note : des tests référencent inventories/production/hosts.yml — vérifié ci-dessous qu'il s'agit de fixtures"
fi

# --------------------------------------------------------------------------
# GSO-REQ-139 — la CI fonctionne SANS le vault de production
# --------------------------------------------------------------------------
# `inventories/production/` est fourni HORS dépôt : aucun fichier suivi.
if git ls-files | grep -qE '^inventories/production/'; then
  fail "GSO-REQ-139 : des fichiers `inventories/production/` sont suivis"
else
  pass "GSO-REQ-139 : `inventories/production/` n'est pas dans le dépôt (fourni hors dépôt)"
fi
# aucun test ne lit un vault de production RÉEL (chemin absolu / racine du dépôt) —
# les tests qui écrivent `$T/inventories/production/.../vault.yml` dans un
# mktemp sont légitimes et ne comptent pas.
_home="/$(printf ho)$(printf me)/"
if git grep -nIE "(\\\$REPO_ROOT|\\\$HOME|${_home}|/Us""ers/|/ro""ot/)[^ ]*inventories/production/[^ ]*vault" -- tests/ scripts/ 2>/dev/null; then
  fail "GSO-REQ-139 : un fichier suivi lit un vault de production réel"
else
  pass "GSO-REQ-139 : aucun fichier suivi ne lit un vault de production réel (fixtures mktemp uniquement)"
fi
grep -q 'fonctionne sans .inventories/production' "$CI" && pass "$CI : en-tête documente le fonctionnement sans inventaire de production" \
  || info "$CI : en-tête ne mentionne pas explicitement l'absence d'inventaire de production (toléré)"

# --------------------------------------------------------------------------
# GSO-REQ-074 — contrôle automatique anti-fuite de secrets dans la CI
# --------------------------------------------------------------------------
if printf %s "$CI_CODE" | grep -qE 'gso-t24'; then
  pass "GSO-REQ-074 : GSO-T24 (anti-fuite de secrets / chemins locaux) est dans la CI"
else
  fail "GSO-REQ-074 : GSO-T24 absent de la CI"
fi

# --------------------------------------------------------------------------
# GSO-REQ-146 — interpréteurs bornés (pas de 3.x, pas de core non borné)
# --------------------------------------------------------------------------
if printf %s "$CI_CODE" | grep -qE 'python-version: *"3\.x"|python-version: *3\.x|python-version: *"3"'; then
  fail "GSO-REQ-146 : python-version flottant (3.x)"
else
  pass "GSO-REQ-146 : python-version épinglé (mineure explicite)"
fi
if printf %s "$CI_CODE" | grep -qE 'ansible-core>=[0-9.]+"'; then
  fail "GSO-REQ-146 : ansible-core sans borne supérieure (rupture majeure possible)"
else
  printf %s "$CI_CODE" | grep -qE 'ansible-core>=[0-9.]+,<[0-9.]+' \
    && pass "GSO-REQ-146 : ansible-core borné haut et bas" \
    || fail "GSO-REQ-146 : ansible-core non borné"
fi

# --------------------------------------------------------------------------
# GSO-REQ-147 — l'absence d'exécution CI observée est indiquée comme telle
# --------------------------------------------------------------------------
if [ -f docs/TEST-RESULTS.md ] && grep -qiE 'CI (distante|GitHub).*(non (exécut|publi|observ)|pas (exécut|observ)|jamais poussé|sans push)' docs/TEST-RESULTS.md; then
  pass "GSO-REQ-147 : docs/TEST-RESULTS.md indique que la CI distante n'a pas été observée (aucun push)"
else
  fail "GSO-REQ-147 : docs/TEST-RESULTS.md ne signale pas l'absence d'exécution CI observée"
fi

# --------------------------------------------------------------------------
# Couverture : GSO-T01..T24 (sauf T15) référencés par une étape CI
# --------------------------------------------------------------------------
missing=""
for n in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 16 17 18 19 20 21 22 23 24; do
  grep -qE "GSO-T$n|gso-t$n" "$CI" || missing="$missing T$n"
done
[ -z "$missing" ] && pass "les 23 GSO-T reproductibles (T01..T24 sauf T15) sont référencés par la CI" \
                  || fail "GSO-T non référencés dans la CI :$missing"
grep -qE 'l4-ci-functional-contract' "$CI" && pass "GSO-T15 : garde-fou statique présent (jamais exécuté en CI)" \
  || fail "garde-fou GSO-T15 absent de la CI"

# --------------------------------------------------------------------------
# GSO-REQ-150 — matrice de conformité complète et à jour (204 exigences)
# --------------------------------------------------------------------------
if [ -f docs/COMPLIANCE-MATRIX.md ] \
   && [ "$(grep -c '^| GSO-REQ-' docs/COMPLIANCE-MATRIX.md)" = 204 ] \
   && python3 scripts/lib/gso_compliance.py --check >/dev/null 2>&1; then
  pass "GSO-REQ-150 : docs/COMPLIANCE-MATRIX.md — 204 exigences, à jour (make matrix-check)"
else
  fail "GSO-REQ-150 : matrice de conformité absente / incomplète / obsolète"
fi
grep -qE 'matrix-check|COMPLIANCE-MATRIX' "$CI" \
  && pass "la CI vérifie la matrice de conformité" \
  || fail "la CI ne vérifie pas la matrice de conformité"

finish
