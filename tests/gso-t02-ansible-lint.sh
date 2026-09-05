#!/usr/bin/env bash
# GSO-T02 — ansible-lint sans erreur.
#
# Au lot L0, il n'existe encore aucun contenu Ansible propre (playbooks,
# roles, tasks). Le test verifie que ansible-lint s'execute sans signaler
# de faute. La couverture reelle augmente avec les lots suivants.

TEST_ID="GSO-T02"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

out="$(ansible-lint --nocolor --offline 2>&1)" && rc=0 || rc=$?
printf '%s\n' "$out" | sed 's/^/      | /'

if [ "$rc" -ne 0 ]; then
  fail "ansible-lint a retourne un code non nul ($rc)"
  finish
fi

if printf '%s\n' "$out" | grep -qiE '(^| )failure\(s\)' \
  && ! printf '%s\n' "$out" | grep -qE '0 failure\(s\)'; then
  fail "ansible-lint signale au moins une faute"
else
  pass "ansible-lint : aucune faute"
fi

finish
