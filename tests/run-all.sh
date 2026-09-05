#!/usr/bin/env bash
# grav-sites-ops — execution de la batterie de tests disponible.
#
# Au lot L0, la batterie couvre GSO-T01, GSO-T02, GSO-T03, GSO-T04,
# GSO-T23 et GSO-T24. Les lots suivants ajoutent leurs propres scripts
# gso-t*.sh dans ce repertoire ; ils seront ramasses automatiquement.

set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

mapfile -t scripts < <(find . -maxdepth 1 -name 'gso-t*.sh' | sort)

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
  if bash "$s"; then
    :
  else
    failed=$((failed + 1))
    failures+=("$(basename "$s" .sh)")
  fi
done

printf '\n========================================\n'
printf 'Total : %d   Reussis : %d   Echecs : %d\n' "$total" "$((total - failed))" "$failed"
if [ "$failed" -ne 0 ]; then
  printf 'En echec : %s\n' "${failures[*]}"
  exit 1
fi
printf 'Tous les tests disponibles sont au vert.\n'
