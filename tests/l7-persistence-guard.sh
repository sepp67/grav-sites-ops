#!/usr/bin/env bash
# L7 — Garde de persistance (statique).
#
# Preuve d'un ensemble d'invariants L7, sans numéro GSO-T (traçabilité
# explicite, convention du préflight). Analyse UNIQUEMENT les fichiers
# d'EXÉCUTION (playbooks/, scripts/, Makefile, workflow CI), commentaires
# retirés — jamais la documentation ni les fixtures de test.
#
# Vérifie que grav-sites-ops :
#   - ne contient aucune opération destructive de volume / répertoire
#     persistant (GSO-REQ-040, 075, 079, 102) ;
#   - ne synchronise ni ne restaure automatiquement de contenu
#     (GSO-REQ-033, 077, 078, 113) ;
#   - n'enchaîne pas un rollback automatique après un échec (GSO-REQ-114) ;
#   - ne réécrit ni ne tronque le journal de versions du rôle
#     (GSO-REQ-117) ;
#   - n'expose aucune voie de surcharge CLI de l'image / version / digest
#     (GSO-REQ-109) ;
#   - ne crée AUCUN nouveau playbook, wrapper, cible Makefile ou intention
#     `_gso_intent` de mise à jour ou de rollback : ce sont des usages
#     déclaratifs de `deploy-site.yml` (contrat §13.1, §15).

TEST_ID="L7-PERSISTENCE-GUARD"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

# Fichiers d'exécution suivis par Git (jamais tests/ ni docs/).
mapfile -t EXEC_FILES < <(git ls-files 'playbooks/*.yml' 'playbooks/**/*.yml' 'scripts/*.sh' 'scripts/**/*.sh' 'scripts/**/*.py' Makefile)

code_only() {  # retire les lignes de commentaire (# … et YAML `#`)
  grep -vE '^[[:space:]]*#' "$1" 2>/dev/null || true
}
all_code() { for f in "${EXEC_FILES[@]}"; do code_only "$f"; done; }

check_absent() {  # <label> <regex étendue>
  local label="$1" re="$2" hit
  hit="$(all_code | grep -nE "$re" || true)"
  if [ -z "$hit" ]; then
    pass "$label"
  else
    fail "$label — trouvé : $(printf '%s' "$hit" | head -3 | tr '\n' ' ')"
  fi
}

# Jeton dénotant une ressource PERSISTANTE (volume, répertoire de contenu).
PERSIST='grav_base_directory|base_directory|_reg\.base_directory|/data/(pages|accounts|data|images)|grav_(pages|accounts|data|images)_directory|grav_secret_directory|persistent|volume'

# --- 1. Destruction de volumes / répertoires persistants (GSO-REQ-040/079/102) ---
check_absent "aucun 'docker compose down --volumes' / 'remove_volumes'" \
  'compose[[:space:]].*down.*(--volumes|[[:space:]]-v([[:space:]]|$))|down_v|remove_volumes:[[:space:]]*(true|yes)'
check_absent "aucun 'docker volume rm' / 'docker volume prune' / 'docker system prune'" \
  'docker[[:space:]]+volume[[:space:]]+(rm|prune)|docker[[:space:]]+system[[:space:]]+prune|volume[[:space:]]+prune'
check_absent "aucun 'docker rm' / 'docker rmi' / 'container prune'" \
  'docker[[:space:]]+(rm|rmi)[[:space:]]|container[[:space:]]+prune'
# `rm -rf` et `state: absent` ne sont interdits QUE sur une ressource persistante
# (le `make clean` qui supprime roles/, collections/, .ansible/ est légitime).
check_absent "aucune suppression récursive d'un CHEMIN PERSISTANT (rm -rf …/data/…, base_directory)" \
  "(rm[[:space:]]+-[a-zA-Z]*[rf][a-zA-Z]*[[:space:]].*($PERSIST))|(($PERSIST).*rm[[:space:]]+-[a-zA-Z]*[rf])"
check_absent "aucun 'state: absent' sur une ressource persistante (GSO-REQ-040)" \
  "state:[[:space:]]*absent"

# --- 2. Synchronisation / restauration automatique de contenu (GSO-REQ-033/077/078/113) ---
check_absent "aucun rsync ni script de synchronisation de contenu" \
  'rsync|sync[-_]content|content[-_]sync|git[[:space:]]+pull.*(pages|accounts|data)'
check_absent "aucune restauration / import automatique de sauvegarde de contenu" \
  '(restore|import)[-_]?(backup|volume|content|data)|backup[-_]restore|tar[[:space:]]+.*-x.*(pages|accounts|data)'

# --- 3. Pas de rollback automatique après échec (GSO-REQ-114) ---
# aucun bloc rescue/always, ni ignore_errors couplé à une reprise, dans les
# playbooks de mutation : un échec s'arrête, l'humain décide.
# capture le code de CHAQUE fichier d'abord (le `$( )` de `code_only` va à
# son terme), puis grep sur la valeur déjà capturée (here-string) — jamais
# `code_only "$f" | grep -q` : SIGPIPE possible sous `set -o pipefail` si le
# grep -q aval sort tôt -> faux négatif sur ce garde-fou.
rescue_hit="$(for f in $(git ls-files 'playbooks/*.yml' 'playbooks/**/*.yml'); do
  _fc="$(code_only "$f" || true)"
  grep -qE 'rescue:|always:' <<<"$_fc" && echo "$f"
done || true)"
if [ -z "$rescue_hit" ]; then
  pass "aucun bloc rescue/always dans les playbooks : un échec de mise à jour ne déclenche aucun rollback automatique (GSO-REQ-114)"
else
  fail "bloc rescue/always dans un playbook (enchaînement aveugle possible) : $rescue_hit"
fi
# cas négatif synthétique (fichier temporaire, dépôt courant jamais touché) :
# un bloc rescue: DOIT être détecté par cette même logique.
_l7neg="$(gso_mktemp_dir l7-guard-neg)"
trap 'rm -rf "$_l7neg"' EXIT
printf 'tasks:\n  - block:\n      - debug: {}\n    rescue:\n      - debug: {}\n' > "$_l7neg/p.yml"
_neg_fc="$(code_only "$_l7neg/p.yml" || true)"
grep -qE 'rescue:|always:' <<<"$_neg_fc" \
  && pass "cas négatif : un bloc rescue: synthétique est bien détecté par cette logique" \
  || fail "cas négatif : un bloc rescue: synthétique n'est PAS détecté (faux négatif)"

# --- 4. Journal de versions du rôle jamais réécrit (GSO-REQ-117) ---
check_absent "l'orchestrateur n'écrit jamais .deployed_state.yml / .deployed_version / deployed_versions.log" \
  '(copy|template|lineinfile|blockinfile|replace|shell|command).*(\.deployed_state\.yml|\.deployed_version|deployed_versions\.log)|>[[:space:]]*.*deployed_versions\.log'

# --- 5. Aucune voie de surcharge CLI de l'image / version / digest (GSO-REQ-109) ---
check_absent "aucun wrapper ne relaie -e / --extra-vars / --version / --digest / --image" \
  '\-\-extra-vars|[[:space:]]-e[[:space:]]+(grav_|version=|digest=|image=)|\-\-(version|digest|image)[[:space:]]'
# la traduction lit la version/digest EXCLUSIVEMENT du registre
if grep -qE 'grav_version:[[:space:]]*"\{\{[[:space:]]*_reg\.version' playbooks/_shared/translate.yml \
   && grep -qE 'grav_digest:[[:space:]]*"\{\{[[:space:]]*_reg\.digest' playbooks/_shared/translate.yml; then
  pass "grav_version / grav_digest proviennent EXCLUSIVEMENT du registre (_reg.*) — GSO-REQ-109/110"
else
  fail "la traduction ne lit pas version/digest exclusivement depuis le registre"
fi

# --- 6. Aucun nouveau playbook / wrapper / cible / intention de mise à jour ou rollback ---
bad_pb="$(git ls-files 'playbooks/*' | grep -E 'update|rollback' || true)"
bad_sc="$(git ls-files 'scripts/*'   | grep -E 'update|rollback' || true)"
[ -z "$bad_pb$bad_sc" ] && pass "aucun playbook/script 'update*' ou 'rollback*' (usage déclaratif de deploy-site.yml — contrat §13.1/§15)" \
  || fail "playbook/script de mise à jour ou rollback créé : $bad_pb $bad_sc"
if grep -qE '^(update|rollback):' Makefile; then
  fail "cible Makefile 'update' ou 'rollback' introduite"
else
  pass "aucune cible make update / make rollback"
fi
# capture d'abord (le `$( )` de `all_code` va à son terme), grep ensuite sur
# la valeur déjà capturée — jamais `all_code | grep -q` (même risque SIGPIPE).
_all_code_captured="$(all_code || true)"
if grep -qE "_gso_intent:[[:space:]]*(update|rollback)" <<<"$_all_code_captured"; then
  fail "intention _gso_intent 'update' ou 'rollback' introduite"
else
  pass "aucune nouvelle intention _gso_intent (deploy/restart/stop inchangés)"
fi
# cas négatif synthétique : une intention _gso_intent: update DOIT être détectée
_neg_intent='_gso_intent: update'
grep -qE "_gso_intent:[[:space:]]*(update|rollback)" <<<"$_neg_intent" \
  && pass "cas négatif : une intention _gso_intent: update synthétique est bien détectée" \
  || fail "cas négatif : une intention _gso_intent: update n'est PAS détectée (faux négatif)"
# la liste fermée des playbooks de mutation reste deploy/restart/stop
if grep -qE 'deploy-site\.yml \| restart-site\.yml \| stop-site\.yml\)' scripts/lib/site-mutation.sh \
   && ! grep -qE 'update-site\.yml|rollback-site\.yml' scripts/lib/site-mutation.sh; then
  pass "site-mutation.sh : liste fermée de playbooks inchangée (deploy/restart/stop)"
else
  fail "site-mutation.sh : liste de playbooks modifiée par L7"
fi

# --- 7. GSO-REQ-102 : ce garde-fou est bien exécuté par la CI ---
if grep -qE 'l7-persistence-guard\.sh' .github/workflows/ci.yml; then
  pass "la CI exécute ce garde-fou de persistance (GSO-REQ-102)"
else
  fail "la CI ne référence pas l7-persistence-guard.sh (GSO-REQ-102)"
fi

# --- 8. GSO-REQ-039 : aucun secret dans le registre non secret / retiré ---
if git grep -qIE '(admin_password|admin_email|admin_user|vault_grav_sites|secrets:)' -- \
     inventories/example/group_vars/all/grav_sites.yml 2>/dev/null; then
  fail "le registre non secret d'exemple contient un champ de secret (GSO-REQ-039)"
else
  pass "aucun secret dans le registre non secret (GSO-REQ-039)"
fi

# --- 9. Chemin opérateur mutant inchangé par L7 ---
# le diff de la branche L7 vs main ne doit toucher aucun composant du chemin deploy.
base="$(git merge-base HEAD main 2>/dev/null || true)"
if [ -n "$base" ]; then
  touched="$(git diff --name-only "$base"..HEAD -- \
      scripts/deploy.sh scripts/lib/site-mutation.sh playbooks/deploy-site.yml \
      playbooks/_shared/mutate.yml playbooks/_shared/translate.yml || true)"
  [ -z "$touched" ] && pass "L7 ne modifie aucun composant du chemin deploy (deploy.sh, site-mutation.sh, deploy-site.yml, mutate.yml, translate.yml)" \
    || fail "L7 a modifié le chemin deploy : $touched"
else
  pass "chemin deploy : pas de base de comparaison (branche non divergée)"
fi

finish
