#!/usr/bin/env bash
# grav-sites-ops — sélecteur fermé (lot L3).
#
# Valide localement, en LECTURE SEULE, que SITE désigne exactement un hôte
# actif cohérent avec l'inventaire imposé, le registre et (si résolvable) le
# vault. Termine avec un code non nul AVANT tout appel à `ansible-playbook`
# en cas d'écart (GSO-REQ-053, 056, 083-086, 093-095, 107, 138).
#
# Usage opérateur :  scripts/validate-target.sh <SITE>
#   -> l'inventaire est FIXÉ à inventories/production/hosts.yml ; aucune
#      option ne peut le remplacer.
# En cas de succès, écrit une ligne `TARGET <site>` : l'appelant transmet
# cette valeur à `--limit` entre guillemets, sans réinterprétation shell.
#
# `--root <dir>` et `--action <...>` sont réservés aux tests.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$HERE/lib/gso_validate.py" selector "$@"
