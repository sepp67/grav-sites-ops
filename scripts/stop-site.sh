#!/usr/bin/env bash
# grav-sites-ops — intention `stop` : arrêter le conteneur d'UN site sur une
# VM encore active. Ne retire PAS le site du registre, n'arrête pas la VM,
# ne supprime ni conteneur, ni volume, ni répertoire persistant, ni fichier
# de déploiement (GSO-REQ-089). Réversible : le prochain `deploy` remet
# l'instance dans son état désiré.
#
# SEUL argument : SITE. Aucune option. Même chemin et même verrou que
# `deploy` (scripts/lib/site-mutation.sh) : le playbook dédié fixe l'état à
# `stopped`, jamais l'opérateur.

set -euo pipefail
[ "$#" -eq 1 ] || { echo "grav-sites-ops : stop-site.sh n'accepte que SITE (reçu : $*)" >&2; exit 2; }
SELF="$(readlink -f "$0" 2>/dev/null || realpath "$0")"
HERE="$(cd "$(dirname "$SELF")" && pwd -P)"
exec "$HERE/lib/site-mutation.sh" stop-site.yml "$1"
