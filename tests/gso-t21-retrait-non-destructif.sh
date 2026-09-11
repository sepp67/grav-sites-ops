#!/usr/bin/env bash
# GSO-T21 — Retrait déclaré sans tâche destructive (lot L8).
#
# 100 % local, déterministe, sans Docker / réseau / connexion. Prouve
# (contrat §21.6-21.7, §7.7 ; GSO-REQ-027/028/029/044/073/178/179/182) :
#   - AUCUN playbook / script livré n'applique un retrait ou une réactivation ;
#   - AUCUN playbook n'appelle un hyperviseur (Proxmox & co.) ;
#   - AUCUN outil livré ne modifie inventaire / registre / vault / Git ;
#   - le retrait est une transformation Git MANUELLE, vérifiée APRÈS COUP par
#     le validateur read-only `gso_lifecycle.py` ;
#   - un « après-retrait » cohérent (hôte hors inventaire + hors grav_sites,
#     fiche ajoutée à retired-sites.yml, secrets déplacés vers
#     vault_retired_grav_sites) valide ; les incohérences significatives sont
#     rejetées ;
#   - aucune donnée persistante n'est supprimée : la fiche retirée CONSERVE
#     `former_base_directory` et `persistent_data_preserved: true` ;
#   - les registres documentaires ne sont pas chargés automatiquement par
#     Ansible et ne contiennent aucun secret.

TEST_ID="GSO-T21"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

tmp="$(gso_mktemp_dir t21)"
trap 'rm -rf "$tmp"' EXIT
gso_isolate_runtime "$tmp"

LC="$REPO_ROOT/scripts/lib/gso_lifecycle.py"
FIX="$REPO_ROOT/tests/fixtures/l8-lifecycle-ok"
REG="$FIX/inventories/production/group_vars/all/grav_sites.yml"
code_only() { grep -vE '^[[:space:]]*#' "$1"; }

# Le vault de fixture est git-ignoré (**/vault.yml) : on le synthétise dans
# $tmp. Marqueurs synthétiques uniquement, jamais un secret réel.
VAULT="$tmp/vault.yml"
cat > "$VAULT" <<'YML'
vault_grav_sites:
  grav-alpha: {admin_user: alpha-admin, admin_password: SYNTH-L8T21-ALPHA, admin_email: alpha@example.invalid}
  grav-delta: {admin_user: delta-admin, admin_password: SYNTH-L8T21-DELTA, admin_email: delta@example.invalid}
vault_retired_grav_sites:
  grav-gamma: {admin_user: gamma-admin, admin_password: SYNTH-L8T21-GAMMA, admin_email: gamma@example.invalid}
  grav-omega: {admin_user: omega-admin, admin_password: SYNTH-L8T21-OMEGA, admin_email: omega@example.invalid}
YML

# --------------------------------------------------------------------------
# 1. Gardes statiques — aucun outil de transformation du cycle de vie
# --------------------------------------------------------------------------
if git ls-files 'playbooks/*' | grep -iE 'retir|retrait|reactiv|réactiv|lifecycle|decommission'; then
  fail "un playbook de cycle de vie a été livré (interdit — GSO-REQ-029)"
else
  pass "aucun playbook de retrait / réactivation (GSO-REQ-029)"
fi

# Capture d'abord (le producteur `git ls-files` va à son terme dans le
# `$( )`), grep ensuite sur la valeur déjà capturée (here-string) — jamais
# `producteur | grep -q` : sous `set -o pipefail`, un SIGPIPE du producteur
# (quand `grep -q` sort tôt) ferait échouer le pipeline même si grep a trouvé
# la ligne -> faux négatif sur ce garde-fou.
_lc_files="$(git ls-files 'scripts/*' 'playbooks/*' 'Makefile')"; _grc=$?
if [ "$_grc" -ne 0 ]; then
  fail "git ls-files a échoué (rc=$_grc)"
elif grep -qiE 'retire-site|reactivate-site|decommission' <<<"$_lc_files"; then
  fail "un script / une cible de transformation du cycle de vie a été livré"
else
  pass "aucun script ni cible Makefile appliquant un retrait / une réactivation"
fi
# cas négatif synthétique (copie temporaire, dépôt courant jamais touché)
_neg="$tmp/sigpipe-neg-t21a"; mkdir -p "$_neg/scripts"
git -C "$_neg" init -q
: > "$_neg/scripts/retire-site.sh"
git -C "$_neg" -c user.email=t@t -c user.name=t add -A >/dev/null
git -C "$_neg" -c user.email=t@t -c user.name=t commit -qm "cas négatif"
_neg_files="$(git -C "$_neg" ls-files 'scripts/*' 'playbooks/*' 'Makefile')"
grep -qiE 'retire-site|reactivate-site|decommission' <<<"$_neg_files" \
  && pass "cas négatif : un script « retire-site.sh » est bien détecté par cette logique" \
  || fail "cas négatif : un script de retrait n'est PAS détecté (faux négatif)"

# aucun appel d'hyperviseur (GSO-REQ-179)
if git grep -nIE 'proxmox|pvesh|qm (start|stop|shutdown)|libvirt|virsh|hypervisor|vim-cmd|esxcli' \
     -- 'playbooks/*' 'scripts/*' ; then
  fail "référence à une API d'hyperviseur dans un fichier d'exécution (GSO-REQ-179)"
else
  pass "aucun appel d'hyperviseur dans les playbooks / scripts (GSO-REQ-179)"
fi

# aucun playbook/script livré n'écrit dans un registre, un inventaire ou le vault
if git grep -nIE "(copy|template|lineinfile|blockinfile|replace):|>>?\s*['\"]?(.*/)?(grav_sites|hosts|vault|retired-sites|reactivated-sites)\.ya?ml|git (add|commit|push)" \
     -- 'playbooks/*' 'scripts/deploy.sh' 'scripts/restart-site.sh' 'scripts/stop-site.sh' \
        'scripts/check-site.sh' 'scripts/check-all.sh' 'scripts/lib/site-mutation.sh' \
        'scripts/lib/site-check.sh' 'scripts/validate-target.sh' 'scripts/preflight.sh' ; then
  fail "un fichier d'exécution écrit dans un registre / inventaire / vault ou automatise Git"
else
  pass "aucun fichier d'exécution ne modifie registre / inventaire / vault ni n'automatise un commit Git"
fi

# le validateur du cycle de vie est strictement en lecture seule
# (capture puis here-string : `code_only` est un `grep -vE` externe — même
# risque de SIGPIPE que ci-dessus si on le pipe directement dans `grep -q`)
_lc_code="$(code_only "$LC" || true)"
if grep -qE "\bopen\([^)]*['\"][wa]['\"]|\.write\(|os\.(remove|rename|replace|mkdir|makedirs)|shutil\.|subprocess|Popen|os\.system|git " <<<"$_lc_code"; then
  fail "gso_lifecycle.py contient une primitive d'écriture / d'exécution"
else
  pass "gso_lifecycle.py : lecture seule (aucune écriture, aucun sous-processus)"
fi
# cas négatif synthétique (fichier temporaire, dépôt courant jamais touché) :
# une primitive d'écriture DOIT être détectée par la même logique corrigée
_neg_py="$tmp/sigpipe-neg-t21b.py"
printf 'def f():\n    open("x", "w")\n' > "$_neg_py"
_neg_code="$(code_only "$_neg_py" || true)"
grep -qE "\bopen\([^)]*['\"][wa]['\"]|\.write\(|os\.(remove|rename|replace|mkdir|makedirs)|shutil\.|subprocess|Popen|os\.system|git " <<<"$_neg_code" \
  && pass "cas négatif : un open(...,\"w\") synthétique est bien détecté par cette logique" \
  || fail "cas négatif : une primitive d'écriture synthétique n'est PAS détectée (faux négatif)"

# les registres documentaires vivent hors de group_vars/ (jamais auto-chargés)
if git ls-files | grep -E 'group_vars/.*(retired-sites|reactivated-sites)' ; then
  fail "un registre de cycle de vie est sous group_vars/ (serait auto-chargé par Ansible)"
else
  pass "registry/retired-sites.yml et registry/reactivated-sites.yml sont hors de group_vars/"
fi
for f in registry/retired-sites.yml registry/reactivated-sites.yml; do
  git ls-files --error-unmatch "$f" >/dev/null 2>&1 && pass "$f est suivi par Git (documentaire)" \
    || fail "$f n'est pas suivi par Git"
done

# --------------------------------------------------------------------------
# 2. Retrait : transformation avant -> après sur fixtures synthétiques
# --------------------------------------------------------------------------
# "avant" = fixture cohérente. "après retrait de grav-alpha" construit en mktemp.
T="$tmp/after"; mkdir -p "$T/registry" "$T/gv"
cp "$FIX/registry/reactivated-sites.yml" "$T/registry/reactivated-sites.yml"

# grav_sites APRÈS : grav-alpha retiré du registre actif
python3 - "$REG" "$T/gv/grav_sites.yml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
d["grav_sites"].pop("grav-alpha", None)
yaml.safe_dump(d, open(sys.argv[2], "w"), sort_keys=False)
PY
# vault APRÈS : secrets de grav-alpha déplacés vers vault_retired_grav_sites
python3 - "$VAULT" "$T/gv/vault.yml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
e = d["vault_grav_sites"].pop("grav-alpha")
d.setdefault("vault_retired_grav_sites", {})["grav-alpha"] = e
yaml.safe_dump(d, open(sys.argv[2], "w"), sort_keys=False)
PY
# retired-sites APRÈS : fiche grav-alpha ajoutée, données persistantes CONSERVÉES
python3 - "$FIX/registry/retired-sites.yml" "$T/registry/retired-sites.yml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
d["retired_grav_sites"]["grav-alpha"] = {
    "project_name": "fixture-alpha",
    "retired_at": "2026-09-08",
    "former_inventory_host": "grav-alpha",
    "former_ansible_host": "192.0.2.31",
    "former_base_directory": "/opt/fixture-alpha",
    "container_name": "fixture-alpha",
    "last_deployment": {"image": "registry.example.invalid/fixture/grav-alpha",
                        "version": "1.0.0", "digest": ""},
    "preservation": {"vm_status": "stopped", "vm_preserved": True,
                     "persistent_data_preserved": True, "secrets_archived_in_vault": True},
    "reason": "Retrait de test (fixture)",
}
yaml.safe_dump(d, open(sys.argv[2], "w"), sort_keys=False)
PY

lc() {  # <label attendu ok|ko> puis args du validateur
  local want="$1"; shift
  local rc=0
  python3 "$LC" "$@" > "$tmp/lc.out" 2>&1 || rc=$?
  if [ "$want" = ok ]; then
    [ "$rc" = 0 ] && pass "validateur : $LABEL -> OK" || { sed 's/^/   | /' "$tmp/lc.out"|grep FAIL; fail "$LABEL : attendu OK (rc=$rc)"; }
  else
    [ "$rc" != 0 ] && pass "validateur : $LABEL -> rejeté (rc=$rc)" || fail "$LABEL : accepté à tort"
  fi
}

LABEL="après-retrait cohérent (grav-alpha)"
lc ok --retired "$T/registry/retired-sites.yml" --reactivated "$T/registry/reactivated-sites.yml" \
      --registry "$T/gv/grav_sites.yml" --vault "$T/gv/vault.yml"

# comparaison avant/après : grav-alpha disparu de l'actif => DOIT être dans retired (GSO-REQ-044/178)
before_active="$(python3 -c 'import yaml,sys;print(",".join(yaml.safe_load(open(sys.argv[1]))["grav_sites"]))' "$REG")"
after_active="$(python3 -c 'import yaml,sys;print(",".join(yaml.safe_load(open(sys.argv[1]))["grav_sites"]))' "$T/gv/grav_sites.yml")"
after_retired="$(python3 -c 'import yaml,sys;print(",".join(yaml.safe_load(open(sys.argv[1]))["retired_grav_sites"]))' "$T/registry/retired-sites.yml")"
if [[ ",$before_active," == *",grav-alpha,"* && ",$after_active," != *",grav-alpha,"* && ",$after_retired," == *",grav-alpha,"* ]]; then
  pass "GSO-REQ-044/178 : la clé retirée de grav_sites est présente dans retired_grav_sites (même changement)"
else
  fail "GSO-REQ-044/178 : suppression active sans ajout au registre retiré"
fi

# la fiche retirée conserve le chemin persistant et le drapeau de préservation
python3 -c '
import yaml,sys
e = yaml.safe_load(open(sys.argv[1]))["retired_grav_sites"]["grav-alpha"]
assert e["former_base_directory"] == "/opt/fixture-alpha", e
assert e["preservation"]["persistent_data_preserved"] is True, e
assert e["preservation"]["vm_preserved"] is True, e
' "$T/registry/retired-sites.yml" \
  && pass "retrait non destructif : chemin persistant conservé, données déclarées préservées (GSO-REQ-027/040)" \
  || fail "retrait : donnée persistante non conservée dans la fiche"

# --------------------------------------------------------------------------
# 3. Incohérences de retrait -> rejetées
# --------------------------------------------------------------------------
# 3a. grav-alpha resté actif ET retiré
cp "$REG" "$tmp/still-active.yml"
LABEL="retrait incohérent : clé encore active ET retirée (GSO-REQ-052)"
lc ko --retired "$T/registry/retired-sites.yml" --reactivated "$T/registry/reactivated-sites.yml" \
      --registry "$tmp/still-active.yml" --vault "$T/gv/vault.yml"

# 3b. secrets restés dans vault_grav_sites
LABEL="retrait incohérent : secrets non déplacés (GSO-REQ-073)"
lc ko --retired "$T/registry/retired-sites.yml" --reactivated "$T/registry/reactivated-sites.yml" \
      --registry "$T/gv/grav_sites.yml" --vault "$VAULT"

# 3c. fiche retirée contenant un secret
python3 - "$T/registry/retired-sites.yml" "$tmp/retired-secret.yml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
d["retired_grav_sites"]["grav-alpha"]["admin_password"] = "LEAKED-PW"
yaml.safe_dump(d, open(sys.argv[2], "w"), sort_keys=False)
PY
LABEL="fiche retirée contenant un secret (GSO-REQ-028)"
lc ko --retired "$tmp/retired-secret.yml" --reactivated "$T/registry/reactivated-sites.yml"

# 3d. racine YAML inconnue
printf 'retired_sites:\n  grav-x: {}\n' > "$tmp/bad-root.yml"
LABEL="racine YAML inconnue"
lc ko --retired "$tmp/bad-root.yml" --reactivated "$T/registry/reactivated-sites.yml"

# 3e. date invalide
python3 - "$T/registry/retired-sites.yml" "$tmp/bad-date.yml" <<'PY'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
d["retired_grav_sites"]["grav-alpha"]["retired_at"] = "hier"
yaml.safe_dump(d, open(sys.argv[2], "w"), sort_keys=False)
PY
LABEL="date de retrait invalide"
lc ko --retired "$tmp/bad-date.yml" --reactivated "$T/registry/reactivated-sites.yml"

# --------------------------------------------------------------------------
# 4. Le validateur n'écrit rien ; fixtures et dépôt intacts ; aucun résidu
# --------------------------------------------------------------------------
before="$(cd "$FIX" && find . -type f -exec stat -c '%n %Y %s' {} \; | sort | sha1sum)"
python3 "$LC" --retired "$FIX/registry/retired-sites.yml" --reactivated "$FIX/registry/reactivated-sites.yml" \
  --registry "$REG" \
  --vault "$VAULT" >/dev/null 2>&1
after="$(cd "$FIX" && find . -type f -exec stat -c '%n %Y %s' {} \; | sort | sha1sum)"
[ "$before" = "$after" ] && pass "validateur : la fixture n'est pas modifiée (lecture seule)" || fail "la fixture a changé"

cur="$(cd "$REPO_ROOT" && git status --porcelain -- tests/fixtures/ registry/)"
[ -z "$cur" ] && pass "fixtures/ et registry/ suivis inchangés" || fail "modifié : $cur"

gso_assert_runtime_clean
finish
