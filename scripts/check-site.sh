#!/usr/bin/env bash
# grav-sites-ops — contrôle de dérive d'UN site (lot L6).
#
# LECTURE SEULE : compare l'état désiré (registre), l'état appliqué
# (.deployed_state.yml) et l'état réel (conteneur + endpoint) ; classe la
# dérive (contrat §16.5) ; ne corrige rien (GSO-REQ-090/122).
#
# SEUL argument : SITE. Aucune option. Le chemin (sélecteur fermé -> playbook
# --limit, SANS verrou) est dans scripts/lib/site-check.sh.

set -euo pipefail
[ "$#" -eq 1 ] || { echo "grav-sites-ops : check-site.sh n'accepte que SITE (reçu : $*)" >&2; exit 2; }
SELF="$(readlink -f "$0" 2>/dev/null || realpath "$0")"
HERE="$(cd "$(dirname "$SELF")" && pwd -P)"
exec "$HERE/lib/site-check.sh" check-site.yml "$1"
