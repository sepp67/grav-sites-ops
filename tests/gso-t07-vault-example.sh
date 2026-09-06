#!/usr/bin/env bash
# GSO-T07 — Correspondance hôte–registre–vault d'exemple.
#
# Démontre : chargement/analyse correcte du vault d'exemple selon le
# mécanisme prévu ; correspondance exacte des clés de projet entre
# inventaire, registre et vault ; rejet des entrées orphelines / manquantes
# / surnuméraires ; validité du schéma administrateur (tri-state) ;
# validité de `grav_secrets` sous la forme name + content ; rejet de `src`
# et des champs non autorisés ; absence de secret dans le registre non
# secret ; absence de fuite de valeurs dans les sorties de test.
#
# Exigences : GSO-REQ-024, 061, 062, 069, 203 (et GSO-REQ-073 par ricochet).

TEST_ID="GSO-T07"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

INV="inventories/example/hosts.yml"
REG="inventories/example/group_vars/all/grav_sites.yml"
VAULT="inventories/example/group_vars/all/vault.yml.example"

for f in "$INV" "$REG" "$VAULT"; do
  [ -f "$f" ] || { fail "fichier absent : $f"; finish; }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Valeurs sensibles du vault d'exemple, dérivées du fichier lui-même (jamais
# recopiées ici). Elles ne doivent JAMAIS apparaître dans une sortie de test
# (GSO-REQ-024, GSO-REQ-074).
MARKERS="$(python3 "$DIR/lib/vault_values.py" "$VAULT")"

# --- 1. Le vault d'exemple n'est PAS chargé automatiquement par Ansible ---
if ansible-inventory -i "$INV" --list > "$tmp/inv.json" 2>/dev/null; then
  if grep -q 'vault_grav_sites' "$tmp/inv.json"; then
    fail "vault_grav_sites chargé automatiquement — le modèle .example doit rester inerte"
  else
    pass "vault.yml.example non chargé automatiquement (extension .example)"
  fi
else
  fail "ansible-inventory a échoué"
fi

# --- 2. Analyse en clair + schéma complet (validateur statique L2) ---
if python3 "$GSO_VALIDATE" vault --inventory "$INV" > "$tmp/lint.out" 2>&1; then
  sed 's/^/      /' "$tmp/lint.out"
  pass "validateur vault : modèle d'exemple cohérent"
else
  sed 's/^/      /' "$tmp/lint.out"
  fail "validateur vault : incohérence dans le modèle d'exemple"
fi

# --- 3. Aucune fuite de valeur dans la sortie du validateur ---
leak=0
while IFS= read -r m; do
  [ -z "$m" ] && continue
  if grep -qF -- "$m" "$tmp/lint.out"; then
    fail "fuite : le marqueur « $m » apparaît dans la sortie du validateur vault"
    leak=1
  fi
done <<< "$MARKERS"
[ "$leak" -eq 0 ] && pass "aucune valeur du vault dans la sortie du validateur"

# --- 4. Cas négatifs : le validateur DOIT rejeter des vaults incohérents ---
mk_case() {
  # $1 = nom, $2 = corps yaml de vault_grav_sites
  local name="$1" body="$2" d="$tmp/$1"
  mkdir -p "$d/gv"
  cp "$INV" "$d/hosts.yml"
  cp "$REG" "$d/gv/grav_sites.yml"
  {
    printf 'vault_grav_sites:\n'
    printf '%s\n' "$body"
    printf 'vault_retired_grav_sites: {}\n'
  } > "$d/gv/vault.yml.example"
  if python3 "$GSO_VALIDATE" vault \
      --inventory "$d/hosts.yml" \
      --registry "$d/gv/grav_sites.yml" \
      --vault "$d/gv/vault.yml.example" > "$d/out" 2>&1; then
    fail "cas négatif « $name » accepté à tort"
  else
    n="$(grep -c '^FAIL' "$d/out" || true)"
    pass "cas négatif « $name » rejeté ($n écart(s))"
  fi
}

mk_case "orphelin+manquant" "$(cat <<'Y'
  grav-example-alpha:
    admin_user: u
    admin_password: p
    admin_email: e@x.invalid
  grav-orphan:
    admin_user: u
    admin_password: p
    admin_email: e@x.invalid
Y
)"

mk_case "admin-tri-state-partiel" "$(cat <<'Y'
  grav-example-alpha:
    admin_user: u
    admin_password: p
  grav-example-beta:
    admin_user: u
    admin_password: p
    admin_email: e@x.invalid
Y
)"

mk_case "secret-forme-src" "$(cat <<'Y'
  grav-example-alpha:
    admin_user: u
    admin_password: p
    admin_email: e@x.invalid
    secrets:
      - name: k.php
        src: /etc/whatever
  grav-example-beta:
    admin_user: u
    admin_password: p
    admin_email: e@x.invalid
Y
)"

mk_case "champ-non-autorise+nom-secret-invalide" "$(cat <<'Y'
  grav-example-alpha:
    admin_user: u
    admin_password: p
    admin_email: e@x.invalid
    unexpected_field: x
    secrets:
      - name: ../escape
        content: x
  grav-example-beta:
    admin_user: u
    admin_password: p
    admin_email: e@x.invalid
Y
)"

# Cas négatif : secret présent dans le registre NON secret (GSO-REQ-203/024) ---
d="$tmp/secret-dans-registre"; mkdir -p "$d/gv"
cp "$INV" "$d/hosts.yml"
{
  printf 'grav_sites:\n'
  printf '  grav-example-alpha: {project_name: a, image: registry.example.invalid/a, version: "1.0.0", digest: "", container_name: a, base_directory: /opt/a, bind_address: 192.0.2.11, http_port: 8080, secrets: [{name: k, content: v}]}\n'
  printf '  grav-example-beta: {project_name: b, image: registry.example.invalid/b, version: "1.0.0", digest: "", container_name: b, base_directory: /opt/b, bind_address: 192.0.2.12, http_port: 8081}\n'
} > "$d/gv/grav_sites.yml"
{
  printf 'vault_grav_sites:\n'
  printf '  grav-example-alpha: {admin_user: u, admin_password: p, admin_email: e@x.invalid}\n'
  printf '  grav-example-beta: {admin_user: u, admin_password: p, admin_email: e@x.invalid}\n'
  printf 'vault_retired_grav_sites: {}\n'
} > "$d/gv/vault.yml.example"
if python3 "$GSO_VALIDATE" vault --inventory "$d/hosts.yml" \
    --registry "$d/gv/grav_sites.yml" --vault "$d/gv/vault.yml.example" > "$d/out" 2>&1; then
  fail "cas négatif « secret-dans-registre » accepté à tort"
else
  pass "cas négatif « secret-dans-registre » rejeté ($(grep -c '^FAIL' "$d/out") écart(s))"
fi

# Cas négatif : racine de vault surnuméraire + clé active aussi retirée ---
d="$tmp/racine-et-disjonction"; mkdir -p "$d/gv"
cp "$INV" "$d/hosts.yml"; cp "$REG" "$d/gv/grav_sites.yml"
{
  printf 'vault_grav_sites:\n'
  printf '  grav-example-alpha: {admin_user: u, admin_password: p, admin_email: e@x.invalid}\n'
  printf '  grav-example-beta: {admin_user: u, admin_password: p, admin_email: e@x.invalid}\n'
  printf 'vault_retired_grav_sites:\n'
  printf '  grav-example-alpha: {admin_user: u, admin_password: p, admin_email: e@x.invalid}\n'
  printf 'stray_root: {}\n'
} > "$d/gv/vault.yml.example"
if python3 "$GSO_VALIDATE" vault --inventory "$d/hosts.yml" \
    --registry "$d/gv/grav_sites.yml" --vault "$d/gv/vault.yml.example" > "$d/out" 2>&1; then
  fail "cas négatif « racine-et-disjonction » accepté à tort"
else
  pass "cas négatif « racine-et-disjonction » rejeté ($(grep -c '^FAIL' "$d/out") écart(s))"
fi

finish
