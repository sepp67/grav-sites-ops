#!/usr/bin/env bash
# grav-sites-ops — chemin opérateur COMMUN au contrôle de dérive (lot L6).
#
# Le contrôle est STRICTEMENT NON MUTANT (contrat §13.7, §16 ; GSO-REQ-090) :
#   - aucune correction automatique, aucune intention deploy/restart/stop ;
#   - aucun `include_role`/`import_role` de sepp67.grav_site ;
#   - aucune écriture (registre, vault, inventaire, fichiers du rôle) ;
#   - aucun pull, aucun conteneur créé/supprimé/démarré/arrêté/redémarré ;
#   - AUCUN verrou de mutation : un check ne bloque jamais un déploiement.
#
#   check-site.yml  : SITE littéral -> sélecteur fermé L3 -> playbook --limit
#   check-all.yml   : aucun SITE -> cohérence déclarative du parc -> playbook
#
# Usage INTERNE, jamais appelé directement par l'opérateur :
#   site-check.sh check-site.yml <SITE>
#   site-check.sh check-all.yml
#
# Codes de sortie propagés SANS masquage. Convention (GSO-REQ-093) :
#   0  -> IN_SYNC (site, ou parc entier, conforme)
#   ≠0 -> refus de cible / incohérence déclarative (sélecteur ou validateur
#         de registre, codes L3 réutilisés tels quels) ; sinon échec de play
#         Ansible = dérive détectée ou état indéterminable. La CATÉGORIE
#         (§16.5) figure dans la sortie lisible.

set -euo pipefail

PLAYBOOK="${1:-}"
case "$PLAYBOOK" in
  check-site.yml | check-all.yml) : ;;
  *)
    echo "grav-sites-ops : playbook de contrôle non autorisé : '${PLAYBOOK}'" >&2
    exit 2
    ;;
esac

SELF="$(readlink -f "$0" 2>/dev/null || realpath "$0")"
LIB="$(cd "$(dirname "$SELF")" && pwd -P)"
SCRIPTS="$(dirname "$LIB")"
ROOT="$(dirname "$SCRIPTS")"
INV="$ROOT/inventories/production/hosts.yml"

case "$PLAYBOOK" in
  check-site.yml)
    SITE="${2:-}"
    if [ "$#" -ne 2 ]; then
      echo "grav-sites-ops : site-check.sh check-site.yml attend exactement <SITE>" >&2
      exit 2
    fi
    # 1. Sélecteur fermé (préflight local, lecture seule) — refuse une cible
    #    absente, retirée, ambiguë ou incohérente AVANT ansible-playbook.
    "$SCRIPTS/validate-target.sh" "$SITE"
    # 2. Playbook de contrôle, cible unique, sans verrou.
    exec ansible-playbook -i "$INV" "$ROOT/playbooks/check-site.yml" --limit "$SITE"
    ;;
  check-all.yml)
    if [ "$#" -ne 1 ]; then
      echo "grav-sites-ops : site-check.sh check-all.yml n'accepte aucun argument" >&2
      exit 2
    fi
    # 1. Dérive déclarative : cohérence inventaire <-> registre <-> vault,
    #    vérifiable SANS connexion aux VM (GSO-REQ-125). Échec = code non nul
    #    avant tout parcours du parc.
    python3 "$SCRIPTS/lib/gso_validate.py" registry \
      --inventory "$INV" --context production
    # 2. Vue du parc actif (groupe grav_servers), sans verrou, non mutant.
    exec ansible-playbook -i "$INV" "$ROOT/playbooks/check-all.yml"
    ;;
esac
