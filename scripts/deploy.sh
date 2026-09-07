#!/usr/bin/env bash
# grav-sites-ops — intention `deploy` : déployer / actualiser UN site selon
# le registre (lot L4).
#
# SEUL argument : SITE. Aucune option. Le chemin (sélecteur -> verrou ->
# assertions -> second préflight structurel -> traduction -> rôle) est dans
# scripts/lib/site-mutation.sh.

set -euo pipefail
[ "$#" -eq 1 ] || { echo "grav-sites-ops : deploy.sh n'accepte que SITE (reçu : $*)" >&2; exit 2; }
SELF="$(readlink -f "$0" 2>/dev/null || realpath "$0")"
HERE="$(cd "$(dirname "$SELF")" && pwd -P)"
exec "$HERE/lib/site-mutation.sh" deploy-site.yml "$1"
