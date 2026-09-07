#!/usr/bin/env bash
# grav-sites-ops — chemin opérateur COMMUN aux mutations d'UN site
# (deploy / restart / stop). Lots L4–L5.
#
#   SITE littéral
#     -> 1. préflight local / sélecteur   scripts/validate-target.sh (L3)
#     -> 2. verrou de concurrence          flock, MÊME fichier `${SITE}.lock`
#           pour deploy/restart/stop — deux mutations concurrentes sur un
#           même site sont impossibles (GSO-REQ-096)
#     -> 3. playbook DÉDIÉ à l'intention   assertions + second préflight
#           structurel + traduction fermée + invocation UNIQUE du rôle
#
# Usage INTERNE, jamais appelé directement par l'opérateur :
#   site-mutation.sh <playbook.yml> <SITE>
# <playbook.yml> est fixé par le wrapper appelant et validé ici contre une
# liste FERMÉE. L'opérateur ne fournit que SITE ; aucune option (inventaire,
# limite, racine, état) n'est acceptée. `--limit` vaut EXACTEMENT SITE.
#
# Les codes de sortie du sélecteur, du verrou et du playbook sont propagés
# tels quels (jamais masqués).

set -euo pipefail

PLAYBOOK="${1:-}"
SITE="${2:-}"

case "$PLAYBOOK" in
  deploy-site.yml | restart-site.yml | stop-site.yml) : ;;
  *)
    echo "grav-sites-ops : playbook d'intention non autorisé : '${PLAYBOOK}'" >&2
    exit 2
    ;;
esac
if [ "$#" -ne 2 ]; then
  echo "grav-sites-ops : site-mutation.sh attend exactement <playbook> <SITE>" >&2
  exit 2
fi

SELF="$(readlink -f "$0" 2>/dev/null || realpath "$0")"
LIB="$(cd "$(dirname "$SELF")" && pwd -P)"
SCRIPTS="$(dirname "$LIB")"
ROOT="$(dirname "$SCRIPTS")"

# --- 1. Sélecteur fermé (préflight local) ---
"$SCRIPTS/validate-target.sh" "$SITE"

# --- 2. Verrou de concurrence par site ---
lock_base="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/grav-sites-ops/locks"
mkdir -p "$lock_base"
exec 9>"$lock_base/${SITE}.lock"
if ! flock -n 9; then
  echo "grav-sites-ops : une mutation est déjà en cours sur '${SITE}' — abandon." >&2
  exit 75
fi

# --- 3. Playbook dédié (fd 9 hérité -> verrou tenu jusqu'à la fin) ---
exec ansible-playbook \
  -i "$ROOT/inventories/production/hosts.yml" \
  "$ROOT/playbooks/${PLAYBOOK}" \
  --limit "$SITE"
