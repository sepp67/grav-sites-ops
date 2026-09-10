#!/usr/bin/env bash
# L10 — Renforcement de l'isolation multi-site (GSO-REQ-142, porteur L10).
#
# Complète GSO-T16 (deux sites, isolation à la traduction) et GSO-T14
# (isolation des secrets) avec : trois sites, déploiements ENTRELACÉS
# (A → B → A), absence de lecture croisée du vault, `no_log` sous `-v`,
# résolution EXCLUSIVEMENT par inventory_hostname.
#
# 100 % local, doublure de rôle, sans Docker / réseau / connexion.

TEST_ID="L10-MULTISITE-ISOLATION"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

tmp="$(gso_mktemp_dir l10-iso)"
trap 'rm -rf "$tmp"' EXIT
gso_isolate_runtime "$tmp"

T="$tmp/tree"
l4_tmptree l3-prod-ok "$T"
gso_spy_role_into "$T"
printf 'retired_grav_sites: {}\n' > "$T/registry/retired-sites.yml"   # grav-gamma redevient un site actif ici

# --- trois hôtes actifs ---
cat > "$T/inventories/production/hosts.yml" <<'YML'
all:
  children:
    grav_servers:
      hosts:
        grav-alpha: {ansible_host: 192.0.2.21}
        grav-beta:  {ansible_host: 192.0.2.22}
        grav-gamma: {ansible_host: 192.0.2.23}
YML
cat > "$T/inventories/production/group_vars/all/grav_sites.yml" <<'YML'
grav_sites:
  grav-alpha: {project_name: pa, image: reg.invalid/a, version: "1.0.0", digest: "", container_name: ctn-a, base_directory: /opt/a, bind_address: 192.0.2.21, http_port: 8081, state: started}
  grav-beta:  {project_name: pb, image: reg.invalid/b, version: "2.0.0", digest: "", container_name: ctn-b, base_directory: /opt/b, bind_address: 192.0.2.22, http_port: 8082, state: started}
  grav-gamma: {project_name: pc, image: reg.invalid/c, version: "3.0.0", digest: "", container_name: ctn-c, base_directory: /opt/c, bind_address: 192.0.2.23, http_port: 8083, state: started}
YML
cat > "$T/inventories/production/group_vars/all/vault.yml" <<'YML'
vault_grav_sites:
  grav-alpha: {admin_user: ua, admin_password: SYNTH-L10-A-PW, admin_email: a@x.invalid, secrets: [{name: a.php, content: "SYNTH-L10-A-CONTENT"}]}
  grav-beta:  {admin_user: ub, admin_password: SYNTH-L10-B-PW, admin_email: b@x.invalid, secrets: [{name: b.php, content: "SYNTH-L10-B-CONTENT"}]}
  grav-gamma: {admin_user: uc, admin_password: SYNTH-L10-C-PW, admin_email: c@x.invalid, secrets: [{name: c.php, content: "SYNTH-L10-C-CONTENT"}]}
vault_retired_grav_sites: {}
YML

dep() {  # <site> <spydir> [ansible extra] -> rc
  local site="$1" spy="$2"; shift 2
  local rc=0
  mkdir -p "$spy"
  ( cd "$T" && GSO_SPY_OUTPUT="$spy" ANSIBLE_ROLES_PATH="$T/roles" \
      ansible-playbook -i inventories/production/hosts.yml playbooks/deploy-site.yml \
      --limit "$site" "$@" ) > "$tmp/$site-$(basename "$spy").log" 2>&1 || rc=$?
  echo "$rc"
}

field() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$1" "$2"; }
secrets_names() { python3 -c 'import json,sys; print(",".join(x["name"] for x in json.load(open(sys.argv[1])).get("grav_secrets",[])))' "$1"; }

# --------------------------------------------------------------------------
# 1. Trois sites : chaque capture est PROPRE au site
# --------------------------------------------------------------------------
for s in grav-alpha grav-beta grav-gamma; do
  rc="$(dep "$s" "$tmp/spy-$s")"
  [ "$rc" = 0 ] || { sed 's/^/   | /' "$tmp/$s"-*.log | tail -12; fail "$s : déploiement (doublure) rc=$rc"; finish; }
done
declare -A EXP_IMG=( [grav-alpha]=reg.invalid/a [grav-beta]=reg.invalid/b [grav-gamma]=reg.invalid/c )
declare -A EXP_SEC=( [grav-alpha]=a.php [grav-beta]=b.php [grav-gamma]=c.php )
declare -A LETTER=( [grav-alpha]=A [grav-beta]=B [grav-gamma]=C )
ok=1
for s in grav-alpha grav-beta grav-gamma; do
  j="$tmp/spy-$s/$s.json"
  [ -f "$j" ] || { fail "$s : capture absente"; ok=0; continue; }
  [ "$(field "$j" grav_image)" = "${EXP_IMG[$s]}" ] || { fail "$s : grav_image = $(field "$j" grav_image)"; ok=0; }
  [ "$(secrets_names "$j")" = "${EXP_SEC[$s]}" ] || { fail "$s : secrets = $(secrets_names "$j")"; ok=0; }
  for o in grav-alpha grav-beta grav-gamma; do
    [ "$o" = "$s" ] && continue
    grep -qE "SYNTH-L10-${LETTER[$o]}-" "$j" && { fail "$s : contient une valeur de $o"; ok=0; }
  done
done
[ "$ok" = 1 ] && pass "trois sites : chaque capture ne contient que les variables et secrets de son hôte"

# --------------------------------------------------------------------------
# 2. Déploiements ENTRELACÉS A → B → A : pas de fuite d'état entre invocations
# --------------------------------------------------------------------------
dep grav-alpha "$tmp/il-a1" >/dev/null
dep grav-beta  "$tmp/il-b"  >/dev/null
dep grav-alpha "$tmp/il-a2" >/dev/null
a1="$(cat "$tmp/il-a1/grav-alpha.json")"; a2="$(cat "$tmp/il-a2/grav-alpha.json")"
[ "$a1" = "$a2" ] && pass "A → B → A : la 2ᵉ capture de A est identique à la 1ʳᵉ (aucune contamination par B)" \
                  || fail "A → B → A : la capture de A a changé après un déploiement de B"
grep -qE 'SYNTH-L10-B-' "$tmp/il-a2/grav-alpha.json" && fail "la 2ᵉ capture de A contient une valeur de B" \
  || pass "A → B → A : aucune valeur de B dans la 2ᵉ capture de A"

# --------------------------------------------------------------------------
# 3. Indépendance par hôte : retirer grav-beta de TOUT le parc, A et C déploient
#    (le préflight structurel L4 valide la cohérence globale du parc : on retire
#    grav-beta de l'inventaire ET du registre ET du vault ensemble.)
# --------------------------------------------------------------------------
python3 - "$T/inventories/production/hosts.yml" "$T/inventories/production/group_vars/all/grav_sites.yml" "$T/inventories/production/group_vars/all/vault.yml" <<'PY'
import sys, yaml
h = yaml.safe_load(open(sys.argv[1])); h["all"]["children"]["grav_servers"]["hosts"].pop("grav-beta")
yaml.safe_dump(h, open(sys.argv[1], "w"), sort_keys=False)
for p, root in ((sys.argv[2], "grav_sites"), (sys.argv[3], "vault_grav_sites")):
    d = yaml.safe_load(open(p)); d[root].pop("grav-beta")
    yaml.safe_dump(d, open(p, "w"), sort_keys=False)
PY
rc="$(dep grav-alpha "$tmp/spy-nobeta")"
{ [ "$rc" = 0 ] && [ -f "$tmp/spy-nobeta/grav-alpha.json" ]; } \
  && pass "grav-alpha déploie après retrait complet de grav-beta du parc (indépendance par hôte)" \
  || { sed 's/^/   | /' "$tmp"/grav-alpha-spy-nobeta.log | tail -10; fail "grav-alpha dépend d'un autre hôte"; }
grep -qE 'SYNTH-L10-B-' "$tmp/spy-nobeta/grav-alpha.json" && fail "capture de A pollue par des restes de B" \
  || pass "capture de A : aucune trace de B après son retrait"
rc="$(dep grav-beta "$tmp/spy-beta-gone")"
{ [ "$rc" != 0 ] && [ ! -f "$tmp/spy-beta-gone/_calls.log" ]; } \
  && pass "grav-beta (hors parc) : refusé par le sélecteur, rôle non invoqué (résolution par inventory_hostname)" \
  || fail "grav-beta accepté alors qu'il n'est plus dans l'inventaire"

# --------------------------------------------------------------------------
# 4. `no_log` : aucune valeur secrète dans les journaux, même sous -vv
# --------------------------------------------------------------------------
dep grav-alpha "$tmp/spy-vv" -vv >/dev/null
if grep -qE 'SYNTH-L10-A-(PW|CONTENT)' "$tmp"/grav-alpha-spy-vv.log; then
  fail "no_log : une valeur secrète apparaît dans le journal -vv"
else
  pass "no_log : aucune valeur secrète dans le journal, même sous -vv (GSO-REQ-024/092/142)"
fi

# --------------------------------------------------------------------------
# 5. Statique : la traduction n'indexe QUE par inventory_hostname
# --------------------------------------------------------------------------
if grep -vE '^\s*#' playbooks/_shared/translate.yml | grep -qE "grav_sites\[[^]]*inventory_hostname[^]]*\]" \
   && ! grep -vE '^\s*#' playbooks/_shared/translate.yml | grep -qE "grav_sites\['?grav-|vault_grav_sites\['?grav-|grav_sites\.[a-z]"; then
  pass "translate.yml : accès aux données UNIQUEMENT par grav_sites[inventory_hostname] / vault_grav_sites[inventory_hostname]"
else
  fail "translate.yml : accès aux données par une clé autre que inventory_hostname"
fi

# --------------------------------------------------------------------------
# 6. Fixtures et dépôt inchangés
# --------------------------------------------------------------------------
cur="$(cd "$REPO_ROOT" && git status --porcelain -- tests/fixtures/ playbooks/)"
[ -z "$cur" ] && pass "fixtures/ et playbooks/ suivis inchangés" || fail "modifié : $cur"

gso_assert_runtime_clean
finish
