# shellcheck shell=bash
# grav-sites-ops — helpers communs aux tests GSO-T* (lot L0).
# Ce fichier n'est pas executable : il est source par les scripts de test.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT

# Validateur partagé unique (registre + vault + sélecteur + préflight).
GSO_VALIDATE="$REPO_ROOT/scripts/lib/gso_validate.py"
export GSO_VALIDATE

# Harnais de test du sélecteur : injecte une racine synthétique par appel
# direct des fonctions internes (jamais exposé à l'opérateur).
GSO_SELECT_HARNESS="$REPO_ROOT/tests/lib/selector_harness.py"
export GSO_SELECT_HARNESS

# l3_tmptree <nom-fixture> <destdir> : recopie les scripts réels + l'arbre
# de production de la fixture dans <destdir>, qui devient un mini-dépôt dont
# les wrappers résolvent <destdir> comme racine canonique.
l3_tmptree() {
  local fixture="$1" dest="$2"
  mkdir -p "$dest"
  cp -r "$REPO_ROOT/scripts" "$dest/scripts"
  if [ -d "$REPO_ROOT/tests/fixtures/$fixture/inventories" ]; then
    cp -r "$REPO_ROOT/tests/fixtures/$fixture/inventories" "$dest/inventories"
  fi
  if [ -d "$REPO_ROOT/tests/fixtures/$fixture/registry" ]; then
    cp -r "$REPO_ROOT/tests/fixtures/$fixture/registry" "$dest/registry"
  fi
}

# l4_tmptree <nom-fixture> <destdir> : comme l3_tmptree + scripts/deploy.sh,
# les playbooks et ansible.cfg. L'appelant ajoute ensuite
# <destdir>/inventories/production/group_vars/all/vault.yml (synthétique) et
# <destdir>/roles/sepp67.grav_site (doublure ou vrai rôle).
l4_tmptree() {
  local fixture="$1" dest="$2"
  l3_tmptree "$fixture" "$dest"
  cp -r "$REPO_ROOT/playbooks" "$dest/playbooks"
  cp "$REPO_ROOT/ansible.cfg" "$dest/ansible.cfg"
  mkdir -p "$dest/roles" "$dest/collections"
}

# gso_spy_role_into <destdir> : installe la DOUBLURE sepp67.grav_site.
gso_spy_role_into() {
  cp -r "$REPO_ROOT/tests/lib/spy-role/sepp67.grav_site" "$1/roles/sepp67.grav_site"
}

# gso_fake_docker_into <destdir> : installe une FAUSSE CLI `docker`
# AUTONOME dans <destdir>/fakebin/docker — chemin ABSOLU, destiné à être
# passé tel quel via GSO_TEST_DOCKER_BIN (lu par _shared/observe.yml sur le
# CONTRÔLEUR, jamais sur la cible). Aucune variable d'environnement : la
# tâche réelle "docker inspect" tourne sous become: true (nécessaire —
# prouvé sur VM réelle avec le compte technique hors du groupe docker) et
# `sudo` réinitialise l'environnement (env_reset) avant d'exécuter la
# commande — toute variable positionnée côté appelant (FAKE_DOCKER_DIR,
# FAKE_DOCKER_UNAVAILABLE) n'atteint donc jamais ce script une fois invoqué
# via `sudo`. Le script se localise lui-même (BASH_SOURCE) et lit/écrit
# EXCLUSIVEMENT sous <destdir>/fakedocker/, appelé <destdir> car chaque
# arbre de scénario de test installe sa PROPRE copie (un fakebin/docker par
# arbre, jamais un binaire partagé) :
#   <destdir>/fakedocker/<container>.json  -> `docker inspect <container>`
#                                              le sert (absent => "No such
#                                              object", code 1, "[]")
#   <destdir>/fakedocker/.unavailable       -> présent => "Cannot connect to
#                                              the Docker daemon", code 1
#                                              (remplace FAKE_DOCKER_UNAVAILABLE)
# Toute sous-commande susceptible de muter (run/rm/stop/start/restart/pull/
# create/kill/prune) est REFUSÉE bruyamment (code 97) : un test qui la
# déclencherait échoue au lieu de passer en silence.
gso_fake_docker_into() {
  local dest="$1"
  mkdir -p "$dest/fakebin" "$dest/fakedocker"
  cat > "$dest/fakebin/docker" <<'SH'
#!/usr/bin/env bash
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
DATA_DIR="$SELF_DIR/../fakedocker"
# Preuve d'invocation (non sensible : horodatage + sous-commande) — permet
# aux tests de prouver que ce faux Docker autonome a bien été appelé, sans
# dépendre du seul résultat de la classification.
echo "$(date +%s) $*" >> "$DATA_DIR/.calls.log"
if [ -f "$DATA_DIR/.unavailable" ]; then
  echo "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?" >&2
  exit 1
fi
case "${1:-}" in
  inspect)
    shift
    [ "${1:0:1}" = "-" ] && { shift; shift; }   # ignore --format ... (non utilisé ici)
    f="$DATA_DIR/${1}.json"
    if [ -f "$f" ]; then cat "$f"; exit 0; fi
    echo "Error: No such object: ${1}" >&2
    echo "[]"
    exit 1
    ;;
  ps)
    exit 0 ;;
  run|rm|stop|start|restart|pull|create|kill|prune|exec|compose|network|volume|rmi|update|cp|commit|build|tag|push|load|save|import|export|rename|pause|unpause)
    echo "FAKE-DOCKER-REFUS : sous-commande mutante '$*' interdite pendant un test de contrôle" >&2
    exit 97
    ;;
  *)
    echo "fake docker: sous-commande non gérée : $*" >&2
    exit 2
    ;;
esac
SH
  chmod +x "$dest/fakebin/docker"
}

# gso_fake_sudo_into <destdir> : installe un FAUX `sudo` AUTONOME dans
# <destdir>/fakebin/sudo — destiné à être déclaré comme
# `ansible_become_exe` dans l'inventaire SYNTHÉTIQUE d'un arbre de test
# (chemin absolu, jamais dans un fichier de production). Objectif : rendre
# GSO-T19/GSO-T20 reproductibles SANS privilège réel, en émulant
# uniquement ce dont le plugin `become: sudo` d'Ansible a besoin — jamais
# une vraie élévation.
#
# Contrat exact sondé empiriquement (audit privilèges 2026-09-16) sur les
# flags par défaut du plugin sudo (`-H -S -n`) :
#   sudo -H -S -n -u <user> <shell> -c '<commande>'
# où <commande> contient déjà, telle que construite par Ansible lui-même,
# le marqueur "echo BECOME-SUCCESS-<hash> ; ...". Ce script ne fait QUE
# reconnaître les options attendues puis `exec` la commande finale TELLE
# QUELLE, sans élévation réelle (le process reste celui de l'utilisateur
# courant) — le marqueur BECOME-SUCCESS est donc préservé automatiquement,
# puisqu'il fait partie de la commande exécutée, pas quelque chose que ce
# script doit lui-même produire. Toute forme imprévue (option non reconnue,
# absence de "<shell> -c") échoue bruyamment (code 98) plutôt que
# d'accepter arbitrairement.
#
# Traçabilité (non sensible : utilisateur cible + nombre d'arguments,
# jamais le contenu de la commande) dans <destdir>/fakebin/.sudo-calls.log
# — permet aux tests de prouver que ce faux sudo a bien été appelé ET que
# l'utilisateur cible est resté "root" (become réellement engagé).
#
# <destdir>/fakebin/.deny-become (marqueur, absent par défaut) : s'il est
# présent, ce faux sudo REFUSE l'élévation (code 1, message générique sur
# stderr) au lieu d'exécuter la commande — reproduit délibérément la forme
# "MODULE FAILURE" qu'Ansible rapporte pour un échec de become réel, afin
# de tester le diagnostic de production sans dépendre d'un hôte réellement
# privé de privilège.
gso_fake_sudo_into() {
  local dest="$1"
  mkdir -p "$dest/fakebin"
  cat > "$dest/fakebin/sudo" <<'SH'
#!/usr/bin/env bash
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
LOG="$SELF_DIR/.sudo-calls.log"
DENY_MARKER="$SELF_DIR/.deny-become"
becuser=""
while [ $# -gt 0 ]; do
  case "$1" in
    -H|-S|-n) shift ;;
    -p) [ $# -ge 2 ] || { echo "fake-sudo: -p sans valeur" >&2; exit 98; }; shift 2 ;;
    -u) [ $# -ge 2 ] || { echo "fake-sudo: -u sans valeur" >&2; exit 98; }; becuser="$2"; shift 2 ;;
    -*)
      echo "fake-sudo: option non prevue : $1" >&2
      exit 98
      ;;
    *)
      break
      ;;
  esac
done
if [ $# -lt 2 ] || [ "$2" != "-c" ]; then
  echo "fake-sudo: forme de commande non prevue (attendu : <shell> -c '<commande>')" >&2
  exit 98
fi
echo "user=${becuser:-?} argc=$#" >> "$LOG"
if [ -f "$DENY_MARKER" ]; then
  echo "fake-sudo: elevation refusee (test)" >&2
  exit 1
fi
exec "$@"
SH
  chmod +x "$dest/fakebin/sudo"
}

# gso_mktemp_dir <tag> : cree un repertoire temporaire au PREFIXE RECONNAISSABLE
# (`gso-<tag>.`) et borne a la zone temporaire du systeme. A preferer a
# `mktemp -d` nu, dont le prefixe `tmp.` est indistinguable et complique la
# verification d'absence de residu.
gso_mktemp_dir() {
  local tag="${1:?gso_mktemp_dir : tag requis}"
  mktemp -d "${TMPDIR:-/tmp}/gso-${tag}.XXXXXXXX"
}

# gso_isolate_runtime <tmpdir> : redirige l'espace runtime vers un
# sous-repertoire de <tmpdir>. `scripts/lib/site-mutation.sh` situe ses
# verrous `flock` sous `${XDG_RUNTIME_DIR}/grav-sites-ops/locks/` ; sans cette
# isolation, chaque test qui emprunte le chemin operateur laisse un fichier de
# verrou vide dans le dossier runtime REEL. Apres `rm -rf "<tmpdir>"`, aucun
# verrou ne subsiste. L'etat du dossier runtime reel est memorise pour la
# preuve de non-regression `gso_assert_runtime_clean`.
gso_isolate_runtime() {
  local tmpdir="${1:?gso_isolate_runtime : <tmpdir> requis}"
  _GSO_REAL_RUNTIME="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/grav-sites-ops"
  _GSO_REAL_RUNTIME_SNAPSHOT="$(find "$_GSO_REAL_RUNTIME" 2>/dev/null | sort || true)"
  _GSO_WORKTREE_SNAPSHOT="$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null || true)"
  export _GSO_REAL_RUNTIME _GSO_REAL_RUNTIME_SNAPSHOT _GSO_WORKTREE_SNAPSHOT
  export XDG_RUNTIME_DIR="$tmpdir/xdg-runtime"
  mkdir -p "$XDG_RUNTIME_DIR/grav-sites-ops/locks"
}

# gso_assert_runtime_clean : preuve de non-regression a appeler avant `finish`
# dans tout test ayant emprunte le chemin operateur. Verifie que
#   1. le dossier runtime REEL n'a pas ete modifie par le test (aucun verrou
#      de test cree hors de l'espace isole) ;
#   2. le depot ne contient aucune modification ni fichier non suivi
#      (les tests n'ecrivent que sous leur repertoire temporaire).
gso_assert_runtime_clean() {
  local now
  now="$(find "${_GSO_REAL_RUNTIME:-/nonexistent}" 2>/dev/null | sort || true)"
  if [ "$now" = "${_GSO_REAL_RUNTIME_SNAPSHOT-}" ]; then
    pass "aucun verrou de test dans le dossier runtime reel"
  else
    fail "residu dans le dossier runtime reel : $(comm -13 <(printf '%s\n' "${_GSO_REAL_RUNTIME_SNAPSHOT-}") <(printf '%s\n' "$now") | tr '\n' ' ')"
  fi
  local wt_now
  wt_now="$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null || true)"
  if [ "$wt_now" = "${_GSO_WORKTREE_SNAPSHOT-}" ]; then
    pass "depot inchange par le test (aucun fichier cree ni modifie hors du repertoire temporaire)"
  else
    fail "le test a modifie le depot : $(comm -13 <(printf '%s\n' "${_GSO_WORKTREE_SNAPSHOT-}") <(printf '%s\n' "$wt_now") | tr '\n' ' ')"
  fi
}

FAILURES=0

pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*"; FAILURES=$((FAILURES + 1)); }
info() { printf '      %s\n' "$*"; }
skip() { printf 'SKIP  %s\n' "$*"; }

finish() {
  printf -- '----\n'
  if [ "$FAILURES" -eq 0 ]; then
    printf '%s: OK\n' "${TEST_ID:-test}"
    exit 0
  fi
  printf '%s: %d verification(s) en echec\n' "${TEST_ID:-test}" "$FAILURES"
  exit 1
}

# tracked_files [pathspec...] : liste les fichiers suivis par Git.
tracked_files() {
  git -C "$REPO_ROOT" ls-files -- "$@"
}
