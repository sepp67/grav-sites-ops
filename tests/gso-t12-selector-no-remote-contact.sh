#!/usr/bin/env bash
# GSO-T12 — Aucune connexion distante après refus du préflight.
#
# Prouve que le sélecteur et le préflight sont strictement locaux : ils
# n'invoquent jamais `ansible-playbook`, `ssh`, ni le rôle, et échouent
# avant tout contact distant (GSO-REQ-095, GSO-REQ-107).

TEST_ID="GSO-T12"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"
S="$REPO_ROOT/scripts/validate-target.sh"
P="$REPO_ROOT/scripts/preflight.sh"
F="$DIR/fixtures"

TARGETS='scripts/lib/gso_validate.py
scripts/validate-target.sh
scripts/preflight.sh'

# Code seul, hors commentaires de ligne et docstrings triple-quotes.
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

# --- 2. Le seul sous-processus lancé par le validateur est ansible-inventory --list ---
code="$(code_only "$REPO_ROOT/scripts/lib/gso_validate.py")"
has_inv=$(printf '%s\n' "$code" | grep -cE '"ansible-inventory".*"--list"' || true)
other_exec=$(printf '%s\n' "$code" \
  | grep -nE 'os\.system|os\.exec|subprocess\.Popen|"(ssh|ansible|ansible-playbook|scp|rsync|docker)"' || true)
if [ "$has_inv" -ge 1 ] && [ -z "$other_exec" ]; then
  pass "unique commande externe : ansible-inventory --list (local, sans connexion)"
else
  fail "commande externe inattendue dans gso_validate.py : ${other_exec:-<ansible-inventory --list absent>}"
fi

# --- 3. Aucun playbook n'existe qui pourrait être invoqué ---
if [ -z "$(git ls-files 'playbooks/*.yml')" ]; then
  pass "playbooks/ ne contient aucun playbook (rien à invoquer)"
else
  fail "des playbooks existent : $(git ls-files 'playbooks/*.yml')"
fi

# --- 4. Refus rapide, sans tentative de contact, sur cible inconnue ---
start=$(date +%s)
bash "$S" grav-zeta --root "$F/l3-prod-ok" >/dev/null 2>&1 && rc=0 || rc=$?
end=$(date +%s)
if [ "$rc" -ne 0 ] && [ $((end - start)) -lt 15 ]; then
  pass "refus d'une cible inconnue en < 15 s, sans blocage réseau (rc=$rc)"
else
  fail "comportement anormal (rc=$rc, durée $((end - start)) s)"
fi

# --- 5. Le préflight échoue fermé sur une arborescence incohérente ---
if bash "$P" grav-beta --root "$F/l3-prod-retired-conflict" >/dev/null 2>&1; then
  fail "le préflight a réussi sur une arborescence incohérente"
else
  pass "le préflight échoue fermé sur incohérence, avant tout contact (rc != 0)"
fi

# --- 6. Le préflight n'écrit aucun fichier (read-only) ---
before="$(cd "$F/l3-prod-ok" && find . -type f | sort | md5sum)"
bash "$P" grav-alpha --root "$F/l3-prod-ok" >/dev/null 2>&1 || true
after="$(cd "$F/l3-prod-ok" && find . -type f | sort | md5sum)"
if [ "$before" = "$after" ]; then
  pass "préflight strictement read-only (fixture inchangée)"
else
  fail "le préflight a modifié la fixture"
fi

finish
