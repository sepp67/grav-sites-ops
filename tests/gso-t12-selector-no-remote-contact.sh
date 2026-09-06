#!/usr/bin/env bash
# GSO-T12 — Aucune connexion distante après refus du préflight.
#
# Le sélecteur et le préflight sont strictement locaux : ils n'invoquent
# jamais `ansible-playbook`, `ssh`, ni le rôle, et échouent avant tout
# contact distant (GSO-REQ-095, GSO-REQ-107).

TEST_ID="GSO-T12"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"
H="python3 $GSO_SELECT_HARNESS"
F="$DIR/fixtures"

TARGETS='scripts/lib/gso_validate.py
scripts/validate-target.sh
scripts/preflight.sh'

code_only() {
  awk '
    /^[[:space:]]*"""/ { d = !d; next }
    d { next }
    /^[[:space:]]*#/ { next }
    { sub(/[[:space:]]#.*$/, ""); print }
  ' "$1"
}

# --- 1. Aucune primitive de connexion / déploiement dans le code exécuté ---
bad=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if code_only "$REPO_ROOT/$f" \
       | grep -nE 'ansible-playbook|(^|[^[:alnum:]_])ssh[[:space:]]|paramiko|sepp67\.grav_site|include_role|import_role|-c[[:space:]]+ssh|ProxyCommand|sshpass'; then
    fail "primitive de connexion/déploiement dans $f"
    bad=1
  fi
done <<< "$TARGETS"
[ "$bad" -eq 0 ] && pass "aucune primitive ansible-playbook / ssh / rôle dans le sélecteur et le préflight"

# --- 2. Aucune option --root sur l'interface opérateur ---
if code_only "$REPO_ROOT/scripts/validate-target.sh" | grep -q -- '--root' \
   || code_only "$REPO_ROOT/scripts/preflight.sh" | grep -q -- '--root'; then
  fail "les wrappers opérateurs mentionnent --root"
else
  pass "les wrappers opérateurs n'exposent aucune option --root"
fi
sp_block="$(awk '/for name in \("selector", "preflight"\):/{f=1} f{print} /args = ap\.parse_args/{f=0}' "$REPO_ROOT/scripts/lib/gso_validate.py")"
if printf '%s\n' "$sp_block" | grep -q 'add_argument("site"' \
   && ! printf '%s\n' "$sp_block" | grep -qE 'add_argument\("--|add_argument\("-[a-z]'; then
  pass "les sous-commandes selector/preflight n'ajoutent que l'argument SITE"
else
  fail "selector/preflight exposent une option :"
  printf '%s\n' "$sp_block" | grep 'add_argument' | sed 's/^/      | /'
fi

# --- 3. La seule commande externe du validateur est ansible-inventory --list ---
code="$(code_only "$REPO_ROOT/scripts/lib/gso_validate.py")"
has_inv=$(printf '%s\n' "$code" | grep -cE '"ansible-inventory".*"--list"' || true)
other_exec=$(printf '%s\n' "$code" \
  | grep -nE 'os\.system|os\.exec|subprocess\.Popen|"(ssh|ansible|ansible-playbook|scp|rsync|docker)"' || true)
if [ "$has_inv" -ge 1 ] && [ -z "$other_exec" ]; then
  pass "unique commande externe : ansible-inventory --list (local, sans connexion)"
else
  fail "commande externe inattendue : ${other_exec:-<ansible-inventory --list absent>}"
fi

# --- 4. Le chemin L3 (sélecteur + préflight) n'invoque aucun playbook ---
# (deploy-site.yml existe à partir de L4 mais n'est appelé que par
#  scripts/deploy.sh, APRÈS le sélecteur et le verrou.)
if code_only "$REPO_ROOT/scripts/validate-target.sh" | grep -qE 'ansible-playbook|deploy-site' \
   || code_only "$REPO_ROOT/scripts/preflight.sh" | grep -qE 'ansible-playbook|deploy-site'; then
  fail "le sélecteur ou le préflight invoque un playbook"
else
  pass "sélecteur et préflight n'invoquent aucun playbook (lecture seule)"
fi

# --- 5. Refus rapide, sans tentative de contact, sur cible inconnue ---
start=$(date +%s)
$H selector grav-zeta "$F/l3-prod-ok" >/dev/null 2>&1 && rc=0 || rc=$?
end=$(date +%s)
if [ "$rc" -ne 0 ] && [ $((end - start)) -lt 15 ]; then
  pass "refus d'une cible inconnue en < 15 s, sans blocage réseau (rc=$rc)"
else
  fail "comportement anormal (rc=$rc, durée $((end - start)) s)"
fi

# --- 6. Le préflight échoue fermé sur une arborescence incohérente ---
if $H preflight grav-beta "$F/l3-prod-retired-conflict" >/dev/null 2>&1; then
  fail "le préflight a réussi sur une arborescence incohérente"
else
  pass "le préflight échoue fermé sur incohérence, avant tout contact (rc != 0)"
fi

# --- 7. Le préflight n'écrit aucun fichier (read-only) ---
before="$(cd "$F/l3-prod-ok" && find . -type f | sort | md5sum)"
$H preflight grav-alpha "$F/l3-prod-ok" >/dev/null 2>&1 || true
after="$(cd "$F/l3-prod-ok" && find . -type f | sort | md5sum)"
if [ "$before" = "$after" ]; then
  pass "préflight strictement read-only (fixture inchangée)"
else
  fail "le préflight a modifié la fixture"
fi

finish
