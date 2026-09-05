# shellcheck shell=bash
# grav-sites-ops — helpers communs aux tests GSO-T* (lot L0).
# Ce fichier n'est pas executable : il est source par les scripts de test.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT

FAILURES=0

pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
info() { printf '      %s\n' "$*"; }
skip() { printf 'SKIP  %s\n' "$*"; }

finish() {
  printf -- '----\n'
  if [ "$FAILURES" -eq 0 ]; then
    printf '%s: OK\n' "${TEST_ID:-test}"
    exit 0
  fi
  printf '%s: %d verification(s) en echec\n' "${TEST_ID:-test}" "$FAILURES"
  exit 1
}

# tracked_files [pathspec...] : liste les fichiers suivis par Git.
tracked_files() {
  git -C "$REPO_ROOT" ls-files -- "$@"
}
