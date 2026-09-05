#!/usr/bin/env bash
# GSO-T23 — Absence de dependance au control-repository.
#
# Verifie qu'aucun lien Ansible, Git, CI ou d'execution ne relie
# grav-sites-ops au control-repository (GSO-REQ-009, GSO-REQ-067).
#
# Nommer la frontiere en prose (documentation, libelles de tests) reste
# autorise : cela n'est pas une dependance. Le test cible donc les formes
# qui constituent effectivement une dependance : sous-module, URL/chemin de
# clone, reference dans requirements.yml ou dans un inventaire, import
# Ansible.

TEST_ID="GSO-T23"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

# --- 1. Aucun sous-module Git ---
if [ -f .gitmodules ]; then
  fail ".gitmodules present : sous-module interdit"
else
  pass "aucun sous-module Git"
fi

# --- 2. requirements.yml ne mentionne pas le control-repository ---
if git grep -qiE 'control[-_]repository' -- requirements.yml; then
  fail "requirements.yml reference le control-repository"
else
  pass "requirements.yml ne reference pas le control-repository"
fi

# --- 3. Aucune URL / chemin de clone du control-repository ---
# Delimiteur significatif avant le nom : ':' '/' 'git@' ou '../'.
url_hits="$(git grep -nIE '([:/]|git@|\.\./)control[-_]repository' -- \
  ':!tests/gso-t23-no-control-repository.sh' || true)"
if [ -n "$url_hits" ]; then
  fail "URL ou chemin de clone du control-repository :"
  printf '%s\n' "$url_hits" | sed 's/^/      | /'
else
  pass "aucune URL ni chemin de clone du control-repository"
fi

# --- 4. Aucun import/include Ansible pointant vers le control-repository ---
import_hits="$(git grep -nIE '(import_playbook|include_tasks|include_role|import_role|ansible\.builtin\.import).*control[-_]repository' -- \
  'playbooks/' 'inventories/' 'scripts/' 'registry/' || true)"
if [ -n "$import_hits" ]; then
  fail "import Ansible vers le control-repository :"
  printf '%s\n' "$import_hits" | sed 's/^/      | /'
else
  pass "aucun import Ansible vers le control-repository"
fi

# --- 5. Aucune variable d'environnement / secret CI nomme control-repository ---
ci_hits="$(git grep -nIE 'control[-_]repository' -- '.github/' \
  | grep -viE 'gso-t23|aucune dependance|no-control-repository' || true)"
if [ -n "$ci_hits" ]; then
  fail "reference active au control-repository dans la CI :"
  printf '%s\n' "$ci_hits" | sed 's/^/      | /'
else
  pass "CI : aucune reference active au control-repository"
fi

finish
