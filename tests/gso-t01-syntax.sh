#!/usr/bin/env bash
# GSO-T01 — Syntaxe YAML, Ansible et inventaires.
#
# Au lot L0, seuls des fichiers YAML de harnais existent. La couverture
# s'etend automatiquement des que des playbooks et des inventaires
# apparaissent (lots L1 et suivants).

TEST_ID="GSO-T01"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

# --- 1. yamllint sur tous les fichiers YAML suivis ---
mapfile -t yaml_files < <(tracked_files '*.yml' '*.yaml' | grep -v -E '^(roles|collections)/' || true)
if [ "${#yaml_files[@]}" -eq 0 ]; then
  fail "aucun fichier YAML suivi (le harnais L0 doit en contenir)"
else
  if yamllint -c "$REPO_ROOT/.yamllint" --strict "${yaml_files[@]}"; then
    pass "yamllint --strict sur ${#yaml_files[@]} fichier(s) YAML"
  else
    fail "yamllint a signale des erreurs"
  fi
fi

# --- 2. Playbooks : verification de syntaxe Ansible ---
mapfile -t playbooks < <(tracked_files 'playbooks/*.yml' || true)
if [ "${#playbooks[@]}" -eq 0 ]; then
  skip "aucun playbook a ce stade (attendu au lot L1)"
else
  for pb in "${playbooks[@]}"; do
    if ansible-playbook --syntax-check "$pb" >/dev/null 2>&1; then
      pass "ansible-playbook --syntax-check $pb"
    else
      fail "syntaxe invalide : $pb"
    fi
  done
fi

# --- 3. Inventaires : parsing ---
mapfile -t inventories < <(tracked_files 'inventories/*/hosts.yml' || true)
if [ "${#inventories[@]}" -eq 0 ]; then
  skip "aucun inventaire a ce stade (attendu au lot L1)"
else
  for inv in "${inventories[@]}"; do
    if ansible-inventory -i "$inv" --list >/dev/null 2>&1; then
      pass "ansible-inventory parse $inv"
    else
      fail "inventaire non parsable : $inv"
    fi
  done
fi

finish
