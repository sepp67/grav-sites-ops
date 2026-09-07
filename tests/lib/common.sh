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

# gso_fake_docker_into <destdir> : installe une FAUSSE CLI `docker` dans
# <destdir>/fakebin/docker (à préfixer au PATH). Lecture seule, pilotée par
# l'environnement — aucun vrai conteneur, aucun daemon Docker :
#   FAKE_DOCKER_DIR=<dir>        -> `docker inspect <c>` rend <dir>/<c>.json
#                                  (absent => "No such object", code 1, "[]")
#   FAKE_DOCKER_UNAVAILABLE=1    -> "Cannot connect to the Docker daemon", code 1
# Toute sous-commande susceptible de muter (run/rm/stop/start/restart/pull/
# create/kill/prune) est REFUSÉE bruyamment (code 97) : un test qui la
# déclencherait échoue au lieu de passer en silence.
gso_fake_docker_into() {
  local dest="$1"
  mkdir -p "$dest/fakebin"
  cat > "$dest/fakebin/docker" <<'SH'
#!/usr/bin/env bash
if [ "${FAKE_DOCKER_UNAVAILABLE:-0}" = 1 ]; then
  echo "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?" >&2
  exit 1
fi
case "${1:-}" in
  inspect)
    shift
    [ "${1:0:1}" = "-" ] && { shift; shift; }   # ignore --format ... (non utilisé ici)
    f="${FAKE_DOCKER_DIR:-/nonexistent}/${1}.json"
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
