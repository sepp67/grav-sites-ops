#!/usr/bin/env bash
# L11 — Gardes d'acceptation (GSO-REQ-158, 159, 183, 184, 185, 186, 187,
# 188, 189, 190, 191, 192, 202).
#
# Rend RE-VÉRIFIABLES les constats de la revue d'acceptation (docs/ACCEPTANCE.md)
# et garantit qu'aucune automatisation de publication / tag / release / migration
# n'apparaît. 100 % local, lecture seule — ne franchit rien.
#
# La CI distante n'est PAS exécutée ici (aucun push) : voir docs/TEST-RESULTS.md.

TEST_ID="L11-ACCEPTANCE-GUARDS"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

ACC="docs/ACCEPTANCE.md"

# --------------------------------------------------------------------------
# 0. docs/ACCEPTANCE.md présent et structuré (les 4 verdicts séparés)
# --------------------------------------------------------------------------
if [ -f "$ACC" ]; then
  pass "$ACC présent"
else
  fail "$ACC absent"; finish
fi

for dom in "Construction locale" "Publication" "Release" "Migration réelle"; do
  grep -qF "$dom" "$ACC" && pass "$ACC : verdict « $dom » présent" \
    || fail "$ACC : verdict « $dom » absent"
done
grep -qE '`ACCEPTED`' "$ACC" && grep -qE '`BLOCKED`' "$ACC" \
  && pass "$ACC : la construction locale est ACCEPTED, d'autres domaines BLOCKED" \
  || fail "$ACC : verdicts ACCEPTED / BLOCKED attendus"

# --------------------------------------------------------------------------
# 1. GSO-REQ-185 — le premier commit du dépôt n'a aucune capacité de déploiement
# --------------------------------------------------------------------------
root="$(git rev-list --max-parents=0 HEAD | tail -1)"
root_files="$(git show --name-only --format= "$root" | grep -v '^$' || true)"
if [ "$(printf '%s\n' "$root_files" | grep -c .)" -eq 1 ] \
   && printf '%s\n' "$root_files" | grep -qx 'README.md'; then
  pass "GSO-REQ-185 : premier commit ($(git rev-parse --short "$root")) = README.md seul, aucune capacité de déploiement"
else
  fail "GSO-REQ-185 : le premier commit contient autre chose que README.md : $(printf '%s ' $root_files)"
fi
if printf '%s\n' "$root_files" | grep -qE '^(playbooks/|scripts/|inventories/|Makefile|ansible\.cfg|requirements\.yml)'; then
  fail "GSO-REQ-185 : capacité opérationnelle dans le premier commit"
else
  pass "GSO-REQ-185 : ni playbook, ni script, ni inventaire, ni Makefile dans le premier commit"
fi

# --------------------------------------------------------------------------
# 2. GSO-REQ-159 / 192 — aucune automatisation de push / tag / release
# --------------------------------------------------------------------------
autom="$(git grep -nIE '(git[[:space:]]+push|git[[:space:]]+tag[[:space:]]+-|gh[[:space:]]+release|gh[[:space:]]+pr[[:space:]]+create|git[[:space:]]+remote[[:space:]]+add)' -- \
  'playbooks/' 'scripts/' 'Makefile' '.github/' \
  ':!tests/**' 2>/dev/null || true)"
if [ -n "$autom" ]; then
  fail "GSO-REQ-192 : automatisation de publication détectée :"
  printf '%s\n' "$autom" | sed 's/^/      | /'
else
  pass "GSO-REQ-192 : aucun git push / git tag / gh release / git remote add dans playbooks, scripts, Makefile, CI"
fi

# ci.yml ne réagit ni à un tag ni à une release (GSO-REQ-159)
python3 - <<'PY'
import sys, yaml
w = yaml.safe_load(open(".github/workflows/ci.yml"))
on = w.get("on") or w.get(True) or {}
if isinstance(on, str):
    on = {on: None}
bad = [k for k in on if k in ("release", "create", "push_tag")]
# un push de tag passerait par push.tags — vérifier qu'aucun filtre tags n'est là
push = on.get("push") if isinstance(on.get("push"), dict) else {}
if push and "tags" in push:
    bad.append("push.tags")
if bad:
    print("DECLENCHEURS INTERDITS:", bad); sys.exit(1)
print("OK  on:", sorted(on))
sys.exit(0)
PY
[ $? -eq 0 ] && pass "GSO-REQ-159 : ci.yml ne se déclenche ni sur release ni sur tag (aucune mutation de VM sur événement de release)" \
             || fail "GSO-REQ-159 : ci.yml réagit à un événement de release / tag"

# aucune étape de déploiement réel dans la CI (déjà couvert par l10-ci-blocking ;
# re-assertion ciblée acceptation)
if git grep -qnIE '(ansible-playbook.+deploy-site\.yml|make deploy|scripts/deploy\.sh)' -- '.github/'; then
  fail "GSO-REQ-159 : la CI invoque un déploiement"
else
  pass "GSO-REQ-159 : la CI n'invoque aucun déploiement (exploitation ≠ publication)"
fi

# --------------------------------------------------------------------------
# 3. GSO-REQ-192 / 158 / 191 — publication en avance rapide, sans réécriture
# --------------------------------------------------------------------------
# GSO-REQ-192 n'interdit PAS de publier `main` : il exige que le `push`, le tag
# et la release soient des étapes explicitement autorisées ET vérifiées.
# Ce garde-fou (un test) vérifie la partie mécanique — relation fast-forward,
# aucune réécriture, aucune automatisation. La vérification de l'AUTORISATION
# HUMAINE du push relève du rapport d'exécution, pas de ce test.
#
# On raisonne sur HEAD (pas `main`) pour fonctionner aussi dans le checkout
# détaché de GitHub Actions.
if git rev-parse --verify -q origin/main >/dev/null 2>&1; then
  # left  = commits sur origin/main absents du checkout testé  -> DOIT être 0
  # right = commits du checkout testé absents d'origin/main     -> >= 0
  _lr="$(git rev-list --left-right --count "origin/main...HEAD" 2>/dev/null || echo 'x x')"
  _left="${_lr%%[[:space:]]*}"; _right="${_lr##*[[:space:]]}"
  if [ "$_left" = "0" ] && git merge-base --is-ancestor origin/main HEAD; then
    if [ "$_right" = "0" ]; then
      pass "GSO-REQ-192 : HEAD == origin/main (publication en avance rapide, aucune réécriture ; left/right = $_left/$_right)"
    else
      pass "GSO-REQ-192 : HEAD descend directement d'origin/main sans divergence ($_right commit(s) non publié(s) ; left/right = $_left/$_right)"
    fi
  else
    # left > 0 : origin/main contient au moins un commit absent du HEAD testé
    # (état distant plus récent, ou divergence). Publication NON vérifiable en
    # avance rapide — sans préjuger de la cause (rebase local en retard,
    # push concurrent, réécriture...).
    fail "GSO-REQ-192 : origin/main n'est pas contenu dans HEAD (left/right = $_left/$_right) — publication non vérifiable en avance rapide"
  fi
  # aucune branche distante autre que main (les branches de travail restent locales)
  remote_branches="$(git branch -r 2>/dev/null | grep -vE 'origin/(HEAD|main)( |$)' || true)"
  if [ -n "$remote_branches" ]; then
    info "note : branche(s) distante(s) autre(s) que main :$(printf ' %s' $remote_branches) - verifier qu'aucune ne contourne le gate de release"
  else
    pass "GSO-REQ-192 : aucune branche distante hors main"
  fi
else
  pass "GSO-REQ-192 : aucun suivi distant de main dans ce checkout"
fi
# GSO-REQ-158 : un tag de release doit pointer sur un SHA à CI verte. Tant
# qu'aucune release n'est préparée, aucun tag ne doit exister ; un tag présent
# devra être annoté et joignable depuis HEAD (contrôlé au lot de release).
if [ -z "$(git tag)" ]; then
  pass "GSO-REQ-158 : aucun tag Git (release non préparée)"
else
  bad_tags=""
  for t in $(git tag); do
    git merge-base --is-ancestor "$t" HEAD 2>/dev/null || bad_tags="$bad_tags $t"
  done
  [ -z "$bad_tags" ] && pass "GSO-REQ-158 : tag(s) présent(s), tous joignables depuis HEAD :$(printf ' %s' $(git tag))" \
                     || fail "GSO-REQ-158 : tag(s) non joignable(s) depuis HEAD :$bad_tags"
fi

# --------------------------------------------------------------------------
# 4. GSO-REQ-189 — commandes documentées testées ou signalées non exécutées
# --------------------------------------------------------------------------
# toute cible `make X` citée dans README.md correspond à une cible réelle du Makefile
doc_targets="$(grep -oE 'make [a-z][a-z0-9-]*' README.md | awk '{print $2}' | sort -u)"
real_targets="$(grep -oE '^[a-z][a-z0-9-]*:' Makefile | sed 's/:$//' | sort -u)"
missing=""
for t in $doc_targets; do
  printf '%s\n' "$real_targets" | grep -qx "$t" || missing="$missing $t"
done
[ -z "$missing" ] && pass "GSO-REQ-189 : les $(printf '%s\n' $doc_targets | grep -c .) cibles \`make\` documentées existent toutes dans le Makefile" \
                  || fail "GSO-REQ-189 : cibles documentées absentes du Makefile :$missing"

# README signale explicitement les éléments non exécutables (inventaire de prod)
grep -qE 'hors dépôt|fourni plus tard|jamais suivi|non opérationnel' README.md \
  && pass "GSO-REQ-189 : README signale les éléments non exécutables (inventaire de production hors dépôt)" \
  || fail "GSO-REQ-189 : README ne signale pas les exemples non exécutés"

# --------------------------------------------------------------------------
# 5. GSO-REQ-190 — cartographie exhaustive des 204 exigences
# --------------------------------------------------------------------------
n_matrix="$(grep -c '^| GSO-REQ-' docs/COMPLIANCE-MATRIX.md 2>/dev/null || echo 0)"
if [ "$n_matrix" = 204 ] && python3 scripts/lib/gso_compliance.py --check >/dev/null 2>&1; then
  pass "GSO-REQ-190 : docs/COMPLIANCE-MATRIX.md cartographie 204/204 exigences (make matrix-check vert)"
else
  fail "GSO-REQ-190 : matrice incomplète ($n_matrix lignes) ou obsolète"
fi

# --------------------------------------------------------------------------
# 6. GSO-REQ-188 — migration réelle NON exécutée
# --------------------------------------------------------------------------
# Capture d'abord (le `$( )` attend la fin normale de `git ls-files`), grep
# ensuite sur la valeur déjà capturée (here-string) — jamais
# `git ls-files | grep -q` (SIGPIPE 141 possible sous `set -o pipefail`,
# faux négatif si le grep aval sort tôt alors qu'il a trouvé la ligne).
_tracked="$(git ls-files)"; _grc=$?
if [ "$_grc" -ne 0 ]; then
  fail "GSO-REQ-188 : git ls-files a échoué (rc=$_grc)"
elif grep -qE '^inventories/production/' <<<"$_tracked"; then
  fail "GSO-REQ-188 : des fichiers inventories/production/ sont suivis (migration/opération réelle)"
else
  pass "GSO-REQ-188 : aucun inventaire de production suivi — conformité établie sur données fictives"
fi
# cas négatif synthétique (copie temporaire, dépôt courant jamais touché) :
# un inventaire de production suivi DOIT être détecté par cette même logique.
_neg="$(gso_mktemp_dir l11-acceptance-neg)"
trap 'rm -rf "$_neg"' EXIT
mkdir -p "$_neg/inventories/production"
git -C "$_neg" init -q
: > "$_neg/inventories/production/hosts.yml"
git -C "$_neg" -c user.email=t@t -c user.name=t add -A >/dev/null
git -C "$_neg" -c user.email=t@t -c user.name=t commit -qm "cas négatif"
_neg_tracked="$(git -C "$_neg" ls-files)"
grep -qE '^inventories/production/' <<<"$_neg_tracked" \
  && pass "cas négatif : inventories/production/hosts.yml suivi est bien détecté par cette logique" \
  || fail "cas négatif : un inventaire de production suivi n'est PAS détecté (faux négatif)"
grep -qiE 'Migration réelle.*`BLOCKED`|`BLOCKED`.*[Mm]igration' "$ACC" \
  && pass "GSO-REQ-188 : docs/ACCEPTANCE.md maintient la migration réelle à l'état BLOCKED" \
  || fail "GSO-REQ-188 : docs/ACCEPTANCE.md ne bloque pas explicitement la migration réelle"

# --------------------------------------------------------------------------
# 7. Décision de licence — signalée comme bloquante, aucune licence implicite
# --------------------------------------------------------------------------
if [ -f LICENSE ] || [ -f LICENSE.md ] || [ -f LICENSE.txt ]; then
  # une licence a été ajoutée par décision humaine : cohérence à vérifier
  grep -qiE 'licen(c|s)e' README.md \
    && pass "licence : fichier LICENSE présent et README à jour" \
    || fail "licence : LICENSE présent mais README ne le mentionne pas"
else
  if grep -qiE 'licen(c|s)e' README.md \
     && grep -qiE 'non encore fixée|non fixée|pas encore fixée|à fixer' README.md; then
    pass "licence : aucune licence choisie ; README la signale comme non fixée (décision humaine)"
  else
    fail "licence : aucune LICENSE et README ne signale pas la décision en attente"
  fi
  grep -qiE 'LICENSE|licen(c|s)e' "$ACC" \
    && pass "licence : docs/ACCEPTANCE.md signale la décision de licence comme condition de release" \
    || fail "licence : docs/ACCEPTANCE.md ne mentionne pas la décision de licence"
fi

# --------------------------------------------------------------------------
# 8. GSO-REQ-184 / 202 — audit et approbation antérieurs, référencés
# --------------------------------------------------------------------------
grep -qE '2026-09-05' docs/CONTRAT-ARCHITECTURAL.md \
  && pass "GSO-REQ-202 : le contrat porte une date d'approbation humaine explicite (2026-09-05)" \
  || fail "GSO-REQ-202 : date d'approbation du contrat introuvable"
grep -qiE 'préflight|preflight|audit' docs/GOVERNANCE.md 2>/dev/null \
  && pass "GSO-REQ-184 : docs/GOVERNANCE.md référence l'audit / le préflight préalables" \
  || info "GSO-REQ-184 : docs/GOVERNANCE.md ne mentionne pas explicitement l'audit (toléré — traçabilité dans audit-grav-sites-ops/)"

# --------------------------------------------------------------------------
# 9. GSO-REQ-187 — le mécanisme de blocage d'une release existe
# --------------------------------------------------------------------------
if grep -qE 'CI complète verte|SHA.*CI|jobs bloquants|conformance' "$ACC" \
   && grep -qE 'needs: \[' .github/workflows/ci.yml; then
  pass "GSO-REQ-187 : le gate de release est conditionné à une CI bloquante (job conformance) — mécanisme en place"
else
  fail "GSO-REQ-187 : mécanisme de blocage d'une release non démontré"
fi

finish
