#!/usr/bin/env bash
# grav-sites-ops — execution de la batterie de tests disponible.
#
# Ramasse automatiquement :
#   - gso-tNN-*.sh : tests numerotes de la matrice du contrat ;
#   - lN-*.sh      : preuves de mecanismes d'un lot sans numero GSO-T dedie
#                    (traçabilite explicite, ex. verrou de concurrence L4).
#
# GSO_SKIP_DOCKER=1 saute les tests exigeant un conteneur Docker (GSO-T15).

set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"
ROOT="$(cd "$DIR/.." && pwd)"

# Les tests dynamiques du lot L4 (traduction, déploiement) consomment le
# vrai rôle : l'installer une fois s'il manque et si des playbooks existent.
if [ -e "$ROOT/playbooks/deploy-site.yml" ] && [ ! -d "$ROOT/roles/sepp67.grav_site" ]; then
  echo "run-all : installation de sepp67.grav_site + community.docker (une fois)…"
  ( cd "$ROOT" && ansible-galaxy install -r requirements.yml ) || {
    echo "run-all : échec de l'installation des dépendances Ansible" >&2; exit 1; }
fi

mapfile -t scripts < <(find . -maxdepth 1 \( -name 'gso-t*.sh' -o -name 'l[0-9]-*.sh' \) | sort)

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
