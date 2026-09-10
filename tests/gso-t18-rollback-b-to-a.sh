#!/usr/bin/env bash
# GSO-T18 — Rollback B→A d'un seul site, explicitement déclaré, en conservant
# les chemins persistants (lot L7, phase P6).
#
# 100 % local, déterministe, DOUBLURE du rôle. Le rollback n'est PAS une
# action CLI ni une intention technique : c'est un usage déclaratif de
# `deploy-site.yml` (contrat §15.4, « suit le même chemin qu'une mise à
# jour »). Ce test prouve :
#   - séquence observée A -> B -> A (trois invocations de deploy-site.yml) ;
#   - à chaque passage, le rôle reçoit EXACTEMENT la référence déclarée et
#     committée (pas l'avant-dernière image, pas le dernier conteneur, pas un
#     tag flottant) ;
#   - le rollback vers A est une DÉCLARATION explicite dans grav_sites.yml,
#     committée — jamais une déduction ;
#   - un rollback vers le même digest mais une version humaine différente
#     reste explicite et distinct ;
#   - une nouvelle entrée de trace (journal synthétique append-only de la
#     doublure) est produite sans effacer ni réécrire les précédentes ;
#   - grav_base_directory et les quatre chemins persistants inchangés ;
#   - aucune restauration ni modification du contenu des volumes ;
#   - aucune opération destructive ; propagation des erreurs ; verrou par
#     site ; aucune modification automatique du registre.

TEST_ID="GSO-T18"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

tmp="$(gso_mktemp_dir t18)"
trap 'rm -rf "$tmp"' EXIT
gso_isolate_runtime "$tmp"
T="$tmp/tree"
l4_tmptree l3-prod-ok "$T"
gso_spy_role_into "$T"

cat > "$T/inventories/production/group_vars/all/vault.yml" <<'YML'
vault_grav_sites:
  grav-alpha: {admin_user: a, admin_password: SYNTH-T18-A-PW, admin_email: a@example.invalid}
  grav-beta:  {admin_user: b, admin_password: SYNTH-T18-B-PW, admin_email: b@example.invalid}
vault_retired_grav_sites: {}
YML

REG_REL="inventories/production/group_vars/all/grav_sites.yml"
REG="$T/$REG_REL"
DIG_A="sha256:$(printf 'a%.0s' $(seq 64))"
DIG_B="sha256:$(printf 'b%.0s' $(seq 64))"

write_registry() {  # <version> <digest>
  cat > "$REG" <<YML
grav_sites:
  grav-alpha:
    project_name: alpha
    image: reg.invalid/grav-alpha
    version: "$1"
    digest: "$2"
    container_name: gso-t18-alpha
    base_directory: /opt/grav-site/gso-t18-alpha
    bind_address: 192.0.2.81
    http_port: 8081
    state: started
  grav-beta:
    project_name: beta
    image: reg.invalid/beta
    version: "5.0.0"
    digest: ""
    container_name: gso-t18-beta
    base_directory: /opt/grav-site/gso-t18-beta
    bind_address: 192.0.2.82
    http_port: 8082
    state: started
YML
}

_gitT() { git -C "$T" -c user.email=t@t -c user.name=t "$@"; }

# --------------------------------------------------------------------------
# Diagnostic PREMIER échec, SANS retry ni temporisation : dump complet sur
# stderr puis échec net. Utilisé par commit_reg et le contrôle n°3.
# --------------------------------------------------------------------------
DEPLOY_RCS=""            # « label:rc » séparés par des espaces
_reg_step=0
_dump() {  # <contexte> <raison>
  {
    echo "================ GSO-T18 DIAG : $1 ================"
    echo "raison        : $2"
    echo "étape commit  : $_reg_step"
    echo "deploy rc     : ${DEPLOY_RCS:-<aucun>}"
    echo "-- git rev-parse HEAD / symbolic-ref --"
    git -C "$T" rev-parse HEAD 2>&1; git -C "$T" symbolic-ref HEAD 2>&1
    echo "-- git log --oneline --decorate -n 8 --"
    git -C "$T" log --oneline --decorate -n 8 2>&1
    echo "-- git status --short --"
    git -C "$T" status --short 2>&1
    echo "-- git diff --"
    git -C "$T" diff 2>&1
    echo "-- git diff --cached --"
    git -C "$T" diff --cached 2>&1
    echo "-- git reflog -8 --"
    git -C "$T" reflog -8 2>&1
    echo "-- registre déclaré sur disque ($REG_REL) --"
    sed 's/^/   | /' "$REG" 2>&1
    echo "-- registre dans l'index (git show :$REG_REL) --"
    git -C "$T" show ":$REG_REL" 2>&1 | sed 's/^/   | /'
    echo "-- registre dans HEAD (git show HEAD:$REG_REL) --"
    git -C "$T" show "HEAD:$REG_REL" 2>&1 | sed 's/^/   | /'
    echo "-- traces de la doublure --"
    for s in "$tmp"/spy.*; do
      [ -d "$s" ] || continue
      echo "   [$s/grav-alpha.json]"; sed 's/^/     /' "$s/grav-alpha.json" 2>/dev/null
      echo "   [$s/_calls.log]"; sed 's/^/     /' "$s/_calls.log" 2>/dev/null
    done
    echo "-- .git : verrous / gc / MERGE --"
    ls -la "$T/.git/" 2>&1 | grep -iE 'lock|gc|MERGE|packed-refs|HEAD' || true
    echo "-- git fsck --"
    { git -C "$T" fsck --no-progress --no-dangling 2>&1 || true; } | sed -n '1,10p'
    echo "================ FIN DIAG ================"
  } >&2
}

# commit_reg <message> <version_attendue> <digest_attendu>
# Committe la modification du registre et ÉCHOUE IMMÉDIATEMENT (dump) si :
#   (a) le changement attendu n'est pas dans l'index ;
#   (b) le contenu indexé ne correspond pas à la déclaration (version+digest) ;
#   (c) `git commit` ne crée pas EXACTEMENT un nouveau commit ;
#   (d) le nouveau HEAD reste égal à l'ancien ;
#   (e) le sujet OU le contenu du commit ne correspond pas à l'étape attendue.
# Aucun retry, aucune temporisation, aucune tolérance à l'absence du commit.
commit_reg() {
  local msg="$1" exp_ver="$2" exp_dig="$3"
  _reg_step=$((_reg_step + 1))
  local h0 n0 h1 n1 staged committed
  h0="$(git -C "$T" rev-parse HEAD)"
  n0="$(git -C "$T" rev-list --count HEAD)"

  _gitT add -A

  # (a) changement attendu dans l'index
  if git -C "$T" diff --cached --quiet -- "$REG_REL"; then
    _dump "commit_reg #$_reg_step ($msg)" "(a) aucun changement de $REG_REL dans l'index"
    fail "commit_reg (a) : $msg"; finish
  fi
  # (b) contenu indexé == déclaration
  # (here-string, PAS de pipeline `... | grep -q` : sous `set -o pipefail`,
  #  un `grep -q` qui sort tôt fait recevoir SIGPIPE au producteur -> le
  #  statut du pipeline devient 141 même quand grep A trouvé la ligne.)
  staged="$(git -C "$T" show ":$REG_REL" 2>/dev/null || true)"
  if ! grep -qF "version: \"$exp_ver\"" <<<"$staged" \
     || ! grep -qF "digest: \"$exp_dig\"" <<<"$staged"; then
    _dump "commit_reg #$_reg_step ($msg)" "(b) index != déclaré (attendu version=$exp_ver digest=$exp_dig)"
    fail "commit_reg (b) : $msg"; finish
  fi

  _gitT commit -qm "$msg"

  h1="$(git -C "$T" rev-parse HEAD)"
  n1="$(git -C "$T" rev-list --count HEAD)"

  # (c) exactement un nouveau commit
  if [ "$n1" != "$((n0 + 1))" ]; then
    _dump "commit_reg #$_reg_step ($msg)" "(c) nombre de commits $n0 -> $n1 (attendu $((n0 + 1)))"
    fail "commit_reg (c) : $msg"; finish
  fi
  # (d) HEAD a bougé
  if [ "$h1" = "$h0" ]; then
    _dump "commit_reg #$_reg_step ($msg)" "(d) HEAD inchangé ($h0)"
    fail "commit_reg (d) : $msg"; finish
  fi
  # (e) sujet + contenu du nouveau HEAD
  if [ "$(git -C "$T" log -1 --pretty=%s)" != "$msg" ]; then
    _dump "commit_reg #$_reg_step ($msg)" "(e) sujet HEAD « $(git -C "$T" log -1 --pretty=%s) » != « $msg »"
    fail "commit_reg (e-sujet) : $msg"; finish
  fi
  committed="$(git -C "$T" show "HEAD:$REG_REL" 2>/dev/null || true)"
  if ! grep -qF "version: \"$exp_ver\"" <<<"$committed" \
     || ! grep -qF "digest: \"$exp_dig\"" <<<"$committed"; then
    _dump "commit_reg #$_reg_step ($msg)" "(e) contenu committé != déclaré"
    fail "commit_reg (e-contenu) : $msg"; finish
  fi
  pass "commit_reg #$_reg_step : « $msg » committé (${h0:0:9} -> ${h1:0:9}, version=$exp_ver)"
}

seq_log="$tmp/sequence.log"    # journal synthétique append-only (orchestration)
: > "$seq_log"
deploy_step() {  # <spydir> <label> <logfile>
  local spy="$1" label="$2" log="$3" rc=0
  mkdir -p "$spy"
  ( cd "$T" && GSO_SPY_OUTPUT="$spy" bash scripts/deploy.sh grav-alpha ) > "$log" 2>&1 || rc=$?
  DEPLOY_RCS="$DEPLOY_RCS $label:$rc"
  if [ "$rc" != 0 ]; then
    sed 's/^/   | /' "$log" | tail -20
    _dump "deploy_step $label" "deploy.sh rc=$rc"
    fail "deploy.sh a échoué ($label, rc=$rc)"; finish
  fi
  # trace synthétique append-only : reconstruit la référence effective à la
  # manière du rôle (image@digest si digest, sinon image:version).
  python3 - "$spy/grav-alpha.json" "$label" >> "$seq_log" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); label = sys.argv[2]
img, ver, dig = d.get("grav_image", ""), d.get("grav_version", ""), d.get("grav_digest", "")
eff = f"{img}@{dig}" if dig else f"{img}:{ver}"
print(f"{label} {ver} {dig or '-'} {eff}")
PY
}

pyget() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$1" "$2"; }

spy1="$tmp/spy.1"; spy2="$tmp/spy.2"; spy3="$tmp/spy.3"; spy4="$tmp/spy.4"

git -C "$T" init -q
_gitT add -A >/dev/null
_gitT commit -qm "état initial"

# --- A : version 1.0.0 + digest A ---
write_registry "1.0.0" "$DIG_A"
commit_reg "déclarer grav-alpha 1.0.0 (A)" "1.0.0" "$DIG_A"
deploy_step "$spy1" A "$tmp/log.1"

# --- B : version 2.0.0 + digest B (mise à jour) ---
write_registry "2.0.0" "$DIG_B"
commit_reg "mettre à jour grav-alpha -> 2.0.0 (B)" "2.0.0" "$DIG_B"
deploy_step "$spy2" B "$tmp/log.2"

# --- ROLLBACK vers A : re-déclaration EXPLICITE de 1.0.0 + digest A ---
write_registry "1.0.0" "$DIG_A"
commit_reg "rollback grav-alpha 2.0.0 -> 1.0.0 (retour à A, référence saine connue)" "1.0.0" "$DIG_A"
deploy_step "$spy3" A "$tmp/log.3"

# --- 1. Séquence observée A -> B -> A ---
seq="$(awk '{print $1}' "$seq_log" | paste -sd'-' -)"
[ "$seq" = "A-B-A" ] && pass "séquence d'application observée : A -> B -> A" || fail "séquence inattendue : $seq"

# --- 2. Référence exacte à chaque passage (déclarée + committée) ---
ok=1
[ "$(pyget "$spy1/grav-alpha.json" grav_version)" = "1.0.0" ] && [ "$(pyget "$spy1/grav-alpha.json" grav_digest)" = "$DIG_A" ] || ok=0
[ "$(pyget "$spy2/grav-alpha.json" grav_version)" = "2.0.0" ] && [ "$(pyget "$spy2/grav-alpha.json" grav_digest)" = "$DIG_B" ] || ok=0
[ "$(pyget "$spy3/grav-alpha.json" grav_version)" = "1.0.0" ] && [ "$(pyget "$spy3/grav-alpha.json" grav_digest)" = "$DIG_A" ] || ok=0
[ "$ok" = 1 ] && pass "chaque passage transmet exactement la référence déclarée (A: 1.0.0/@a, B: 2.0.0/@b, rollback: 1.0.0/@a)" \
             || fail "une référence transmise ne correspond pas à la déclaration committée"

# --- 3. Le rollback est une déclaration Git explicite, pas une déduction ---
# commit_reg a DÉJÀ prouvé (checks a-e) que le commit du rollback a été créé,
# que HEAD a bougé et que son sujet est exact. Ce contrôle vérifie que ce
# commit est toujours dans l'historique atteignable.
#
# On CAPTURE d'abord la sortie de `git log` puis on cherche dans une
# here-string. Un `git log --pretty=%s | grep -qxF …` est PIÉGÉ sous
# `set -o pipefail` (common.sh) : `grep -q` sort dès la 1ʳᵉ ligne (le commit
# de rollback EST HEAD), `git log` reçoit SIGPIPE, sort en 141, et `pipefail`
# fait échouer le pipeline ALORS QUE grep a trouvé la ligne — d'où un faux
# « rollback non tracé » intermittent (plus fréquent sous charge, quand
# `git log` est lent à vider son tampon). Cause racine de l'aléa GSO-T18.
_t18_subjects="$(git -C "$T" log --pretty=%s)"
if grep -qxF "rollback grav-alpha 2.0.0 -> 1.0.0 (retour à A, référence saine connue)" <<<"$_t18_subjects"; then
  pass "le rollback est une re-déclaration explicite committée (GSO-REQ-112, procédure §15.4)"
else
  _dump "contrôle n°3" "le commit de rollback n'est pas dans git log --pretty=%s"
  fail "rollback non tracé dans l'historique Git"
fi
# le digest du rollback vient du registre committé, pas d'un historique Docker
grep -q "A 1.0.0 $DIG_A " "$seq_log" && pass "digest du rollback = celui déclaré au registre (jamais choisi dans l'historique Docker / un tag flottant)" \
  || fail "le digest du rollback ne vient pas de la déclaration"

# --- 4. Trace append-only : les entrées précédentes ne sont ni effacées ni réécrites ---
lines="$(grep -c . "$seq_log")"
[ "$lines" = 3 ] && [ -f "$spy1/grav-alpha.json" ] && [ -f "$spy2/grav-alpha.json" ] && [ -f "$spy3/grav-alpha.json" ] \
  && pass "trois traces d'application distinctes conservées (aucune entrée effacée ni réécrite)" \
  || fail "trace d'orchestration incomplète ($lines entrées)"
# les invocations de la doublure s'ajoutent (append), jamais ne se remplacent
calls="$(grep -c . "$spy3/_calls.log" 2>/dev/null || echo 0)"
[ "$calls" = 1 ] && pass "chaque passage = une invocation unique du rôle (GSO-REQ-087 conservé au rollback)" || fail "$calls invocations au 3ᵉ passage"

# --- 5. Rollback vers le MÊME digest mais une version humaine différente reste explicite ---
write_registry "1.0.1" "$DIG_A"     # même octets que A, version humaine corrigée
commit_reg "re-déclarer grav-alpha 1.0.1 @même-digest (correction de version humaine)" "1.0.1" "$DIG_A"
deploy_step "$spy4" A2 "$tmp/log.4"
if [ "$(pyget "$spy4/grav-alpha.json" grav_version)" = "1.0.1" ] \
   && [ "$(pyget "$spy4/grav-alpha.json" grav_digest)" = "$DIG_A" ]; then
  pass "version humaine 1.0.0 -> 1.0.1 à digest inchangé : transmise explicitement (version ET digest visibles séparément)"
else
  fail "changement de version humaine à digest constant non transmis explicitement"
fi

# --- 6. Chemins persistants inchangés sur toute la séquence ---
bds="$(for s in "$spy1" "$spy2" "$spy3" "$spy4"; do pyget "$s/grav-alpha.json" grav_base_directory; done | sort -u | grep -c .)"
cns="$(for s in "$spy1" "$spy2" "$spy3" "$spy4"; do pyget "$s/grav-alpha.json" grav_container_name; done | sort -u | grep -c .)"
[ "$bds" = 1 ] && [ "$cns" = 1 ] && pass "grav_base_directory et grav_container_name identiques sur A->B->A->A2 (chemins data/{pages,accounts,data,images} préservés)" \
  || fail "un chemin structurant a changé pendant la séquence de rollback"

# --- 7. Aucune restauration / modification de contenu ; aucune opération destructive ---
if grep -qiE 'down --volumes|volume rm|volume prune|rm -rf|rsync|restore|state: absent' "$tmp"/log.[1-4]; then
  fail "trace d'opération de restauration ou de destruction dans la sortie"
else
  pass "rollback : aucune restauration de contenu, aucune opération destructive (GSO-REQ-113)"
fi
# l'orchestrateur ne transmet aucun sous-chemin persistant ni drapeau de restauration
python3 - "$spy3/grav-alpha.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
bad = [k for k in d if k in ("grav_pages_directory", "grav_accounts_directory",
       "grav_data_directory", "grav_images_directory", "grav_secret_directory")
       or "restore" in k or "backup" in k]
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] && pass "aucun sous-chemin persistant ni drapeau de restauration transmis au rôle" || fail "l'orchestrateur transmet un chemin/drapeau de contenu"

# --- 8. Le rollback réutilise le chemin L4 (sélecteur, verrou, cible unique) ---
grep -qE 'selector : [0-9]+ contrôles OK' "$tmp/log.1" && grep -qE 'selector : [0-9]+ contrôles OK' "$tmp/log.3" \
  && pass "le rollback emprunte le sélecteur fermé L3 comme un deploy (même chemin)" || fail "le rollback contourne le sélecteur"
lock_dir="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/grav-sites-ops/locks"
( exec 9>"$lock_dir/grav-alpha.lock"; flock -n 9 ) \
  && pass "verrou par site libéré après le rollback (même verrou que deploy)" || fail "verrou resté tenu"

# --- 9. Aucune modification automatique du registre (capture, pas de pipeline) ---
_t18_status="$(git -C "$T" status --porcelain)"
if [ -n "$_t18_status" ]; then
  _dump "contrôle n°9" "le dépôt de test est modifié après les exécutions"
  fail "le registre (ou un fichier suivi) a été modifié automatiquement par une exécution : $_t18_status"
else
  pass "aucune modification automatique du registre : seule la main humaine committe (GSO-REQ-109/126)"
fi

# --- 10. Propagation d'erreur : une déclaration incohérente échoue proprement ---
write_registry "3.0.0" "sha256:tropcourt"
rc=0; ( cd "$T" && GSO_SPY_OUTPUT="$tmp/spy.bad" bash scripts/deploy.sh grav-alpha ) > "$tmp/log.bad" 2>&1 || rc=$?
_gitT checkout -q -- "$REG_REL"
{ [ "$rc" != 0 ] && [ ! -f "$tmp/spy.bad/_calls.log" ]; } \
  && pass "déclaration incohérente : échec propagé (rc=$rc), rôle non invoqué, aucun enchaînement automatique" \
  || fail "erreur mal propagée sur déclaration incohérente (rc=$rc)"

# --- 11. Isolation : grav-beta jamais touché ---
if ! ls "$tmp"/spy.*/grav-beta.json >/dev/null 2>&1; then
  pass "le site non ciblé (grav-beta) n'est jamais invoqué pendant la séquence"
else
  fail "capture croisée du site non ciblé"
fi

# --- 12. Pas de fuite de secret (toutes les sorties, y compris le chemin d'erreur) ---
grep -qE 'SYNTH-T18-[AB]-PW' "$tmp"/log.1 "$tmp"/log.2 "$tmp"/log.3 "$tmp"/log.4 "$tmp"/log.bad \
  && fail "fuite d'un secret" || pass "aucune valeur secrète dans les sorties"

gso_assert_runtime_clean
finish
