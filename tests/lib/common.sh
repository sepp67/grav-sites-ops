# shellcheck shell=bash
# grav-sites-ops — helpers communs aux tests GSO-T* (lot L0).
# Ce fichier n'est pas executable : il est source par les scripts de test.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT

# Validateur partagé unique (registre + vault + sélecteur + préflight).
GSO_VALIDATE="$REPO_ROOT/scripts/lib/gso_validate.py"
export GSO_VALIDATE

# Harnais de test du sélecteur : injecte une racine synthétique par appel
# direct des fonctions internes (jamais exposé à l'opérateur).
GSO_SELECT_HARNESS="$REPO_ROOT/tests/lib/selector_harness.py"
export GSO_SELECT_HARNESS

# l3_tmptree <nom-fixture> <destdir> : recopie les scripts réels + l'arbre
# de production de la fixture dans <destdir>, qui devient un mini-dépôt dont
# les wrappers résolvent <destdir> comme racine canonique.
l3_tmptree() {
  local fixture="$1" dest="$2"
  mkdir -p "$dest"
  cp -r "$REPO_ROOT/scripts" "$dest/scripts"
  if [ -d "$REPO_ROOT/tests/fixtures/$fixture/inventories" ]; then
    cp -r "$REPO_ROOT/tests/fixtures/$fixture/inventories" "$dest/inventories"
  fi
  if [ -d "$REPO_ROOT/tests/fixtures/$fixture/registry" ]; then
    cp -r "$REPO_ROOT/tests/fixtures/$fixture/registry" "$dest/registry"
  fi
}

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
