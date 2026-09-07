#!/usr/bin/env bash
# grav-sites-ops — contrôle de dérive de TOUT le parc actif (lot L6).
#
# LECTURE SEULE. Unique interface prévue pour parcourir `grav_servers`
# (contrat §13.7). Non mutant : aucune confirmation globale ne peut y
# déclencher une mutation (GSO-REQ-104). Ne corrige rien.
#
# AUCUN argument : `check-all` n'accepte ni SITE, ni option. Le chemin
# (cohérence déclarative -> playbook groupe, SANS verrou) est dans
# scripts/lib/site-check.sh.

set -euo pipefail
[ "$#" -eq 0 ] || { echo "grav-sites-ops : check-all.sh n'accepte aucun argument (reçu : $*)" >&2; exit 2; }
SELF="$(readlink -f "$0" 2>/dev/null || realpath "$0")"
HERE="$(cd "$(dirname "$SELF")" && pwd -P)"
exec "$HERE/lib/site-check.sh" check-all.yml
