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

REG="$T/inventories/production/group_vars/all/grav_sites.yml"
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

git -C "$T" init -q
git -C "$T" -c user.email=t@t -c user.name=t add -A >/dev/null
git -C "$T" -c user.email=t@t -c user.name=t commit -qm "état initial"

seq_log="$tmp/sequence.log"    # journal synthétique append-only (orchestration)
: > "$seq_log"
deploy_step() {  # <spydir> <label> <logfile>
  local spy="$1" label="$2" log="$3" rc=0
  mkdir -p "$spy"
  ( cd "$T" && GSO_SPY_OUTPUT="$spy" bash scripts/deploy.sh grav-alpha ) > "$log" 2>&1 || rc=$?
  if [ "$rc" != 0 ]; then sed 's/^/   | /' "$log" | tail -12; fail "deploy.sh a échoué ($label, rc=$rc)"; finish; fi
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

# --- A : version 1.0.0 + digest A ---
write_registry "1.0.0" "$DIG_A"
git -C "$T" -c user.email=t@t -c user.name=t commit -qam "déclarer grav-alpha 1.0.0 (A)"
deploy_step "$spy1" A "$tmp/log.1"

# --- B : version 2.0.0 + digest B (mise à jour) ---
write_registry "2.0.0" "$DIG_B"
git -C "$T" -c user.email=t@t -c user.name=t commit -qam "mettre à jour grav-alpha -> 2.0.0 (B)"
deploy_step "$spy2" B "$tmp/log.2"

# --- ROLLBACK vers A : re-déclaration EXPLICITE de 1.0.0 + digest A ---
write_registry "1.0.0" "$DIG_A"
git -C "$T" -c user.email=t@t -c user.name=t commit -qam "rollback grav-alpha 2.0.0 -> 1.0.0 (retour à A, référence saine connue)"
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
if git -C "$T" log --oneline | grep -qi 'rollback grav-alpha'; then
  pass "le rollback est une re-déclaration explicite committée (GSO-REQ-112, procédure §15.4)"
else
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
git -C "$T" -c user.email=t@t -c user.name=t commit -qam "re-déclarer grav-alpha 1.0.1 @même-digest (correction de version humaine)"
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
if grep -qiE 'down --volumes|volume rm|volume prune|rm -rf|rsync|restore|state: absent' "$tmp"/log.*; then
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

# --- 9. Aucune modification automatique du registre ---
if git -C "$T" status --porcelain | grep -q .; then
  fail "le registre (ou un fichier suivi) a été modifié automatiquement par une exécution"
else
  pass "aucune modification automatique du registre : seule la main humaine committe (GSO-REQ-109/126)"
fi

# --- 10. Propagation d'erreur : une déclaration incohérente échoue proprement ---
write_registry "3.0.0" "sha256:tropcourt"
rc=0; ( cd "$T" && GSO_SPY_OUTPUT="$tmp/spy.bad" bash scripts/deploy.sh grav-alpha ) >/tmp/o 2>&1 || rc=$?
git -C "$T" -c user.email=t@t -c user.name=t checkout -q -- "$REG"
{ [ "$rc" != 0 ] && [ ! -f "$tmp/spy.bad/_calls.log" ]; } \
  && pass "déclaration incohérente : échec propagé (rc=$rc), rôle non invoqué, aucun enchaînement automatique" \
  || fail "erreur mal propagée sur déclaration incohérente (rc=$rc)"

# --- 11. Isolation : grav-beta jamais touché ---
if ! ls "$tmp"/spy.*/grav-beta.json >/dev/null 2>&1; then
  pass "le site non ciblé (grav-beta) n'est jamais invoqué pendant la séquence"
else
  fail "capture croisée du site non ciblé"
fi

# --- 12. Pas de fuite de secret ---
grep -qE 'SYNTH-T18-[AB]-PW' "$tmp"/log.* && fail "fuite d'un secret" || pass "aucune valeur secrète dans les sorties"

gso_assert_runtime_clean
finish
