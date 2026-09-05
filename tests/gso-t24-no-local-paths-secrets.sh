#!/usr/bin/env bash
# GSO-T24 — Absence de chemins locaux, de liens symboliques externes et de
# secrets suivis.
#
# Couvre GSO-REQ-024 (aucun secret suivi), GSO-REQ-099 (portabilite du
# depot) et GSO-REQ-132 (categories sensibles non suivies).

TEST_ID="GSO-T24"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

# --- 1. Aucun lien symbolique suivi qui sorte du depot ---
symlinks="$(git ls-files -s | awk '$1 == "120000" {print $4}')"
if [ -z "$symlinks" ]; then
  pass "aucun lien symbolique suivi"
else
  while IFS= read -r link; do
    target="$(readlink "$link")"
    resolved="$(cd "$(dirname "$link")" && realpath -m "$target")"
    case "$resolved" in
      "$REPO_ROOT"/*) info "lien interne tolere : $link -> $target" ;;
      *) fail "lien symbolique externe : $link -> $target" ;;
    esac
  done <<< "$symlinks"
fi

# --- 2. Aucun chemin absolu de workstation dans les fichiers suivis ---
# Motifs assembles a l'execution pour que ce script ne se matche pas lui-meme.
h="$(printf '%s' '/ho')$(printf '%s' 'me/')"
u="$(printf '%s' '/Us')$(printf '%s' 'ers/')"
r="$(printf '%s' '/ro')$(printf '%s' 'ot/')"
path_hits="$(git grep -lI -e "$h" -e "$u" -e "$r" -- . ':!tests/gso-t24-no-local-paths-secrets.sh' || true)"
if [ -n "$path_hits" ]; then
  fail "chemin absolu de workstation dans des fichiers suivis :"
  printf '%s\n' "$path_hits" | sed 's/^/      | /'
else
  pass "aucun chemin absolu de workstation dans les fichiers suivis"
fi

# --- 3. Aucun vault ni fichier de secret suivi ---
secret_tracked="$(git ls-files | grep -E '(^|/)vault\.yml$|\.vault$|\.vault_pass$|(^|/)\.vault-password$|vault-.*\.yml$' || true)"
if [ -n "$secret_tracked" ]; then
  fail "fichier de secret suivi par Git :"
  printf '%s\n' "$secret_tracked" | sed 's/^/      | /'
else
  pass "aucun vault ni fichier de secret suivi"
fi

# --- 4. .gitignore couvre les categories sensibles prevues (section 17.7) ---
required_patterns='vault.yml
roles/
*.retry'
missing=""
while IFS= read -r pat; do
  grep -qF -- "$pat" .gitignore || missing="$missing $pat"
done <<< "$required_patterns"
if [ -n "$missing" ]; then
  fail ".gitignore ne couvre pas :$missing"
else
  pass ".gitignore couvre vault, roles installes et fichiers .retry"
fi

# --- 5. Les categories ignorees ne peuvent pas etre suivies accidentellement ---
# git check-ignore raisonne sur des motifs de chemin : aucun fichier n'est cree.
probe="inventories/production/group_vars/all/vault.yml"
if git check-ignore -q "$probe"; then
  pass "un vault de production place au bon endroit serait ignore"
else
  fail "un vault de production ne serait PAS ignore ($probe)"
fi

probe2="inventories/example/group_vars/all/vault.yml"
if git check-ignore -q "$probe2"; then
  pass "un vault reel egare dans inventories/example serait ignore"
else
  fail "un vault dans inventories/example ne serait PAS ignore"
fi

finish
