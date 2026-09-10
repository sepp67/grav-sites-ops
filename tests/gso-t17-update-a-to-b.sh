#!/usr/bin/env bash
# GSO-T17 — Mise à jour A→B d'un seul site, en conservant les chemins
# persistants (lot L7, phase P6).
#
# 100 % local, déterministe, DOUBLURE du rôle : aucun conteneur, aucune
# connexion. La mise à jour n'est PAS une intention technique : c'est un
# usage déclaratif de `deploy-site.yml` (contrat §13.1, §15.1). Ce test
# prouve donc, sur le VRAI chemin `deploy` :
#   - déclaration A puis déclaration B dans grav_sites.yml (committées) ;
#   - application de B par deploy-site.yml -> le rôle reçoit EXACTEMENT
#     l'image / la version / le digest de B ;
#   - aucune valeur héritée de A dans l'invocation B ;
#   - digest transmis tel quel, jamais de référence hybride reconstruite
#     par l'orchestrateur (GSO-REQ-110) ;
#   - grav_base_directory et les quatre chemins persistants
#     (data/pages, data/accounts, data/data, data/images) inchangés ;
#   - aucune surcharge CLI possible (--version / --digest / -e ...) ;
#   - aucune opération destructive ;
#   - le site non ciblé n'est pas touché (isolation).

TEST_ID="GSO-T17"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

tmp="$(gso_mktemp_dir t17)"
trap 'rm -rf "$tmp"' EXIT
gso_isolate_runtime "$tmp"
T="$tmp/tree"
l4_tmptree l3-prod-ok "$T"
gso_spy_role_into "$T"

cat > "$T/inventories/production/group_vars/all/vault.yml" <<'YML'
vault_grav_sites:
  grav-alpha: {admin_user: a, admin_password: SYNTH-T17-A-PW, admin_email: a@example.invalid}
  grav-beta:  {admin_user: b, admin_password: SYNTH-T17-B-PW, admin_email: b@example.invalid}
vault_retired_grav_sites: {}
YML

REG_REL="inventories/production/group_vars/all/grav_sites.yml"
REG="$T/$REG_REL"

# Registre d'un site à une référence donnée. base_directory / container_name
# NE changent JAMAIS entre A et B : seules l'image/version/digest bougent.
write_registry() {  # <image> <version> <digest>
  cat > "$REG" <<YML
grav_sites:
  grav-alpha:
    project_name: alpha
    image: $1
    version: "$2"
    digest: "$3"
    container_name: gso-t17-alpha
    base_directory: /opt/grav-site/gso-t17-alpha
    bind_address: 192.0.2.71
    http_port: 8071
    state: started
  grav-beta:
    project_name: beta
    image: reg.invalid/beta
    version: "9.9.9"
    digest: ""
    container_name: gso-t17-beta
    base_directory: /opt/grav-site/gso-t17-beta
    bind_address: 192.0.2.72
    http_port: 8072
    state: started
YML
}

# Dépôt Git jetable dans l'arbre de test : la décision A puis B est committée,
# ce qui rend la mise à jour traçable (GSO-REQ-109/112, procédure §15.1).
git -C "$T" init -q
git -C "$T" -c user.email=t@t -c user.name=t add -A >/dev/null
git -C "$T" -c user.email=t@t -c user.name=t commit -qm "état initial"

_gitT() { git -C "$T" -c user.email=t@t -c user.name=t "$@"; }
DEPLOY_RCS=""
_reg_step=0
_dump() {  # <contexte> <raison>
  {
    echo "================ GSO-T17 DIAG : $1 ================"
    echo "raison : $2 (étape commit $_reg_step ; deploy rc :${DEPLOY_RCS:- <aucun>})"
    echo "-- HEAD --"; git -C "$T" rev-parse HEAD 2>&1; git -C "$T" symbolic-ref HEAD 2>&1
    echo "-- git log --oneline --decorate -n 8 --"; git -C "$T" log --oneline --decorate -n 8 2>&1
    echo "-- git status --short --"; git -C "$T" status --short 2>&1
    echo "-- git diff --"; git -C "$T" diff 2>&1
    echo "-- git diff --cached --"; git -C "$T" diff --cached 2>&1
    echo "-- git reflog -8 --"; git -C "$T" reflog -8 2>&1
    echo "-- registre sur disque --"; sed 's/^/   | /' "$REG" 2>&1
    echo "-- registre dans HEAD --"; git -C "$T" show "HEAD:$REG_REL" 2>&1 | sed 's/^/   | /'
    echo "-- traces doublure --"
    for s in "$tmp"/spy.*; do [ -d "$s" ] || continue
      echo "   [$s]"; sed 's/^/     /' "$s/grav-alpha.json" 2>/dev/null; sed 's/^/     /' "$s/_calls.log" 2>/dev/null
    done
    echo "================ FIN DIAG ================"
  } >&2
}

# commit_reg <message> <version_attendue> <digest_attendu>
# ÉCHOUE IMMÉDIATEMENT (dump) si : (a) le changement attendu n'est pas dans
# l'index ; (b) le contenu indexé != déclaration ; (c) `git commit` ne crée
# pas EXACTEMENT un commit ; (d) HEAD inchangé ; (e) sujet/contenu du nouveau
# HEAD != étape attendue. Aucun retry, aucune temporisation.
# Les vérifications utilisent des HERE-STRINGS, jamais `... | grep -q` : sous
# `set -o pipefail`, un `grep -q` qui sort tôt fait échouer le pipeline
# (SIGPIPE 141 du producteur) ALORS que la ligne a été trouvée.
commit_reg() {
  local msg="$1" exp_ver="$2" exp_dig="$3"
  _reg_step=$((_reg_step + 1))
  local h0 n0 h1 n1 staged committed
  h0="$(git -C "$T" rev-parse HEAD)"; n0="$(git -C "$T" rev-list --count HEAD)"
  _gitT add -A
  if git -C "$T" diff --cached --quiet -- "$REG_REL"; then
    _dump "commit_reg #$_reg_step ($msg)" "(a) aucun changement de $REG_REL dans l'index"
    fail "commit_reg (a) : $msg"; finish
  fi
  staged="$(git -C "$T" show ":$REG_REL" 2>/dev/null || true)"
  if ! grep -qF "version: \"$exp_ver\"" <<<"$staged" || ! grep -qF "digest: \"$exp_dig\"" <<<"$staged"; then
    _dump "commit_reg #$_reg_step ($msg)" "(b) index != déclaré (version=$exp_ver digest=$exp_dig)"
    fail "commit_reg (b) : $msg"; finish
  fi
  _gitT commit -qm "$msg"
  h1="$(git -C "$T" rev-parse HEAD)"; n1="$(git -C "$T" rev-list --count HEAD)"
  if [ "$n1" != "$((n0 + 1))" ]; then
    _dump "commit_reg #$_reg_step ($msg)" "(c) commits $n0 -> $n1 (attendu +1)"; fail "commit_reg (c) : $msg"; finish
  fi
  if [ "$h1" = "$h0" ]; then
    _dump "commit_reg #$_reg_step ($msg)" "(d) HEAD inchangé"; fail "commit_reg (d) : $msg"; finish
  fi
  if [ "$(git -C "$T" log -1 --pretty=%s)" != "$msg" ]; then
    _dump "commit_reg #$_reg_step ($msg)" "(e) sujet HEAD != « $msg »"; fail "commit_reg (e-sujet) : $msg"; finish
  fi
  committed="$(git -C "$T" show "HEAD:$REG_REL" 2>/dev/null || true)"
  if ! grep -qF "version: \"$exp_ver\"" <<<"$committed" || ! grep -qF "digest: \"$exp_dig\"" <<<"$committed"; then
    _dump "commit_reg #$_reg_step ($msg)" "(e) contenu committé != déclaré"; fail "commit_reg (e-contenu) : $msg"; finish
  fi
  pass "commit_reg #$_reg_step : « $msg » committé (${h0:0:9} -> ${h1:0:9}, version=$exp_ver)"
}

deploy_step() {  # <spydir> <label> <logfile> ; échoue le test si deploy.sh échoue
  local spy="$1" label="$2" log="$3" rc=0
  mkdir -p "$spy"
  ( cd "$T" && GSO_SPY_OUTPUT="$spy" bash scripts/deploy.sh grav-alpha ) > "$log" 2>&1 || rc=$?
  DEPLOY_RCS="$DEPLOY_RCS $label:$rc"
  if [ "$rc" != 0 ]; then
    sed 's/^/   | /' "$log" | tail -20
    _dump "deploy_step $label" "deploy.sh rc=$rc"
    fail "deploy.sh a échoué pour la déclaration $label (rc=$rc)"
    finish
  fi
}

IMG_A="reg.invalid/grav-alpha"
IMG_B="reg.invalid/grav-alpha"
DIG_B="sha256:$(printf 'b%.0s' $(seq 64))"      # sha256 valide (64 hex)

# --- Déclaration A : version 1.0.0, sans digest ---
spyA="$tmp/spy.A"; spyB="$tmp/spy.B"
write_registry "$IMG_A" "1.0.0" ""
commit_reg "déclarer grav-alpha 1.0.0 (A)" "1.0.0" ""
deploy_step "$spyA" A "$tmp/log.A"

# --- Déclaration B : version 1.1.0 + digest, committée ---
write_registry "$IMG_B" "1.1.0" "$DIG_B"
commit_reg "mettre à jour grav-alpha 1.0.0 -> 1.1.0 @${DIG_B:0:14} (B)" "1.1.0" "$DIG_B"
deploy_step "$spyB" B "$tmp/log.B"

pyget() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get(sys.argv[2],""))' "$1" "$2"; }

# --- 1. B appliqué : image / version / digest EXACTS de la déclaration B ---
okB=1
[ "$(pyget "$spyB/grav-alpha.json" grav_image)"   = "$IMG_B"  ] || { okB=0; echo "   image B: $(pyget "$spyB/grav-alpha.json" grav_image)"; }
[ "$(pyget "$spyB/grav-alpha.json" grav_version)" = "1.1.0"   ] || { okB=0; echo "   version B: $(pyget "$spyB/grav-alpha.json" grav_version)"; }
[ "$(pyget "$spyB/grav-alpha.json" grav_digest)"  = "$DIG_B"  ] || { okB=0; echo "   digest B: $(pyget "$spyB/grav-alpha.json" grav_digest)"; }
[ "$okB" = 1 ] && pass "mise à jour : le rôle reçoit exactement l'image/version/digest de la déclaration B" \
               || fail "mise à jour : référence B transmise incorrecte"

# --- 2. Aucune valeur héritée de A dans l'invocation B ---
if [ "$(pyget "$spyB/grav-alpha.json" grav_version)" != "1.0.0" ] \
   && ! grep -q '1\.0\.0' "$spyB/grav-alpha.json"; then
  pass "aucune valeur héritée de la déclaration A dans l'invocation B"
else
  fail "une valeur de A subsiste dans l'invocation B"
fi

# --- 3. Digest transmis tel quel, jamais de référence hybride (GSO-REQ-110) ---
python3 - "$spyB/grav-alpha.json" "$DIG_B" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); dig = sys.argv[2]
if d.get("grav_digest") != dig:
    print("      FAIL grav_digest non transmis tel quel :", d.get("grav_digest")); sys.exit(1)
# aucune variable grav_* de type interface ne doit combiner image, version ET
# digest (référence hybride que seul le rôle a le droit de construire).
iface = {k: v for k, v in d.items() if isinstance(v, str) and k not in ("grav_digest",)}
hybrid = [f"{k}={v}" for k, v in iface.items()
          if "@sha256:" in v or (v.count(":") >= 1 and "@" in v)]
if hybrid:
    print("      FAIL référence hybride reconstruite par l'orchestrateur :", hybrid); sys.exit(1)
if d.get("grav_image") != "reg.invalid/grav-alpha" or d.get("grav_version") != "1.1.0":
    print("      FAIL image/version non transmis séparément"); sys.exit(1)
print("      OK   image, version et digest transmis séparément ; aucune référence hybride")
PY
[ $? -eq 0 ] && pass "digest transmis sans reconstruction hybride ; image/version/digest séparés (GSO-REQ-110)" \
             || fail "l'orchestrateur a reconstruit une référence hybride"

# --- 4. grav_base_directory ET les quatre chemins persistants inchangés A->B ---
bdA="$(pyget "$spyA/grav-alpha.json" grav_base_directory)"
bdB="$(pyget "$spyB/grav-alpha.json" grav_base_directory)"
cnA="$(pyget "$spyA/grav-alpha.json" grav_container_name)"
cnB="$(pyget "$spyB/grav-alpha.json" grav_container_name)"
if [ "$bdA" = "$bdB" ] && [ -n "$bdB" ] && [ "$cnA" = "$cnB" ]; then
  pass "grav_base_directory et grav_container_name inchangés A->B ($bdB) — chemins data/{pages,accounts,data,images} préservés"
else
  fail "un chemin structurant a changé pendant la mise à jour (bd:$bdA->$bdB cn:$cnA->$cnB)"
fi
# l'orchestrateur ne transmet AUCUN override de sous-chemin persistant
python3 - "$spyB/grav-alpha.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
over = [k for k in d if k in (
    "grav_pages_directory", "grav_accounts_directory",
    "grav_data_directory", "grav_images_directory", "grav_secret_directory")]
sys.exit(1 if over else 0)
PY
[ $? -eq 0 ] && pass "aucun sous-chemin persistant surchargé par l'orchestrateur (défauts du rôle conservés)" \
             || fail "l'orchestrateur surcharge un sous-chemin persistant"

# --- 5. Seule la dimension image bouge : les variables STRUCTURANTES que
#        l'orchestrateur transmet au rôle sont identiques A->B ---
python3 - "$spyA/grav-alpha.json" "$spyB/grav-alpha.json" <<'PY'
import json, sys
a = json.load(open(sys.argv[1])); b = json.load(open(sys.argv[2]))
# variables grav_* RÉELLEMENT transmises comme interface du rôle (on ignore
# l'écho du registre `grav_sites` capté par la doublure).
structuring = ["grav_container_name", "grav_base_directory", "grav_bind_address",
               "grav_http_port", "grav_state", "grav_force_pull",
               "grav_manage_docker", "grav_site_check_path", "grav_extra_environment"]
diff = [k for k in structuring if a.get(k) != b.get(k)]
if diff:
    print("      FAIL variable structurante modifiée par la mise à jour :", diff); sys.exit(1)
if a.get("grav_image") == b.get("grav_image") and a.get("grav_version") == b.get("grav_version") \
   and a.get("grav_digest") == b.get("grav_digest"):
    print("      FAIL la dimension image n'a pas changé (test invalide)"); sys.exit(1)
print("      OK   toutes les variables structurantes identiques ; seule l'image/version/digest diffère")
sys.exit(0)
PY
[ $? -eq 0 ] && pass "seule la dimension image change A->B ; base_directory / container_name / bind / port / state inchangés (GSO-REQ-076 versant mise à jour)" \
             || fail "la mise à jour a modifié une variable structurante"

# --- 6. Aucune surcharge CLI de version/digest/image acceptée ---
for extra in "-e grav_version=2.0.0" "--extra-vars" "grav-alpha -e digest=x"; do
  # shellcheck disable=SC2086
  if ( cd "$T" && bash scripts/deploy.sh grav-alpha $extra ) >/dev/null 2>&1; then
    fail "deploy.sh a accepté une surcharge « $extra »"
  else
    pass "deploy.sh refuse la surcharge « $extra »"
  fi
done

# --- 7. Aucune opération destructive pendant la mise à jour ---
if grep -qiE 'down --volumes|volume rm|volume prune|rm -rf|state: absent' "$tmp"/log.*; then
  fail "trace d'opération destructive dans la sortie de mise à jour"
else
  pass "mise à jour : aucune opération destructive"
fi

# --- 8. Isolation : grav-beta jamais touché ---
if [ ! -f "$spyA/grav-beta.json" ] && [ ! -f "$spyB/grav-beta.json" ]; then
  pass "le site non ciblé (grav-beta) n'est jamais invoqué"
else
  fail "capture croisée du site non ciblé"
fi

# --- 9. La décision A puis B est tracée dans l'historique Git (procédure §15.1) ---
# CAPTURE puis here-string : `git log | grep -q` est piégé sous `set -o
# pipefail` (SIGPIPE 141 du producteur quand grep -q sort tôt) — cf. GSO-T18.
_t17_log="$(git -C "$T" log --oneline)"
if grep -q 'mettre à jour grav-alpha 1.0.0 -> 1.1.0' <<<"$_t17_log"; then
  pass "la mise à jour est une déclaration committée, visible dans l'historique Git"
else
  _dump "contrôle n°9" "la mise à jour n'est pas visible dans git log --oneline"
  fail "décision de mise à jour non tracée"
fi

# --- 10. Pas de fuite de secret ---
grep -qE 'SYNTH-T17-[AB]-PW' "$tmp"/log.* && fail "fuite d'un secret" || pass "aucune valeur secrète dans les sorties"

gso_assert_runtime_clean
finish
