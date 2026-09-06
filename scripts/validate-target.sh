#!/usr/bin/env bash
# grav-sites-ops — sélecteur fermé (lot L3).
#
# Valide localement, en LECTURE SEULE, que SITE désigne exactement un hôte
# actif cohérent avec l'inventaire imposé, le registre et (si résolvable) le
# vault. Termine avec un code non nul AVANT tout appel a ansible-playbook en
# cas d'écart (GSO-REQ-053, 056, 083-086, 093-095, 107, 138).
#
# Usage :  scripts/validate-target.sh <SITE>
#
# SEUL argument accepté : SITE. Aucune option (`-i`, `--inventory`,
# `--limit`, `--root`, ...) : la racine du dépôt et l'inventaire
# (inventories/production/hosts.yml) sont déterminés depuis l'emplacement
# canonique de ce script, jamais depuis le répertoire courant, une option
# ou une variable d'environnement.
#
# En cas de succès, écrit `TARGET <site>` : l'appelant transmet cette valeur
# à --limit entre guillemets, sans réinterprétation shell.

set -euo pipefail
SELF="$(readlink -f "$0" 2>/dev/null || realpath "$0")"
HERE="$(cd "$(dirname "$SELF")" && pwd -P)"
exec python3 "$HERE/lib/gso_validate.py" selector "$@"
