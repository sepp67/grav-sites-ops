#!/usr/bin/env bash
# GSO-T22 — Registres actif et retiré strictement disjoints, y compris après
# réactivation (lot L8).
#
# 100 % local, déterministe, sans Docker / réseau / connexion. Prouve
# (contrat §7.7, §21.8-21.9 ; GSO-REQ-052, GSO-REQ-073, GSO-REQ-180,
# GSO-REQ-181) :
#   - état cohérent (actif / retiré / réactivé) validé ;
#   - disjonction stricte grav_sites ∩ retired_grav_sites = ∅, sans exception ;
#   - disjonction vault : un site actif jamais dans vault_retired_grav_sites,
#     un site retiré jamais dans vault_grav_sites ;
#   - transformation de réactivation (avant -> après) : fiche retirée du
#     registre retiré, hôte replacé dans l'actif, événement daté AJOUTÉ à
#     reactivated-sites.yml, secrets déplacés vers vault_grav_sites ;
#   - AUCUNE clé réactivée ne subsiste dans retired_grav_sites (GSO-REQ-181) ;
#   - historique de réactivation APPEND-ONLY : une 2e réactivation ajoute un
#     2e événement sans effacer ni réécrire le 1er ;
#   - rejets : clé active+retirée, secret mal placé, racine/champ inconnu,
#     date/statut invalide, historique réécrit, clé « réactivée » restée
#     retirée avec une date antérieure ;
#   - le validateur est strictement en lecture seule ; aucun résidu.

TEST_ID="GSO-T22"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

tmp="$(gso_mktemp_dir t22)"
trap 'rm -rf "$tmp"' EXIT
gso_isolate_runtime "$tmp"

LC="$REPO_ROOT/scripts/lib/gso_lifecycle.py"
FIX="$REPO_ROOT/tests/fixtures/l8-lifecycle-ok"
REG="$FIX/inventories/production/group_vars/all/grav_sites.yml"

# Le vault de fixture est git-ignoré (**/vault.yml) : synthétisé dans $tmp.
# Marqueurs synthétiques uniquement, jamais un secret réel. Cohérent avec la
# fixture suivie : actifs grav-alpha/grav-delta, retirés grav-gamma/grav-omega.
VAULT="$tmp/vault.yml"
cat > "$VAULT" <<'YML'
vault_grav_sites:
  grav-alpha: {admin_user: alpha-admin, admin_password: SYNTH-L8T22-ALPHA, admin_email: alpha@example.invalid}
  grav-delta: {admin_user: delta-admin, admin_password: SYNTH-L8T22-DELTA, admin_email: delta@example.invalid}
vault_retired_grav_sites:
  grav-gamma: {admin_user: gamma-admin, admin_password: SYNTH-L8T22-GAMMA, admin_email: gamma@example.invalid}
  grav-omega: {admin_user: omega-admin, admin_password: SYNTH-L8T22-OMEGA, admin_email: omega@example.invalid}
YML

lc() {  # <label> <ok|ko> <args...>
  local label="$1" want="$2"; shift 2
  local rc=0
  python3 "$LC" "$@" > "$tmp/o" 2>&1 || rc=$?
  if [ "$want" = ok ]; then
    [ "$rc" = 0 ] && pass "$label -> OK" || { sed 's/^/   | /' "$tmp/o" | grep FAIL; fail "$label : attendu OK (rc=$rc)"; }
  else
    [ "$rc" != 0 ] && pass "$label -> rejeté (rc=$rc)" || fail "$label : accepté à tort"
  fi
}

# --------------------------------------------------------------------------
# 1. État cohérent : la fixture de référence valide
# --------------------------------------------------------------------------
lc "état actif / retiré / réactivé cohérent" ok \
  --retired "$FIX/registry/retired-sites.yml" --reactivated "$FIX/registry/reactivated-sites.yml" \
  --registry "$REG" --vault "$VAULT"

# grav-delta : réactivé, actif, absent de retired_grav_sites
python3 -c '
import yaml,sys
ret = yaml.safe_load(open(sys.argv[1]))["retired_grav_sites"]
act = yaml.safe_load(open(sys.argv[2]))["grav_sites"]
rea = yaml.safe_load(open(sys.argv[3]))["reactivated_sites"]
assert "grav-delta" in rea and "grav-delta" in act and "grav-delta" not in ret
' "$FIX/registry/retired-sites.yml" "$REG" "$FIX/registry/reactivated-sites.yml" \
  && pass "GSO-REQ-181 : clé réactivée (grav-delta) active et ABSENTE de retired_grav_sites" \
  || fail "GSO-REQ-181 : clé réactivée encore retirée"

# --------------------------------------------------------------------------
# 2. Transformation de réactivation : avant -> après (grav-gamma)
# --------------------------------------------------------------------------
A="$tmp/after-react"; mkdir -p "$A/registry" "$A/gv"
# retired APRÈS : grav-gamma retiré de retired-sites.yml
python3 - "$FIX/registry/retired-sites.yml" "$A/registry/retired-sites.yml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
d["retired_grav_sites"].pop("grav-gamma")
yaml.safe_dump(d, open(sys.argv[2], "w"), sort_keys=False)
PY
# reactivated APRÈS : événement daté AJOUTÉ (grav-gamma n'avait pas d'historique)
python3 - "$FIX/registry/reactivated-sites.yml" "$A/registry/reactivated-sites.yml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
d["reactivated_sites"]["grav-gamma"] = [{
    "reactivated_at": "2026-09-08",
    "project_name": "fixture-gamma",
    "former_inventory_host": "grav-gamma",
    "previous_retirement": {"retired_at": "2026-07-15", "reason": "Projet mis de côté (fixture)"},
}]
yaml.safe_dump(d, open(sys.argv[2], "w"), sort_keys=False)
PY
# grav_sites APRÈS : grav-gamma replacé dans l'actif
python3 - "$REG" "$A/gv/grav_sites.yml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
d["grav_sites"]["grav-gamma"] = {
    "project_name": "fixture-gamma", "image": "registry.example.invalid/fixture/grav-gamma",
    "version": "0.9.0", "digest": "", "container_name": "fixture-gamma",
    "base_directory": "/opt/fixture-gamma", "bind_address": "192.0.2.32",
    "http_port": 8082, "state": "started",
}
yaml.safe_dump(d, open(sys.argv[2], "w"), sort_keys=False)
PY
# vault APRÈS : secrets de grav-gamma déplacés vers vault_grav_sites
python3 - "$VAULT" "$A/gv/vault.yml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
d["vault_grav_sites"]["grav-gamma"] = d["vault_retired_grav_sites"].pop("grav-gamma")
yaml.safe_dump(d, open(sys.argv[2], "w"), sort_keys=False)
PY

lc "après-réactivation cohérent (grav-gamma)" ok \
  --retired "$A/registry/retired-sites.yml" --reactivated "$A/registry/reactivated-sites.yml" \
  --registry "$A/gv/grav_sites.yml" --vault "$A/gv/vault.yml"

# l'événement précédent (grav-delta) est CONSERVÉ à l'identique
python3 -c '
import yaml,sys
b = yaml.safe_load(open(sys.argv[1]))["reactivated_sites"]["grav-delta"]
a = yaml.safe_load(open(sys.argv[2]))["reactivated_sites"]["grav-delta"]
assert a == b, (b, a)
' "$FIX/registry/reactivated-sites.yml" "$A/registry/reactivated-sites.yml" \
  && pass "append-only : l'historique de grav-delta est conservé à l'identique" \
  || fail "append-only : historique préexistant modifié"

python3 -c '
import yaml,sys
ret = yaml.safe_load(open(sys.argv[1]))["retired_grav_sites"]
assert "grav-gamma" not in ret, ret
' "$A/registry/retired-sites.yml" \
  && pass "GSO-REQ-181 : après réactivation, grav-gamma ne subsiste pas dans retired_grav_sites" \
  || fail "GSO-REQ-181 : clé réactivée encore présente dans retired_grav_sites"

# --------------------------------------------------------------------------
# 3. Seconde réactivation : 2e événement AJOUTÉ, 1er conservé
# --------------------------------------------------------------------------
python3 - "$A/registry/reactivated-sites.yml" "$tmp/twice.yml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
d["reactivated_sites"]["grav-gamma"].append({
    "reactivated_at": "2026-11-01",
    "project_name": "fixture-gamma",
    "former_inventory_host": "grav-gamma",
    "previous_retirement": {"retired_at": "2026-10-01", "reason": "2e mise de côté (fixture)"},
})
yaml.safe_dump(d, open(sys.argv[2], "w"), sort_keys=False)
PY
lc "historique append-only à deux événements (grav-gamma)" ok \
  --retired "$A/registry/retired-sites.yml" --reactivated "$tmp/twice.yml" \
  --registry "$A/gv/grav_sites.yml" --vault "$A/gv/vault.yml"
python3 -c 'import yaml,sys; assert len(yaml.safe_load(open(sys.argv[1]))["reactivated_sites"]["grav-gamma"])==2' "$tmp/twice.yml" \
  && pass "deux événements de réactivation conservés (aucune perte)" || fail "événement perdu"

# --------------------------------------------------------------------------
# 4. Rejets — incohérences significatives
# --------------------------------------------------------------------------
# 4a. clé simultanément active et retirée
python3 - "$REG" "$tmp/collide.yml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
d["grav_sites"]["grav-gamma"] = {"project_name":"x","image":"r/x","version":"1","digest":"",
    "container_name":"x","base_directory":"/opt/x","bind_address":"192.0.2.40","http_port":8090}
yaml.safe_dump(d, open(sys.argv[2], "w"), sort_keys=False)
PY
lc "clé simultanément active et retirée (GSO-REQ-052)" ko \
  --retired "$FIX/registry/retired-sites.yml" --reactivated "$FIX/registry/reactivated-sites.yml" \
  --registry "$tmp/collide.yml" --vault "$VAULT"

# 4b. site actif dans vault_retired_grav_sites
python3 - "$VAULT" "$tmp/vault-leak.yml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
d["vault_retired_grav_sites"]["grav-alpha"] = {"admin_user":"a","admin_password":"SYNTH","admin_email":"a@x.invalid"}
yaml.safe_dump(d, open(sys.argv[2], "w"), sort_keys=False)
PY
lc "site actif présent dans vault_retired_grav_sites" ko \
  --retired "$FIX/registry/retired-sites.yml" --reactivated "$FIX/registry/reactivated-sites.yml" \
  --registry "$REG" --vault "$tmp/vault-leak.yml"

# 4c. site retiré resté dans vault_grav_sites (GSO-REQ-073)
python3 - "$VAULT" "$tmp/vault-stuck.yml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
d["vault_grav_sites"]["grav-gamma"] = {"admin_user":"g","admin_password":"SYNTH","admin_email":"g@x.invalid"}
yaml.safe_dump(d, open(sys.argv[2], "w"), sort_keys=False)
PY
lc "site retiré resté dans vault_grav_sites (GSO-REQ-073)" ko \
  --retired "$FIX/registry/retired-sites.yml" --reactivated "$FIX/registry/reactivated-sites.yml" \
  --registry "$REG" --vault "$tmp/vault-stuck.yml"

# 4d. racine reactivated inconnue
printf 'reactivations:\n  grav-x: []\n' > "$tmp/bad-react-root.yml"
lc "racine YAML inconnue (reactivated-sites)" ko \
  --retired "$FIX/registry/retired-sites.yml" --reactivated "$tmp/bad-react-root.yml"

# 4e. événement de réactivation : valeur non-liste
printf 'reactivated_sites:\n  grav-x:\n    reactivated_at: "2026-01-01"\n' > "$tmp/not-list.yml"
lc "événement de réactivation non encapsulé dans une liste" ko \
  --retired "$FIX/registry/retired-sites.yml" --reactivated "$tmp/not-list.yml"

# 4f. historique réécrit : événements dans le désordre chronologique
python3 - "$tmp/twice.yml" "$tmp/reordered.yml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
d["reactivated_sites"]["grav-gamma"].reverse()   # 2026-11-01 avant 2026-09-08
yaml.safe_dump(d, open(sys.argv[2], "w"), sort_keys=False)
PY
lc "historique de réactivation réécrit (désordre chronologique)" ko \
  --retired "$A/registry/retired-sites.yml" --reactivated "$tmp/reordered.yml"

# 4g. clé « réactivée » qui subsiste dans retired_grav_sites avec date antérieure
python3 - "$FIX/registry/retired-sites.yml" "$tmp/stuck-retired.yml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
# grav-delta est réactivé le 2026-06-10 ; on le remet indûment dans retired avec une date ANTÉRIEURE
d["retired_grav_sites"]["grav-delta"] = dict(d["retired_grav_sites"]["grav-gamma"])
d["retired_grav_sites"]["grav-delta"]["retired_at"] = "2026-05-15"
d["retired_grav_sites"]["grav-delta"]["former_inventory_host"] = "grav-delta"
yaml.safe_dump(d, open(sys.argv[2], "w"), sort_keys=False)
PY
lc "clé réactivée subsistant dans retired_grav_sites (GSO-REQ-181)" ko \
  --retired "$tmp/stuck-retired.yml" --reactivated "$FIX/registry/reactivated-sites.yml"

# --------------------------------------------------------------------------
# 5. Validateur strictement read-only ; aucun résidu
# --------------------------------------------------------------------------
sig() { find "$1" -type f -exec stat -c '%n %Y %s' {} \; | sort | sha1sum; }
b="$(sig "$FIX")"
python3 "$LC" --retired "$FIX/registry/retired-sites.yml" --reactivated "$FIX/registry/reactivated-sites.yml" \
  --registry "$REG" --vault "$VAULT" >/dev/null 2>&1
[ "$b" = "$(sig "$FIX")" ] && pass "validateur : lecture seule (fixture inchangée)" || fail "fixture modifiée par le validateur"

cur="$(cd "$REPO_ROOT" && git status --porcelain -- tests/fixtures/ registry/)"
[ -z "$cur" ] && pass "fixtures/ et registry/ suivis inchangés" || fail "modifié : $cur"

gso_assert_runtime_clean
finish
