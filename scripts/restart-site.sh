#!/usr/bin/env bash
# grav-sites-ops — intention `restart` : redémarrer l'instance d'UN site,
# SANS changer sa référence désirée (version / digest inchangés — GSO-REQ-088).
#
# SEUL argument : SITE. Aucune option. Même chemin et même verrou que
# `deploy` (scripts/lib/site-mutation.sh) : le playbook dédié fixe l'état à
# `restarted`, jamais l'opérateur.

set -euo pipefail
[ "$#" -eq 1 ] || { echo "grav-sites-ops : restart-site.sh n'accepte que SITE (reçu : $*)" >&2; exit 2; }
SELF="$(readlink -f "$0" 2>/dev/null || realpath "$0")"
HERE="$(cd "$(dirname "$SELF")" && pwd -P)"
exec "$HERE/lib/site-mutation.sh" restart-site.yml "$1"
