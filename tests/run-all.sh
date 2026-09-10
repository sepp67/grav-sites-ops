#!/usr/bin/env bash
# grav-sites-ops — batterie de tests.
#
# Ramasse :
#   - gso-tNN-*.sh : tests numerotes de la matrice du contrat ;
#   - lN-*.sh      : preuves de mecanismes d'un lot sans numero GSO-T dedie.
#
# GSO-T15 (deploiement fonctionnel avec conteneur Docker REEL) n'est execute
# QUE si --functional (ou GSO_RUN_FUNCTIONAL=1). Il n'est jamais saute
# silencieusement : il echoue si Docker, le role, la collection ou l'image
# grav-runtime epinglee ne sont pas deja disponibles (voir docs/TESTING.md).
#
#   bash tests/run-all.sh              # sous-ensemble 100 % reproductible
#   bash tests/run-all.sh --functional # + GSO-T15 (gate locale complete)

set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
ROOT="$(cd "$DIR/.." && pwd)"

FUNCTIONAL=0
[ "${1:-}" = "--functional" ] && FUNCTIONAL=1
[ "${GSO_RUN_FUNCTIONAL:-0}" = "1" ] && FUNCTIONAL=1

# Les tests dynamiques du lot L4 consomment le vrai role : l'installer une
# fois s'il manque et si des playbooks existent.
if [ -e "$ROOT/playbooks/deploy-site.yml" ] && [ ! -d "$ROOT/roles/sepp67.grav_site" ]; then
  echo "run-all : installation de sepp67.grav_site + community.docker (une fois)…"
  ( cd "$ROOT" && ansible-galaxy install -r requirements.yml ) || {
    echo "run-all : échec de l'installation des dépendances Ansible" >&2; exit 1; }
fi

mapfile -t all < <(find . -maxdepth 1 \( -name 'gso-t*.sh' -o -name 'l[0-9]-*.sh' -o -name 'l[0-9][0-9]-*.sh' \) | sort)
scripts=()
skipped_functional=""
for s in "${all[@]}"; do
  case "$s" in
    ./gso-t15-*)
      if [ "$FUNCTIONAL" -eq 1 ]; then scripts+=("$s")
      else skipped_functional="$(basename "$s" .sh)"; fi
      ;;
    *) scripts+=("$s") ;;
  esac
done

if [ "${#scripts[@]}" -eq 0 ]; then
  echo "aucun script de test trouve" >&2
  exit 1
fi

total=0
failed=0
declare -a failures=()

for s in "${scripts[@]}"; do
  total=$((total + 1))
  printf '\n=== %s ===\n' "$(basename "$s" .sh)"
  if bash "$s"; then :; else
    failed=$((failed + 1))
    failures+=("$(basename "$s" .sh)")
  fi
done

printf '\n========================================\n'
printf 'Total : %d   Reussis : %d   Echecs : %d\n' "$total" "$((total - failed))" "$failed"
if [ -n "$skipped_functional" ]; then
  printf 'NON EXECUTE (test fonctionnel local) : %s — `make test-functional`\n' "$skipped_functional"
fi
if [ "$failed" -ne 0 ]; then
  printf 'En echec : %s\n' "${failures[*]}"
  exit 1
fi
printf 'Tous les tests executes sont au vert.\n'
