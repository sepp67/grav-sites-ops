#!/usr/bin/env bash
# GSO-T19 — Contrôle des trois états et classification de dérive (lot L6).
#
# 100 % local, déterministe, LECTURE SEULE : fausse CLI `docker`, fixtures
# synthétiques, `.deployed_state.yml` fabriqués à la main, aucun conteneur
# réel, aucune connexion. Prouve (contrat §16, §18.10 ; GSO-REQ-118/120/121/
# 122/123/124/144) :
#   - les trois niveaux (désiré / appliqué / réel) sont distingués ;
#   - un état conforme -> IN_SYNC, code 0 ;
#   - une référence différente -> REFERENCE_DRIFT ;
#   - un conteneur arrêté (désiré started) -> STOPPED ;
#   - `stopped` désiré + conteneur arrêté -> IN_SYNC, jamais STOPPED ;
#   - un état inconnu (fichier illisible, docker indisponible) -> UNKNOWN ;
#   - une VM simulée injoignable -> UNREACHABLE ;
#   - NOT_DEPLOYED, CONFIG_DRIFT, UNHEALTHY ;
#   - aucune mutation : ni .deployed_state.yml / .deployed_version /
#     deployed_versions.log modifiés, ni sous-commande `docker` mutante,
#     ni include_role du rôle ;
#   - aucune valeur secrète dans la sortie ; .last_failure.log signalé mais
#     jamais affiché ;
#   - codes de sortie stables ; fixtures inchangées.

TEST_ID="GSO-T19"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

tmp="$(gso_mktemp_dir t19)"
trap 'rm -rf "$tmp"' EXIT
gso_isolate_runtime "$tmp"

CLASS="$REPO_ROOT/scripts/lib/gso_classify.py"

# --------------------------------------------------------------------------
# Partie A — le classificateur (fonction pure) : les 8 catégories du §16.5
# --------------------------------------------------------------------------
classify() {  # <json> -> catégorie
  printf '%s' "$1" | python3 "$CLASS" | python3 -c 'import json,sys; print(json.load(sys.stdin)["category"])'
}
D='"image":"r/i","version":"1.0.0","digest":"","container_name":"c","base_directory":"/b","bind_address":"127.0.0.1","http_port":8080,"state":"started","site_check_path":"/"'
Dstop='"image":"r/i","version":"1.0.0","digest":"","container_name":"c","base_directory":"/b","bind_address":"127.0.0.1","http_port":8080,"state":"stopped","site_check_path":"/"'

expect() {  # <label> <catégorie attendue> <json>
  local got; got="$(classify "$3")"
  [ "$got" = "$2" ] && pass "classif « $1 » -> $2" || fail "classif « $1 » -> $got (attendu $2)"
}
expect "conforme (started+healthy)" IN_SYNC \
  "{\"desired\":{$D},\"applied\":{\"effective_reference\":\"r/i:1.0.0\"},\"real\":{\"reachable\":true,\"container_exists\":true,\"container_image\":\"r/i:1.0.0\",\"running\":true,\"health\":\"healthy\",\"published_port\":8080,\"http_status\":200}}"
expect "conforme (stopped désiré + arrêté) — GSO-REQ-121" IN_SYNC \
  "{\"desired\":{$Dstop},\"applied\":{\"effective_reference\":\"r/i:1.0.0\"},\"real\":{\"reachable\":true,\"container_exists\":true,\"container_image\":\"r/i:1.0.0\",\"running\":false,\"health\":\"none\",\"published_port\":8080,\"http_status\":null}}"
expect "référence appliquée différente" REFERENCE_DRIFT \
  "{\"desired\":{\"image\":\"r/i\",\"version\":\"2.0.0\",\"digest\":\"\",\"container_name\":\"c\",\"base_directory\":\"/b\",\"bind_address\":\"127.0.0.1\",\"http_port\":8080,\"state\":\"started\"},\"applied\":{\"effective_reference\":\"r/i:1.0.0\"},\"real\":{\"reachable\":true,\"container_exists\":true,\"container_image\":\"r/i:1.0.0\",\"running\":true,\"health\":\"healthy\",\"published_port\":8080}}"
expect "conteneur arrêté (désiré started)" STOPPED \
  "{\"desired\":{$D},\"applied\":{\"effective_reference\":\"r/i:1.0.0\"},\"real\":{\"reachable\":true,\"container_exists\":true,\"container_image\":\"r/i:1.0.0\",\"running\":false,\"health\":\"none\"}}"
expect "conteneur en cours alors que désiré stopped" CONFIG_DRIFT \
  "{\"desired\":{$Dstop},\"applied\":{\"effective_reference\":\"r/i:1.0.0\"},\"real\":{\"reachable\":true,\"container_exists\":true,\"container_image\":\"r/i:1.0.0\",\"running\":true,\"health\":\"healthy\"}}"
expect "port publié différent" CONFIG_DRIFT \
  "{\"desired\":{$D},\"applied\":{\"effective_reference\":\"r/i:1.0.0\"},\"real\":{\"reachable\":true,\"container_exists\":true,\"container_image\":\"r/i:1.0.0\",\"running\":true,\"health\":\"none\",\"published_port\":9999,\"http_status\":200}}"
expect "rien de déployé" NOT_DEPLOYED \
  "{\"desired\":{$D},\"applied\":null,\"applied_error\":\"absent\",\"real\":{\"reachable\":true,\"container_exists\":false}}"
expect "healthcheck négatif" UNHEALTHY \
  "{\"desired\":{$D},\"applied\":{\"effective_reference\":\"r/i:1.0.0\"},\"real\":{\"reachable\":true,\"container_exists\":true,\"container_image\":\"r/i:1.0.0\",\"running\":true,\"health\":\"unhealthy\"}}"
expect "état appliqué illisible" UNKNOWN \
  "{\"desired\":{$D},\"applied\":null,\"applied_error\":\"unreadable\",\"real\":{\"reachable\":true,\"container_exists\":true,\"container_image\":\"r/i:1.0.0\",\"running\":true,\"health\":\"healthy\"}}"
expect "docker indisponible" UNKNOWN \
  "{\"desired\":{$D},\"applied\":{\"effective_reference\":\"r/i:1.0.0\"},\"real\":{\"reachable\":true},\"real_error\":\"docker_unavailable\"}"
expect "échec d'exécution du module (module_failure)" UNKNOWN \
  "{\"desired\":{$D},\"applied\":{\"effective_reference\":\"r/i:1.0.0\"},\"real\":{\"reachable\":true},\"real_error\":\"module_failure\"}"
expect "VM injoignable" UNREACHABLE \
  "{\"desired\":{$D},\"applied\":null,\"real\":{\"reachable\":false},\"real_error\":\"unreachable\"}"

# le classificateur ne modifie rien, code toujours 0, aucune valeur secrète
printf '%s' "{\"desired\":{$D},\"applied\":{\"effective_reference\":\"r/i:1.0.0\",\"admin_password\":\"SECRET-XYZ\"}}" \
  | python3 "$CLASS" > "$tmp/cout" 2>&1
[ $? -eq 0 ] && pass "classificateur : code 0" || fail "classificateur : code non nul"
grep -q 'SECRET-XYZ' "$tmp/cout" && fail "classificateur : fuite d'une valeur" || pass "classificateur : aucune valeur non pertinente recopiée"

# --------------------------------------------------------------------------
# Partie B — check-site.yml de bout en bout (fausse CLI docker, lecture seule)
# --------------------------------------------------------------------------
# Pas de fausse CLI ni de PATH partagés ici : la tâche réelle "docker
# inspect" tourne sous become: true (nécessaire, prouvé sur VM réelle) et
# `sudo` réinitialise à la fois PATH (secure_path) et l'environnement
# (env_reset) avant d'exécuter la commande — ni un préfixage PATH, ni une
# variable d'environnement (FAKE_DOCKER_DIR, FAKE_DOCKER_UNAVAILABLE) ne
# survit à la traversée de `sudo`. Chaque arbre créé par mk_tree() installe
# donc sa PROPRE fausse CLI autonome (gso_fake_docker_into "$T", voir
# tests/lib/common.sh) : chemin absolu passé via GSO_TEST_DOCKER_BIN,
# lu par _shared/observe.yml sur le CONTRÔLEUR uniquement (même mécanisme
# que GSO_SPY_OUTPUT) — jamais transmis à la cible ni à travers sudo.
#
# become: true lui-même reste RÉEL (playbooks/_shared/observe.yml
# inchangé) : ce sandbox n'a pas de sudo non interactif pour le prouver de
# bout en bout, donc chaque arbre installe aussi un FAUX sudo autonome
# (gso_fake_sudo_into "$T") déclaré UNIQUEMENT dans l'inventaire
# SYNTHÉTIQUE de cet arbre via `ansible_become_exe` (variable de connexion
# native d'Ansible — aucun fichier de production modifié). Ce faux sudo
# n'élève aucun privilège réel : il valide juste la forme des arguments
# attendus du plugin become sudo puis exécute la commande finale telle
# quelle (voir tests/lib/common.sh pour le contrat exact sondé).

mk_tree() {  # -> echo path
  local T="$tmp/tree-$RANDOM"
  l4_tmptree l3-prod-ok "$T"
  gso_spy_role_into "$T"          # doublure : si un include_role survenait, on le verrait
  mkdir -p "$T/sites/grav-alpha" "$T/fakedocker"
  gso_fake_docker_into "$T"       # fausse CLI docker autonome, propre à CET arbre
  gso_fake_sudo_into "$T"         # faux sudo autonome, propre à CET arbre (become réel simulé, pas de privilège réel)
  cat > "$T/inventories/production/hosts.yml" <<YML
all:
  children:
    grav_servers:
      hosts:
        grav-alpha:
          ansible_connection: local
          ansible_host: 127.0.0.1
          ansible_become_exe: "$T/fakebin/sudo"
        grav-unreach:
          ansible_connection: ssh
          ansible_host: 127.0.0.1
          ansible_port: 1
          ansible_ssh_common_args: "-o ConnectTimeout=2 -o BatchMode=yes -o StrictHostKeyChecking=no"
          ansible_become_exe: "$T/fakebin/sudo"
YML
  cat > "$T/inventories/production/group_vars/all/grav_sites.yml" <<YML
grav_sites:
  grav-alpha:
    project_name: alpha
    image: reg.invalid/alpha
    version: "1.0.0"
    digest: ""
    container_name: gso-t19-alpha
    base_directory: $T/sites/grav-alpha
    bind_address: 127.0.0.1
    http_port: 18190
    state: started
    site_check_path: /
  grav-unreach:
    project_name: unreach
    image: reg.invalid/unreach
    version: "1.0.0"
    digest: ""
    container_name: gso-t19-unreach
    base_directory: $T/sites/grav-unreach
    bind_address: 127.0.0.1
    http_port: 18191
    state: started
    site_check_path: /
YML
  cat > "$T/inventories/production/group_vars/all/vault.yml" <<YML
vault_grav_sites:
  grav-alpha: {admin_user: alpha-adm, admin_password: SYNTH-T19-ADMIN-PW, admin_email: a@example.invalid}
  grav-unreach: {admin_user: u, admin_password: SYNTH-T19-OTHER-PW, admin_email: u@example.invalid}
vault_retired_grav_sites: {}
YML
  # état appliqué conforme
  cat > "$T/sites/grav-alpha/.deployed_state.yml" <<'YML'
image: reg.invalid/alpha
declared_version: "1.0.0"
digest: ""
effective_reference: reg.invalid/alpha:1.0.0
deployed_at: "2026-09-01T10:00:00Z"
YML
  # état réel conforme : running + healthy + port 18190
  printf '%s\n' '[{"Config":{"Image":"reg.invalid/alpha:1.0.0"},"State":{"Running":true,"Health":{"Status":"healthy"}},"NetworkSettings":{"Ports":{"18190/tcp":[{"HostIp":"127.0.0.1","HostPort":"18190"}]}}}]' \
    > "$T/fakedocker/gso-t19-alpha.json"
  echo "$T"
}

check() {  # <tree> <site> -> "<rc> <logfile>"
  local T="$1" site="$2" rc=0
  ( cd "$T" && GSO_TEST_DOCKER_BIN="$T/fakebin/docker" bash scripts/check-site.sh "$site" ) > "$T.log.$site" 2>&1 || rc=$?
  echo "$rc $T.log.$site"
}

# --- B1. état conforme -> IN_SYNC, code 0, trois niveaux affichés ---
T="$(mk_tree)"
read -r rc log < <(check "$T" grav-alpha)
[ "$rc" = 0 ] && pass "check-site grav-alpha conforme : code 0" || { sed 's/^/   | /' "$log" | tail -15; fail "conforme : code $rc"; }
grep -q 'IN_SYNC' "$log" && pass "verdict IN_SYNC affiché" || fail "verdict absent"
grep -qE 'désiré=reg.invalid/alpha:1.0.0 .*appliqué=reg.invalid/alpha:1.0.0 .*réel=reg.invalid/alpha:1.0.0' "$log" \
  && pass "les trois niveaux (désiré/appliqué/réel) sont distingués (GSO-REQ-118)" || fail "trois niveaux non distingués"
grep -qE 'SYNTH-T19-(ADMIN|OTHER)-PW' "$log" && fail "fuite d'une valeur secrète" || pass "aucune valeur secrète (vault) dans la sortie"

# --- B1b. preuves d'engagement réel de become (mission A.6) ---
[ -s "$T/fakebin/.sudo-calls.log" ] && pass "le faux sudo a été appelé" || fail "le faux sudo n'a pas été appelé"
grep -q '^user=root ' "$T/fakebin/.sudo-calls.log" \
  && pass "la tâche 'docker inspect' reste exécutée avec become (utilisateur cible root)" \
  || fail "become non engagé (utilisateur cible différent de root) : $(cat "$T/fakebin/.sudo-calls.log" 2>/dev/null)"
[ -s "$T/fakedocker/.calls.log" ] && pass "le faux Docker autonome a été appelé" || fail "le faux Docker autonome n'a pas été appelé"

# --- B2. non mutant : aucun fichier du rôle touché, aucune sous-commande docker mutante ---
before="$(stat -c '%Y %s' "$T/sites/grav-alpha/.deployed_state.yml")"
_ignore=$(check "$T" grav-alpha)
after="$(stat -c '%Y %s' "$T/sites/grav-alpha/.deployed_state.yml")"
[ "$before" = "$after" ] && pass ".deployed_state.yml inchangé (mtime+taille) — GSO-REQ-119" || fail ".deployed_state.yml modifié"
[ ! -e "$T/sites/grav-alpha/.deployed_version" ] && [ ! -e "$T/sites/grav-alpha/deployed_versions.log" ] \
  && pass "ni .deployed_version ni deployed_versions.log créés" || fail "fichier de traçabilité créé par le check"
[ ! -e "$T/roles/sepp67.grav_site/_calls.log" ] && pass "doublure du rôle jamais invoquée (aucun include_role — GSO-REQ-090)" || fail "le rôle a été invoqué"
grep -q 'FAKE-DOCKER-REFUS' "$T.log.grav-alpha" && fail "une sous-commande docker mutante a été tentée" || pass "aucune sous-commande docker mutante"

# --- B3. référence différente -> REFERENCE_DRIFT, code != 0 ---
T="$(mk_tree)"
sed -i 's#version: "1.0.0"#version: "2.5.0"#' "$T/inventories/production/group_vars/all/grav_sites.yml"
# le registre attend 2.5.0 mais grav-unreach garde 1.0.0 -> ne toucher que grav-alpha
sed -i '0,/version: "2.5.0"/! s#version: "2.5.0"#version: "1.0.0"#' "$T/inventories/production/group_vars/all/grav_sites.yml"
read -r rc log < <(check "$T" grav-alpha)
{ [ "$rc" != 0 ] && grep -q 'REFERENCE_DRIFT' "$log"; } && pass "référence différente -> REFERENCE_DRIFT, code $rc" || { sed 's/^/   | /' "$log"|tail -8; fail "REFERENCE_DRIFT attendu (rc=$rc)"; }

# --- B4. conteneur arrêté -> STOPPED ---
T="$(mk_tree)"
sed -i 's/"Running":true/"Running":false/;s/"Status":"healthy"/"Status":"none"/' "$T/fakedocker/gso-t19-alpha.json"
read -r rc log < <(check "$T" grav-alpha)
{ [ "$rc" != 0 ] && grep -q 'STOPPED' "$log"; } && pass "conteneur arrêté (désiré started) -> STOPPED" || { sed 's/^/   | /' "$log"|tail -8; fail "STOPPED attendu (rc=$rc)"; }

# --- B5. état appliqué illisible -> UNKNOWN ---
T="$(mk_tree)"
: > "$T/sites/grav-alpha/.deployed_state.yml"
read -r rc log < <(check "$T" grav-alpha)
{ [ "$rc" != 0 ] && grep -q 'UNKNOWN' "$log"; } && pass "état appliqué illisible -> UNKNOWN" || { sed 's/^/   | /' "$log"|tail -8; fail "UNKNOWN attendu (rc=$rc)"; }

# --- B6. docker indisponible -> UNKNOWN ---
T="$(mk_tree)"
touch "$T/fakedocker/.unavailable"   # marqueur local à l'arbre — lu par la doublure elle-même, jamais via l'environnement
rc=0; ( cd "$T" && GSO_TEST_DOCKER_BIN="$T/fakebin/docker" bash scripts/check-site.sh grav-alpha ) > "$T.log.dk" 2>&1 || rc=$?
{ [ "$rc" != 0 ] && grep -q 'UNKNOWN' "$T.log.dk"; } && pass "docker indisponible -> UNKNOWN" || { sed 's/^/   | /' "$T.log.dk"|tail -8; fail "UNKNOWN attendu (rc=$rc)"; }

# --- B6b. échec d'exécution du module (MODULE FAILURE) -> UNKNOWN, sans fuite ---
# Le faux sudo de cet arbre refuse délibérément l'élévation (marqueur
# .deny-become) : Ansible rapporte alors l'échec sous la forme
# "MODULE FAILURE" (msg) + module_stderr, jamais stdout/stderr normaux.
# C'est UN exemple CONCRET (become indisponible) produisant cette forme —
# pas la preuve que tout "MODULE FAILURE" est lié aux privilèges : Ansible
# rapporte la même forme pour tout échec qui empêche le module de
# s'exécuter (interpréteur absent, transfert du script échoué, etc.). Le
# verdict et la raison publiée restent donc volontairement génériques
# ("exécution du module impossible sur la cible", jamais "become" ni
# "privilège"). Avant la correction B, ce cas était classé NOT_DEPLOYED
# (faux : l'existence du conteneur est en réalité INCONNUE).
T="$(mk_tree)"
touch "$T/fakebin/.deny-become"
read -r rc log < <(check "$T" grav-alpha)
{ [ "$rc" != 0 ] && grep -q 'UNKNOWN' "$log"; } && pass "échec d'exécution du module (MODULE FAILURE) -> UNKNOWN" || { sed 's/^/   | /' "$log"|tail -10; fail "UNKNOWN attendu pour échec de module (rc=$rc)"; }
grep -qE 'elevation refusee|MODULE FAILURE|module_stderr' "$log" \
  && fail "contenu sensible (message du faux sudo / module_stderr / MODULE FAILURE) affiché dans le rapport" \
  || pass "aucun contenu de module_stderr/msg affiché (GSO-REQ-123)"

# --- B6c. docker inspect normal, conteneur réellement absent (aucun become en cause) -> NOT_DEPLOYED inchangé (mission B.7) ---
T="$(mk_tree)"
rm -f "$T/fakedocker/gso-t19-alpha.json"
read -r rc log < <(check "$T" grav-alpha)
{ [ "$rc" != 0 ] && grep -q 'NOT_DEPLOYED' "$log"; } && pass "conteneur normalement absent -> NOT_DEPLOYED (comportement inchangé)" || { sed 's/^/   | /' "$log"|tail -10; fail "NOT_DEPLOYED attendu pour absence normale (rc=$rc)"; }

# --- B7. VM simulée injoignable -> UNREACHABLE ---
T="$(mk_tree)"
read -r rc log < <(check "$T" grav-unreach)
{ [ "$rc" != 0 ] && grep -q 'UNREACHABLE' "$log"; } && pass "VM simulée injoignable -> UNREACHABLE" || { sed 's/^/   | /' "$log"|tail -8; fail "UNREACHABLE attendu (rc=$rc)"; }

# --- B8. .last_failure.log : présence signalée, contenu JAMAIS affiché ---
T="$(mk_tree)"
printf 'TRACE-SECRETE-DE-PANNE-XYZ\n' > "$T/sites/grav-alpha/.last_failure.log"
read -r rc log < <(check "$T" grav-alpha)
grep -q '.last_failure.log présent' "$log" && pass ".last_failure.log : présence signalée (GSO-REQ-123)" || fail ".last_failure.log non signalé"
grep -q 'TRACE-SECRETE-DE-PANNE-XYZ' "$log" && fail ".last_failure.log : contenu affiché" || pass ".last_failure.log : contenu jamais affiché"

# --- B9. codes de sortie stables (rejouer = même verdict, même code) ---
T="$(mk_tree)"
read -r rc1 _ < <(check "$T" grav-alpha)
read -r rc2 _ < <(check "$T" grav-alpha)
[ "$rc1" = 0 ] && [ "$rc2" = 0 ] && pass "code de sortie stable au rejeu (0, 0)" || fail "codes instables ($rc1, $rc2)"

# --- B10. fixtures inchangées ---
cur="$(cd "$REPO_ROOT" && git status --porcelain -- tests/fixtures/)"
[ -z "$cur" ] && pass "fixtures tests/fixtures/ inchangées" || fail "fixtures modifiées : $cur"

gso_assert_runtime_clean
finish
