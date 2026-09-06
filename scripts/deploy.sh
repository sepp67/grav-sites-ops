#!/usr/bin/env bash
# grav-sites-ops — chemin opérateur de déploiement d'UN site (lot L4).
#
#   SITE littéral
#     -> préflight local (scripts/validate-target.sh, sélecteur fermé L3)
#     -> verrou de concurrence (flock, par site)
#     -> playbook deploy-site.yml (assertions internes + préflight structurel
#        + traduction + invocation UNIQUE de sepp67.grav_site)
#
# SEUL argument accepté : SITE. Aucune option ne peut substituer la racine,
# l'inventaire ou la limite (GSO-REQ-053, GSO-REQ-084). L'inventaire est fixé
# à inventories/production/hosts.yml, résolu depuis l'emplacement de ce
# script. `--limit` vaut EXACTEMENT le littéral SITE validé.
#
# Le verrou (flock sur un descripteur hérité par ansible-playbook) est
# libéré de façon fiable par le noyau en succès, échec ou interruption
# (GSO-REQ-096). Une tentative concurrente échoue proprement (code 75) sans
# lancer le rôle.

set -euo pipefail

SELF="$(readlink -f "$0" 2>/dev/null || realpath "$0")"
HERE="$(cd "$(dirname "$SELF")" && pwd -P)"
ROOT="$(dirname "$HERE")"

SITE="${1:-}"
if [ "$#" -gt 1 ]; then
  echo "grav-sites-ops : deploy.sh n'accepte que SITE (reçu : $*)" >&2
  exit 2
fi

# --- Niveau 1 : sélecteur fermé (préflight local) -------------------------
"$HERE/validate-target.sh" "$SITE"

# --- Verrou de concurrence par site -------------------------------------
lock_base="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/grav-sites-ops/locks"
mkdir -p "$lock_base"
exec 9>"$lock_base/${SITE}.lock"
if ! flock -n 9; then
  echo "grav-sites-ops : une opération est déjà en cours sur '${SITE}' — abandon." >&2
  exit 75
fi

# --- Niveau 2 : playbook (le descripteur 9 reste ouvert -> verrou tenu) ---
exec ansible-playbook \
  -i "$ROOT/inventories/production/hosts.yml" \
  "$ROOT/playbooks/deploy-site.yml" \
  --limit "$SITE"
