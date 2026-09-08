#!/usr/bin/env bash
# L8 — Preuve APPEND-ONLY INTER-VERSION de registry/reactivated-sites.yml
# (GSO-REQ-181). Preuve de mécanisme sans numéro GSO-T dédié (convention du
# préflight, cohérente avec l4-concurrency-lock / l7-persistence-guard).
#
# 100 % local, déterministe, sans Docker / réseau / connexion. Prouve que
# `scripts/lifecycle-history-check.sh` :
#   - accepte l'historique RÉEL du dépôt (append-only jusqu'ici) ;
#   - accepte une transition qui ajoute un événement en fin de liste ;
#   - REFUSE une transition qui réécrit un événement ancien ;
#   - REFUSE explicitement un dépôt Git superficiel (pas de faux succès) ;
#   - tolère le commit initial (aucune transition antérieure).
# Le wrapper est le SEUL endroit qui touche à Git ; il n'écrit rien dans le
# dépôt courant.

TEST_ID="L8-HISTORY-APPEND-ONLY"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

tmp="$(gso_mktemp_dir l8-history)"
trap 'rm -rf "$tmp"' EXIT

WRAP="$REPO_ROOT/scripts/lifecycle-history-check.sh"

# --------------------------------------------------------------------------
# 1. Historique réel du dépôt : append-only
# --------------------------------------------------------------------------
if bash "$WRAP" > "$tmp/real.out" 2>&1; then
  pass "historique réel de registry/reactivated-sites.yml : append-only ($(grep -oE '[0-9]+ transition' "$tmp/real.out" | head -1))"
else
  sed 's/^/   | /' "$tmp/real.out"
  fail "l'historique réel viole l'append-only"
fi
grep -q 'git show\|--history-before' "$WRAP" && pass "le wrapper délègue la comparaison à gso_lifecycle.py --history-before" \
  || fail "le wrapper n'utilise pas gso_lifecycle.py"
code_only() { grep -vE '^[[:space:]]*#' "$1"; }
if code_only "$WRAP" | grep -qE 'git (add|commit|push|checkout|reset|rebase|merge|tag)|>[[:space:]]*"?\$ROOT|tee '; then
  fail "le wrapper contient une commande Git mutante ou une écriture dans le dépôt"
else
  pass "le wrapper : lecture seule (git show/log/rev-parse uniquement)"
fi

# --------------------------------------------------------------------------
# Fabrique d'un mini-dépôt jouet
# --------------------------------------------------------------------------
mk_repo() {  # <dir>
  local d="$1"
  mkdir -p "$d/registry" "$d/scripts/lib"
  cp "$REPO_ROOT/scripts/lifecycle-history-check.sh" "$d/scripts/lifecycle-history-check.sh"
  cp "$REPO_ROOT/scripts/lib/gso_lifecycle.py" "$d/scripts/lib/gso_lifecycle.py"
  cp "$REPO_ROOT/scripts/lib/gso_validate.py" "$d/scripts/lib/gso_validate.py"
  ( cd "$d" && git init -q && git config user.email t@t.invalid && git config user.name t \
      && git add -A && git commit -q -m "harness" )
}
ev() {  # <date> <retired_at>
  printf '    - {reactivated_at: "%s", project_name: p, former_inventory_host: grav-p, previous_retirement: {retired_at: "%s", reason: r}}\n' "$1" "$2"
}
commit_file() {  # <dir> <content-file> <msg>
  cp "$2" "$1/registry/reactivated-sites.yml"
  ( cd "$1" && git add registry/reactivated-sites.yml && git commit -q -m "$3" )
}

# --------------------------------------------------------------------------
# 2. Transition VALIDE : un événement ajouté en fin
# --------------------------------------------------------------------------
G="$tmp/good"; mk_repo "$G"
{ echo "reactivated_sites:"; echo "  grav-p:"; ev 2026-01-10 2025-12-01; } > "$tmp/v1.yml"
{ echo "reactivated_sites:"; echo "  grav-p:"; ev 2026-01-10 2025-12-01; ev 2026-06-10 2026-05-01; } > "$tmp/v2.yml"
commit_file "$G" "$tmp/v1.yml" "v1"
commit_file "$G" "$tmp/v2.yml" "v2 append"
if ( cd "$G" && bash scripts/lifecycle-history-check.sh ) > "$tmp/g.out" 2>&1; then
  pass "transition valide (ajout en fin) : acceptée"
else
  sed 's/^/   | /' "$tmp/g.out"; fail "transition valide refusée"
fi

# --------------------------------------------------------------------------
# 3. Transition INVALIDE : un événement ancien réécrit
# --------------------------------------------------------------------------
B="$tmp/bad"; mk_repo "$B"
{ echo "reactivated_sites:"; echo "  grav-p:"; ev 2026-01-10 2025-12-01; } > "$tmp/b1.yml"
{ echo "reactivated_sites:"; echo "  grav-p:"; ev 2026-01-11 2025-12-02; } > "$tmp/b2.yml"   # date modifiée
commit_file "$B" "$tmp/b1.yml" "b1"
commit_file "$B" "$tmp/b2.yml" "b2 rewrite"
if ( cd "$B" && bash scripts/lifecycle-history-check.sh ) > "$tmp/b.out" 2>&1; then
  sed 's/^/   | /' "$tmp/b.out"; fail "réécriture d'un événement ancien : acceptée à tort"
else
  pass "réécriture d'un événement ancien : REFUSÉE ($(grep -oE 'ÉCHEC append-only' "$tmp/b.out" | head -1))"
fi

# --------------------------------------------------------------------------
# 4. Transition INVALIDE : un événement ancien supprimé
# --------------------------------------------------------------------------
D="$tmp/del"; mk_repo "$D"
commit_file "$D" "$tmp/v2.yml" "d1 (deux événements)"
commit_file "$D" "$tmp/v1.yml" "d2 (retour à un seul)"
if ( cd "$D" && bash scripts/lifecycle-history-check.sh ) >/dev/null 2>&1; then
  fail "suppression d'un événement ancien : acceptée à tort"
else
  pass "suppression d'un événement ancien (troncature) : REFUSÉE"
fi

# --------------------------------------------------------------------------
# 5. Dépôt superficiel : REFUS explicite (pas de faux succès)
# --------------------------------------------------------------------------
S="$tmp/shallow"
git clone -q --depth 1 "file://$G/.git" "$S"
cp "$REPO_ROOT/scripts/lifecycle-history-check.sh" "$S/scripts/lifecycle-history-check.sh" 2>/dev/null || {
  mkdir -p "$S/scripts/lib"; cp "$REPO_ROOT/scripts/lifecycle-history-check.sh" "$S/scripts/lifecycle-history-check.sh"
  cp "$REPO_ROOT/scripts/lib/gso_lifecycle.py" "$S/scripts/lib/"; cp "$REPO_ROOT/scripts/lib/gso_validate.py" "$S/scripts/lib/"; }
if ( cd "$S" && bash scripts/lifecycle-history-check.sh ) > "$tmp/s.out" 2>&1; then
  sed 's/^/   | /' "$tmp/s.out"; fail "dépôt superficiel : faux succès"
else
  grep -qi 'superficiel' "$tmp/s.out" && pass "dépôt superficiel : REFUS explicite (aucun faux succès)" \
    || { sed 's/^/   | /' "$tmp/s.out"; fail "dépôt superficiel refusé mais sans message clair"; }
fi

# --------------------------------------------------------------------------
# 6. Commit initial : toléré (aucune transition antérieure)
# --------------------------------------------------------------------------
I="$tmp/init"; mk_repo "$I"
commit_file "$I" "$tmp/v1.yml" "introduit reactivated-sites.yml"
if ( cd "$I" && bash scripts/lifecycle-history-check.sh ) > "$tmp/i.out" 2>&1; then
  grep -qi 'commit initial\|0 transition' "$tmp/i.out" && pass "commit initial : toléré, aucune transition à vérifier" \
    || { sed 's/^/   | /' "$tmp/i.out"; fail "commit initial : message inattendu"; }
else
  sed 's/^/   | /' "$tmp/i.out"; fail "commit initial refusé à tort"
fi

# --------------------------------------------------------------------------
# 7. Le dépôt courant n'a pas été modifié
# --------------------------------------------------------------------------
cur="$(cd "$REPO_ROOT" && git status --porcelain -- registry/ scripts/ tests/fixtures/)"
[ -z "$cur" ] && pass "dépôt courant inchangé (registry/, scripts/, fixtures/)" || fail "modifié : $cur"

finish
