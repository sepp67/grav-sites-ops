#!/usr/bin/env bash
# grav-sites-ops — préflight opérateur (lot L3).
#
# Sélecteur fermé + réutilisation des validateurs de registre et de vault
# (une seule implémentation : scripts/lib/gso_validate.py). LECTURE SEULE :
# ne déploie rien, n'ouvre aucun vault chiffré, ne contacte aucune machine,
# ne modifie aucun fichier. Échoue fermé (GSO-REQ-026, 038, 094, 095, 107).
#
# Usage :  scripts/preflight.sh <SITE>
#
# SEUL argument accepté : SITE (voir scripts/validate-target.sh). Aucune
# option ne peut substituer la racine du dépôt ni l'inventaire imposé.

set -euo pipefail
SELF="$(readlink -f "$0" 2>/dev/null || realpath "$0")"
HERE="$(cd "$(dirname "$SELF")" && pwd -P)"
exec python3 "$HERE/lib/gso_validate.py" preflight "$@"
