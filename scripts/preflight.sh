#!/usr/bin/env bash
# grav-sites-ops — préflight opérateur (lot L3).
#
# Sélecteur fermé + réutilisation des validateurs de registre et de vault
# (une seule implémentation : scripts/lib/gso_validate.py). LECTURE SEULE :
# ne déploie rien, n'ouvre aucun vault chiffré, ne contacte aucune machine,
# ne modifie aucun fichier. Échoue fermé (GSO-REQ-026, 038, 094, 095, 107).
#
# Ordre (contrat §14.2) : dépôt/paramètres -> inventaire imposé -> cible
# unique -> cohérence inventaire/registre/vault -> (connexion VM et rôle :
# lots ultérieurs).
#
# Usage opérateur :  scripts/preflight.sh <SITE>
# `--root` / `--action` : réservés aux tests.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$HERE/lib/gso_validate.py" preflight "$@"
