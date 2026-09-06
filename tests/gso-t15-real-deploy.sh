#!/usr/bin/env bash
# GSO-T15 — Déploiement fonctionnel d'UN seul site, avec conteneur Docker
# RÉEL et éphémère (préflight du lot L4, exception d'exécution autorisée
# pour ce seul test).
#
# TEST D'ACCEPTATION LOCAL — non exécuté par la CI standard (aucune image
# préchargée garantie, aucun identifiant GHCR). Lancé par `make test-functional`
# ou `bash tests/run-all.sh --functional`. Préconditions et digest exact :
# docs/TESTING.md. À exécuter OBLIGATOIREMENT avant toute autorisation de
# release.
#
# Chemin opérateur complet : scripts/deploy.sh -> sélecteur fermé -> verrou
# -> deploy-site.yml (assertions + préflight structurel + traduction) ->
# invocation UNIQUE du VRAI rôle sepp67.grav_site v2.0.0 -> un conteneur
# grav-runtime éphémère -> contrôle fonctionnel -> destruction contrôlée.
#
# Garde-fous : localhost + ansible_connection=local uniquement ; données,
# identifiants et secrets SYNTHÉTIQUES ; noms préfixés `gso-t15-` + suffixe
# unique ; publication HTTP sur 127.0.0.1 uniquement ; répertoire mktemp ;
# nettoyage en succès comme en échec ; suppression des SEULES ressources
# créées ; jamais de `docker … prune`.

TEST_ID="GSO-T15"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

IMG_REF="ghcr.io/sepp67/grav-runtime"
IMG_VERSION="1.0.4"      # défini par ansible-role-grav-site (molecule/deploy, molecule/multi_instance)
IMG_DIGEST="sha256:d130f333c6566a26856c271656b21ce2d06793f9c4af24e620b53da14e4d640f"

# --- 0. Préconditions : blocage explicite (jamais un SKIP, jamais un succès) ---
# GSO-T15 est un test d'acceptation LOCAL (docs/TESTING.md). Il n'est pas
# exécuté par la CI standard. En l'absence d'une précondition, il ÉCHOUE.
BLOCK=0
command -v docker >/dev/null && docker version >/dev/null 2>&1 \
  || { fail "BLOCAGE : Docker indisponible — GSO-T15 exige un conteneur réel"; BLOCK=1; }
docker image inspect "$IMG_REF:$IMG_VERSION" >/dev/null 2>&1 \
  || { fail "BLOCAGE : image $IMG_REF:$IMG_VERSION absente localement — la tirer manuellement par digest ($IMG_DIGEST) ; aucun pull automatique"; BLOCK=1; }
[ -d "$REPO_ROOT/roles/sepp67.grav_site" ] \
  || { fail "BLOCAGE : rôle sepp67.grav_site non installé — 'make install-role'"; BLOCK=1; }
[ -d "$REPO_ROOT/collections/ansible_collections/community/docker" ] \
  || { fail "BLOCAGE : collection community.docker absente — 'make install-role'"; BLOCK=1; }
[ "$BLOCK" -eq 0 ] || finish

SUF="$(printf '%x' "$(date +%s)")$$$RANDOM"
SITE="gso-t15-$SUF"
CTN="$SITE"
NET="${SITE}_default"                     # projet compose = basename(base_directory) = $SITE

# Port libre déterministe sur la loopback
PORT=0
for p in $(seq 18715 18815); do
  if ! (exec 3<>"/dev/tcp/127.0.0.1/$p") 2>/dev/null; then PORT="$p"; break; fi
  exec 3>&- 2>/dev/null || true
done
[ "$PORT" != 0 ] || { fail "aucun port libre dans 18715-18815"; finish; }

T="$(mktemp -d)"
# Garde positive : l'arborescence de test doit vivre sous la zone temporaire,
# jamais dans un répertoire de projet ou de home.
case "$T/" in
  "${TMPDIR:-/tmp}"/*/ | /tmp/*/ | /var/tmp/*/) : ;;
  *) fail "mktemp hors de la zone temporaire attendue : $T"; finish ;;
esac

created_container=""
created_network=""
LOCK="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/grav-sites-ops/locks/${SITE}.lock"

cleanup() {
  [ -n "$created_container" ] && docker rm -f "$created_container" >/dev/null 2>&1
  [ -n "$created_network" ] && docker network rm "$created_network" >/dev/null 2>&1
  # sous-arbres appartenant à l'uid conteneur (82) : suppression par un
  # conteneur jetable de la MÊME image approuvée, borné à $T.
  if [ -d "$T" ]; then
    docker run --rm -v "$T:/w" --entrypoint sh "$IMG_REF:$IMG_VERSION" \
      -c 'rm -rf /w/* /w/.[!.]* 2>/dev/null || true' >/dev/null 2>&1 || true
    rm -rf "$T" 2>/dev/null || true
  fi
  rm -f "$LOCK" 2>/dev/null || true
}
trap cleanup EXIT

# --- 1. Aucune ressource ne préexiste sous ces noms exacts ---
if docker ps -a --format '{{.Names}}' | grep -qx "$CTN" \
   || docker network ls --format '{{.Name}}' | grep -qx "$NET"; then
  fail "collision : une ressource porte déjà le nom $CTN ou $NET"
  finish
fi
pass "noms uniques et libres : conteneur=$CTN réseau=$NET port=127.0.0.1:$PORT"

# --- 2. Arborescence de test SYNTHÉTIQUE (localhost, connexion locale) ---
l4_tmptree l3-prod-ok "$T"
rm -rf "$T/inventories/production/group_vars" "$T/registry"
mkdir -p "$T/inventories/production/group_vars/all"
ln -s "$REPO_ROOT/roles/sepp67.grav_site" "$T/roles/sepp67.grav_site"
ln -s "$REPO_ROOT/collections/ansible_collections" "$T/collections/ansible_collections"

cat > "$T/inventories/production/hosts.yml" <<YML
all:
  children:
    grav_servers:
      hosts:
        $SITE:
          ansible_connection: local
          ansible_host: 127.0.0.1
YML
cat > "$T/inventories/production/group_vars/all/grav_sites.yml" <<YML
grav_sites:
  $SITE:
    project_name: $SITE
    image: $IMG_REF
    version: "$IMG_VERSION"
    digest: "$IMG_DIGEST"
    container_name: $CTN
    base_directory: $T/$SITE
    bind_address: 127.0.0.1
    http_port: $PORT
    state: started
    force_pull: false
    manage_docker: false
    site_check_path: /admin
    extra_environment: {}
YML
cat > "$T/inventories/production/group_vars/all/vault.yml" <<YML
vault_grav_sites:
  $SITE:
    admin_user: gso-t15-admin
    admin_password: SYNTHETIC-GSO-T15-PW-$SUF
    admin_email: gso-t15@example.invalid
    admin_type: both
vault_retired_grav_sites: {}
YML
cat > "$T/inventories/production/group_vars/all/main.yml" <<YML
grav_deploy_wait_retries: 40
grav_deploy_wait_delay: 3
ansible_python_interpreter: "{{ ansible_playbook_python }}"
YML

# --- 3. Exécution du chemin opérateur réel ---
RUN="$T.run.log"
drc=0
( cd "$T" && timeout 300 bash scripts/deploy.sh "$SITE" ) > "$RUN" 2>&1 || drc=$?
# on connaît maintenant les ressources potentiellement créées
docker ps -a --format '{{.Names}}' | grep -qx "$CTN" && created_container="$CTN"
docker network ls --format '{{.Name}}' | grep -qx "$NET" && created_network="$NET"

if [ "$drc" -eq 0 ]; then
  pass "scripts/deploy.sh $SITE : rc=0"
else
  sed 's/^/      | /' "$RUN" | grep -viE 'deprecat|TripleDES' | tail -20
  fail "scripts/deploy.sh a échoué (rc=$drc)"
  finish
fi

# --- 4. Ordre : préflight -> verrou -> assertions -> rôle ---
python3 - "$RUN" <<'PY'
import re, sys
txt = open(sys.argv[1], encoding="utf-8", errors="replace").read()
def pos(pat):
    m = re.search(pat, txt)
    return m.start() if m else -1
p_sel = pos(r'selector : \d+ contrôles OK')          # sélecteur (verrou juste après)
p_assert = pos(r"TASK \[Assertion : --limit")
p_pref = pos(r"TASK \[Préflight structurel local")
p_role = pos(r"TASK \[sepp67\.grav_site :")
order = [("sélecteur", p_sel), ("assertion", p_assert),
         ("préflight structurel", p_pref), ("rôle", p_role)]
missing = [n for n, p in order if p < 0]
if missing:
    print("      FAIL étapes absentes du journal :", missing); sys.exit(1)
seq = [p for _, p in order]
if seq != sorted(seq):
    print("      FAIL ordre incorrect :", [n for n, _ in order]); sys.exit(1)
print("      OK sélecteur -> assertion -> préflight structurel -> rôle")
sys.exit(0)
PY
[ $? -eq 0 ] && pass "ordre respecté : sélecteur/verrou -> assertions -> préflight -> rôle" \
             || fail "ordre du chemin opérateur non respecté"

# --- 5. Exactement une invocation du rôle, un seul conteneur ---
inv="$(grep -cF 'TASK [Invoquer sepp67.grav_site' "$RUN" || true)"
rtasks="$(grep -cE '^TASK \[sepp67\.grav_site : ' "$RUN" || true)"
if [ "$inv" = 1 ] && [ "$rtasks" -ge 1 ] && [ -f "$T/$SITE/.deployed_state.yml" ]; then
  pass "rôle invoqué exactement une fois (1 include_role, $rtasks tâches du rôle, .deployed_state.yml écrit)"
else
  fail "invocation du rôle anormale : include_role x$inv, tâches rôle x$rtasks"
fi
nctn="$(docker ps --filter "name=^gso-t15-" --format '{{.Names}}' | wc -l)"
[ "$nctn" = 1 ] && pass "exactement un conteneur gso-t15-* en fonctionnement" || fail "$nctn conteneurs gso-t15-*"

# --- 6. Contrôle fonctionnel : conteneur créé et sain ---
status="$(docker inspect --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' "$CTN" 2>/dev/null)"
case "$status" in
  "running healthy") pass "conteneur $CTN : running + healthy" ;;
  *) fail "état inattendu du conteneur : '$status'" ;;
esac
code="$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/admin" || echo ERR)"
[ "$code" = 200 ] && pass "le site répond sur http://127.0.0.1:$PORT/admin (200)" \
                  || fail "le site ne répond pas comme attendu ($code)"

# --- 7. Digest épinglé effectivement utilisé, pas de pull ---
used="$(docker inspect --format '{{.Config.Image}}' "$CTN" 2>/dev/null)"
case "$used" in
  *"@${IMG_DIGEST}") pass "image déployée par digest épinglé ($IMG_DIGEST)" ;;
  *) fail "image déployée inattendue : $used" ;;
esac

# --- 8. Aucune fuite de valeur synthétique ---
if grep -qE "SYNTHETIC-GSO-T15-PW-$SUF" "$RUN"; then
  fail "fuite du mot de passe synthétique dans la sortie du déploiement"
else
  pass "aucune valeur secrète synthétique dans la sortie"
fi

# --- 9. Verrou libéré après succès ---
if ( exec 7>"$LOCK"; flock -n 7 ); then
  pass "verrou de concurrence libéré après le déploiement"
else
  fail "verrou toujours tenu après le déploiement"
fi

# --- 10. Nettoyage puis vérification d'absence de résidu ---
cleanup
trap - EXIT
resid=0
docker ps -a --format '{{.Names}}' | grep -qx "$CTN" && { fail "conteneur résiduel $CTN"; resid=1; }
docker network ls --format '{{.Name}}' | grep -qx "$NET" && { fail "réseau résiduel $NET"; resid=1; }
[ -e "$T" ] && { fail "répertoire temporaire résiduel $T"; resid=1; }
[ -e "$LOCK" ] && { fail "fichier de verrou résiduel $LOCK"; resid=1; }
[ "$resid" -eq 0 ] && pass "aucun conteneur, réseau, fichier temporaire ou verrou résiduel"

finish
