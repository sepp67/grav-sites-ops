#!/usr/bin/env bash
# L10 — Nettoyage vérifiable des ressources de test (GSO-REQ-148, GSO-REQ-149).
#
# Prouve :
#   - STATIQUE : chaque test qui crée un répertoire temporaire utilise un
#     préfixe reconnaissable (`gso_mktemp_dir`) et un `trap … rm -rf` ; chaque
#     test qui emprunte le chemin opérateur isole son espace de verrous
#     (`gso_isolate_runtime`) ; aucun test n'effectue de nettoyage NON BORNÉ
#     (`rm -rf /tmp/*`, `docker system prune`, `docker rm $(docker ps -aq)`…) ;
#   - DYNAMIQUE : après l'exécution d'un échantillon représentatif de tests
#     créateurs de ressources, il ne reste AUCUN conteneur / réseau `gso-t*`,
#     AUCUN verrou de test dans le dossier runtime réel, AUCUN `/tmp/gso-*`,
#     AUCUN `/tmp/tmp.*.run.log`, et le dépôt suivi est inchangé.
#
# 100 % local. N'exécute pas GSO-T15 (conteneur réel) — sa propre preuve de
# non-résidu est dans GSO-T15 §10.

TEST_ID="L10-CLEANUP"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"
code_only() { grep -vE '^[[:space:]]*#' "$1"; }

# --------------------------------------------------------------------------
# 1. Gardes statiques sur tous les tests
# --------------------------------------------------------------------------
missing_trap=""; missing_prefix=""
while IFS= read -r f; do
  c="$(code_only "$f")"
  b="$(basename "$f")"
  # un test « crée un répertoire temporaire » s'il appelle gso_mktemp_dir ou mktemp -d
  if echo "$c" | grep -qE '\bgso_mktemp_dir\b|\bmktemp -d\b'; then
    # trap direct 'rm -rf' OU trap d'une fonction de nettoyage
    if echo "$c" | grep -qE "^trap .*(rm -rf|cleanup)"; then :; else missing_trap="$missing_trap $b"; fi
    # préfixe reconnaissable : gso_mktemp_dir, ou un mktemp -d avec un gabarit nommé
    if echo "$c" | grep -qE '\bgso_mktemp_dir\b|mktemp -d +"?\$\{TMPDIR[^"]*/(gso|grav)'; then :; else missing_prefix="$missing_prefix $b"; fi
  fi
done < <(git ls-files 'tests/*.sh' ':!tests/run-all.sh' ':!tests/lib/**')

[ -z "$missing_trap" ]   && pass "tous les tests créateurs de tmp ont un trap de nettoyage" || fail "sans trap de nettoyage :$missing_trap"
[ -z "$missing_prefix" ] && pass "tous les tests créateurs de tmp utilisent un préfixe reconnaissable (gso_mktemp_dir)" || fail "mktemp nu :$missing_prefix"

# helpers du harnais : les trois primitives de propreté existent
for fn in gso_mktemp_dir gso_isolate_runtime gso_assert_runtime_clean gso_fake_docker_into; do
  grep -qE "^${fn}\(\)" tests/lib/common.sh && pass "harnais : \`$fn\` défini" || fail "harnais : \`$fn\` absent"
done

# GSO-T15 : nettoyage borné à $T + ses ressources nommées (jamais un prune)
if code_only tests/gso-t15-real-deploy.sh | grep -qE 'docker rm -f "\$created_container"' \
   && code_only tests/gso-t15-real-deploy.sh | grep -qE 'docker network rm "\$created_network"' \
   && ! code_only tests/gso-t15-real-deploy.sh | grep -qwE 'prune'; then
  pass "GSO-T15 : nettoyage borné aux ressources qu'il a créées (jamais un prune)"
else
  fail "GSO-T15 : nettoyage non conforme"
fi

# aucun test n'exécute un nettoyage NON borné (motif en DÉBUT de commande, hors
# arguments de grep / git grep qui, eux, RECHERCHENT ces motifs interdits).
broad=""
while IFS= read -r f; do
  if code_only "$f" | grep -vE 'grep|git grep' \
       | grep -qE '(^|\bthen |;\s*|&&\s*|\|\|\s*)(docker (system |image |volume |network )?prune|docker rm +-f? *\$\(docker ps|rm -rf +/tmp/\*)'; then
    broad="$broad $(basename "$f")"
  fi
done < <(git ls-files 'tests/*.sh' ':!tests/lib/**')
[ -z "$broad" ] && pass "aucun test n'exécute de nettoyage non borné (prune, docker rm en masse, rm -rf /tmp/*)" || fail "nettoyage non borné :$broad"

# la doublure de docker (L6) refuse toute sous-commande mutante -> pas de résidu Docker en L6
if code_only tests/lib/common.sh | grep -qE 'FAKE-DOCKER-REFUS'; then
  pass "fausse CLI docker (L6/L8) : refuse run/rm/stop/prune -> aucun conteneur possible"
else
  fail "fausse CLI docker : garde mutante absente"
fi

# --------------------------------------------------------------------------
# 2. Preuve dynamique : échantillon représentatif, puis zéro résidu
# --------------------------------------------------------------------------
REAL_RT="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/grav-sites-ops"
snap_rt() { find "$REAL_RT" 2>/dev/null | sort || true; }
snap_tmp() { find "${TMPDIR:-/tmp}" -maxdepth 1 \( -name 'gso-*' -o -name 'tmp.*.run.log' \) 2>/dev/null | sort || true; }
snap_dk() { docker ps -aq --filter 'name=gso-t' 2>/dev/null | sort || true; docker network ls --filter 'name=gso-t' -q 2>/dev/null | sort || true; }
snap_git() { git -C "$REPO_ROOT" status --porcelain || true; }

rt0="$(snap_rt)"; tmp0="$(snap_tmp)"; dk0="$(snap_dk)"; git0="$(snap_git)"

# un test par famille de ressource :
#   gso-t13  -> doublure de rôle + verrou (chemin opérateur)
#   l4-concurrency-lock -> verrous flock
#   gso-t19  -> fausse CLI docker + fixtures
for s in gso-t13-translate l4-concurrency-lock gso-t19-drift-classification l10-multisite-isolation; do
  if bash "tests/$s.sh" > "$DIR/../$s.l10out" 2>&1; then
    rm -f "$DIR/../$s.l10out"
  else
    sed 's/^/   | /' "$DIR/../$s.l10out" | tail -8; rm -f "$DIR/../$s.l10out"
    fail "échantillon $s a échoué"
  fi
done

rt1="$(snap_rt)"; tmp1="$(snap_tmp)"; dk1="$(snap_dk)"; git1="$(snap_git)"
[ "$rt0" = "$rt1" ]   && pass "dossier runtime réel inchangé après l'échantillon (aucun verrou de test)" || fail "verrou résiduel : $(comm -13 <(echo "$rt0") <(echo "$rt1"))"
[ "$tmp0" = "$tmp1" ] && pass "aucun /tmp/gso-* ni /tmp/tmp.*.run.log résiduel" || fail "temp résiduel : $(comm -13 <(echo "$tmp0") <(echo "$tmp1"))"
[ "$dk0" = "$dk1" ]   && pass "aucun conteneur / réseau gso-t* résiduel" || fail "Docker résiduel : $(comm -13 <(echo "$dk0") <(echo "$dk1"))"
[ "$git0" = "$git1" ] && pass "dépôt suivi inchangé après l'échantillon" || fail "dépôt modifié : $(comm -13 <(echo "$git0") <(echo "$git1"))"

# --------------------------------------------------------------------------
# 3. make clean ne laisse aucun artefact hors roles/collections ignorés
# --------------------------------------------------------------------------
( cd "$REPO_ROOT" && make clean >/dev/null 2>&1 )
resid="$(git -C "$REPO_ROOT" status --porcelain --ignored | grep -vE '^!! (roles|collections)/$' || true)"
[ -z "$resid" ] && pass "make clean : working tree entièrement propre (hors roles/ collections/ ignorés)" || fail "résidu après make clean : $resid"

finish
