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

# trap EXIT unique pour tout le script : les appels `trap … EXIT` ne
# s'empilent PAS en bash (chacun remplace le précédent) — un trap par
# répertoire temporaire créé plus loin dans ce fichier laisserait les
# premiers résidus non nettoyés. Un seul trap, posé ici, couvre les trois
# répertoires créés plus bas (variables vides tant que non affectées).
_l10_cleanup() {
  [ -n "${_neg_t15:-}" ]   && rm -rf "$_neg_t15"
  [ -n "${_neg_broad:-}" ] && rm -rf "$_neg_broad"
  [ -n "${sample_log:-}" ] && rm -rf "$sample_log"
}
trap _l10_cleanup EXIT

# --------------------------------------------------------------------------
# 1. Gardes statiques sur tous les tests
# --------------------------------------------------------------------------
missing_trap=""; missing_prefix=""
while IFS= read -r f; do
  c="$(code_only "$f" || true)"
  b="$(basename "$f")"
  # un test « crée un répertoire temporaire » s'il AFFECTE le résultat de
  # gso_mktemp_dir ou de `mktemp -d` à une variable (forme `x="$(… )"`).
  if echo "$c" | grep -qE '=[[:space:]]*"?\$\((gso_mktemp_dir|mktemp -d)'; then
    if echo "$c" | grep -qE "^trap .*(rm -rf|cleanup)"; then :; else missing_trap="$missing_trap $b"; fi
    if echo "$c" | grep -qE '=[[:space:]]*"?\$\(gso_mktemp_dir|=[[:space:]]*"?\$\(mktemp -d[[:space:]]+"?\$\{TMPDIR[^"]*/(gso|grav)'; then :; else missing_prefix="$missing_prefix $b"; fi
  fi
done < <(git ls-files 'tests/*.sh' ':!tests/run-all.sh' ':!tests/lib/**')

[ -z "$missing_trap" ]   && pass "tous les tests créateurs de tmp ont un trap de nettoyage" || fail "sans trap de nettoyage :$missing_trap"
[ -z "$missing_prefix" ] && pass "tous les tests créateurs de tmp utilisent un préfixe reconnaissable (gso_mktemp_dir)" || fail "mktemp nu :$missing_prefix"

# helpers du harnais : les trois primitives de propreté existent
for fn in gso_mktemp_dir gso_isolate_runtime gso_assert_runtime_clean gso_fake_docker_into; do
  grep -qE "^${fn}\(\)" tests/lib/common.sh && pass "harnais : \`$fn\` défini" || fail "harnais : \`$fn\` absent"
done

# GSO-T15 : nettoyage borné à $T + ses ressources nommées (jamais un prune)
# Capture d'abord (le `$( )` de `code_only` va à son terme), grep ensuite sur
# la valeur déjà capturée — jamais `code_only "$f" | grep -q` : SIGPIPE
# possible sous `set -o pipefail` si un grep -q aval sort tôt -> faux négatif.
# (Lecture seule de gso-t15-real-deploy.sh : ce fichier n'est PAS modifié ici.)
_t15_fc="$(code_only tests/gso-t15-real-deploy.sh || true)"
if grep -qE 'docker rm -f "\$created_container"' <<<"$_t15_fc" \
   && grep -qE 'docker network rm "\$created_network"' <<<"$_t15_fc" \
   && ! grep -qwE 'prune' <<<"$_t15_fc"; then
  pass "GSO-T15 : nettoyage borné aux ressources qu'il a créées (jamais un prune)"
else
  fail "GSO-T15 : nettoyage non conforme"
fi
# cas négatif synthétique (fichier temporaire, dépôt courant jamais touché) :
# un `docker ... prune` DOIT être détecté par cette même logique.
_neg_t15="$(gso_mktemp_dir l10-cleanup-neg)"
printf 'docker rm -f "$created_container"\ndocker network rm "$created_network"\ndocker system prune -f\n' > "$_neg_t15/gso-t15-fake.sh"
_neg_t15_fc="$(code_only "$_neg_t15/gso-t15-fake.sh" || true)"
if grep -qE 'docker rm -f "\$created_container"' <<<"$_neg_t15_fc" \
   && grep -qE 'docker network rm "\$created_network"' <<<"$_neg_t15_fc" \
   && ! grep -qwE 'prune' <<<"$_neg_t15_fc"; then
  fail "cas négatif : un « docker system prune » synthétique n'est PAS détecté (faux négatif)"
else
  pass "cas négatif : un « docker system prune » synthétique est bien détecté par cette logique"
fi

# aucun test n'exécute un nettoyage NON borné (motif en DÉBUT de commande, hors
# arguments de grep / git grep qui, eux, RECHERCHENT ces motifs interdits).
# Capture ENTIÈREMENT le pipeline de filtrage (`code_only | grep -v`, sans
# `-q` en aval dans le `$( )` : les deux commandes vont à leur terme) puis
# applique le `grep -q` final sur la valeur déjà capturée (here-string) —
# jamais de `-q` DANS un pipeline multi-étages : sous `set -o pipefail`, un
# SIGPIPE d'un maillon intermédiaire ferait échouer tout le pipeline même si
# le dernier grep a trouvé la ligne -> faux négatif sur ce garde-fou.
broad=""
while IFS= read -r f; do
  _filtered="$(code_only "$f" | grep -vE 'grep|git grep' || true)"
  if grep -qE '(^|\bthen |;\s*|&&\s*|\|\|\s*)(docker (system |image |volume |network )?prune|docker rm +-f? *\$\(docker ps|rm -rf +/tmp/\*)' <<<"$_filtered"; then
    broad="$broad $(basename "$f")"
  fi
done < <(git ls-files 'tests/*.sh' ':!tests/lib/**')
[ -z "$broad" ] && pass "aucun test n'exécute de nettoyage non borné (prune, docker rm en masse, rm -rf /tmp/*)" || fail "nettoyage non borné :$broad"
# cas négatif synthétique (fichier temporaire, dépôt courant jamais touché) :
# un nettoyage NON borné (docker system prune) DOIT être détecté.
_neg_broad="$(gso_mktemp_dir l10-cleanup-neg-broad)"
printf 'docker system prune -f\n' > "$_neg_broad/x.sh"
_neg_broad_filtered="$(code_only "$_neg_broad/x.sh" | grep -vE 'grep|git grep' || true)"
grep -qE '(^|\bthen |;\s*|&&\s*|\|\|\s*)(docker (system |image |volume |network )?prune|docker rm +-f? *\$\(docker ps|rm -rf +/tmp/\*)' <<<"$_neg_broad_filtered" \
  && pass "cas négatif : un « docker system prune » non borné synthétique est bien détecté par cette logique" \
  || fail "cas négatif : un nettoyage non borné synthétique n'est PAS détecté (faux négatif)"

# la doublure de docker (L6) refuse toute sous-commande mutante -> pas de résidu Docker en L6
_common_fc="$(code_only tests/lib/common.sh || true)"
if grep -qE 'FAKE-DOCKER-REFUS' <<<"$_common_fc"; then
  pass "fausse CLI docker (L6/L8) : refuse run/rm/stop/prune -> aucun conteneur possible"
else
  fail "fausse CLI docker : garde mutante absente"
fi
# cas négatif synthétique : le motif FAKE-DOCKER-REFUS DOIT être détecté quand présent
_neg_marker='echo "FAKE-DOCKER-REFUS"'
grep -qE 'FAKE-DOCKER-REFUS' <<<"$_neg_marker" \
  && pass "cas négatif : le motif FAKE-DOCKER-REFUS synthétique est bien détecté par cette logique" \
  || fail "cas négatif : le motif FAKE-DOCKER-REFUS synthétique n'est PAS détecté (faux négatif)"

# --------------------------------------------------------------------------
# 2. Preuve dynamique : échantillon représentatif, puis zéro résidu
# --------------------------------------------------------------------------
REAL_RT="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/grav-sites-ops"
snap_rt() { find "$REAL_RT" 2>/dev/null | sort || true; }
snap_tmp() { find "${TMPDIR:-/tmp}" -maxdepth 1 \( -name 'gso-*' -o -name 'tmp.*.run.log' \) 2>/dev/null | sort || true; }
snap_dk() { docker ps -aq --filter 'name=gso-t' 2>/dev/null | sort || true; docker network ls --filter 'name=gso-t' -q 2>/dev/null | sort || true; }
snap_git() { git -C "$REPO_ROOT" status --porcelain || true; }

# journaux de l'échantillon : HORS du dépôt (sinon `git status` les verrait
# le temps de l'exécution et le contrôle « dépôt suivi inchangé » deviendrait
# sensible à une course).
sample_log="$(gso_mktemp_dir l10-cleanup-sample)"

rt0="$(snap_rt)"; tmp0="$(snap_tmp)"; dk0="$(snap_dk)"; git0="$(snap_git)"

# un test par famille de ressource :
#   gso-t13  -> doublure de rôle + verrou (chemin opérateur)
#   l4-concurrency-lock -> verrous flock
#   gso-t19  -> fausse CLI docker + fixtures
#   l10-multisite-isolation -> trois sites, ansible-playbook -vv
for s in gso-t13-translate l4-concurrency-lock gso-t19-drift-classification l10-multisite-isolation; do
  if ! bash "tests/$s.sh" > "$sample_log/$s.out" 2>&1; then
    sed 's/^/   | /' "$sample_log/$s.out" | tail -8
    fail "échantillon $s a échoué"
  fi
done

# les répertoires temporaires des sous-tests sont nettoyés par leur `trap`
# EXIT, qui a déjà eu lieu ; on retire notre propre journal des deux relevés.
rt1="$(snap_rt)"; dk1="$(snap_dk)"; git1="$(snap_git)"
tmp1="$(snap_tmp | grep -vF "$sample_log" || true)"
tmp0="$(printf '%s\n' "$tmp0" | grep -vF "$sample_log" || true)"
[ "$rt0" = "$rt1" ]   && pass "dossier runtime réel inchangé après l'échantillon (aucun verrou de test)" || fail "verrou résiduel : $(comm -13 <(echo "$rt0") <(echo "$rt1"))"
[ "$tmp0" = "$tmp1" ] && pass "aucun /tmp/gso-* ni /tmp/tmp.*.run.log résiduel" || fail "temp résiduel : $(comm -13 <(echo "$tmp0") <(echo "$tmp1"))"
[ "$dk0" = "$dk1" ]   && pass "aucun conteneur / réseau gso-t* résiduel" || fail "Docker résiduel : $(comm -13 <(echo "$dk0") <(echo "$dk1"))"
[ "$git0" = "$git1" ] && pass "dépôt suivi inchangé après l'échantillon" || fail "dépôt modifié : $(comm -13 <(echo "$git0") <(echo "$git1"))"

# --------------------------------------------------------------------------
# 3. La cible `make clean` ne supprime QUE des artefacts ignorés / générés
#    (jamais un fichier suivi). Vérification STATIQUE — on n'exécute pas
#    `make clean` ici pour ne pas retirer roles/ dont GSO-T15 a besoin.
# --------------------------------------------------------------------------
clean_body="$(awk '/^clean:/{f=1;next} f&&/^[a-zA-Z]/{f=0} f' Makefile)"
if printf '%s' "$clean_body" | grep -qE 'git |inventories/|playbooks/|scripts/|docs/|registry/|tests/[a-z]'; then
  fail "la cible make clean touche un chemin suivi"
else
  pass "make clean : ne cible que roles/ collections/ caches / __pycache__ / *.retry (aucun fichier suivi)"
fi

finish
