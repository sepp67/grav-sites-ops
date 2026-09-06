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

# --- 2. Aucun chemin absolu de workstation dans les fichiers d'execution ---
# Motifs assembles a l'execution pour que ce script ne se matche pas lui-meme.
# docs/ est exclu : la documentation normative cite ces motifs comme exemples
# de ce qui est interdit (contrat, section 14.6). Le controle porte sur les
# fichiers qui participent a l'execution et a la configuration.
h="$(printf '%s' '/ho')$(printf '%s' 'me/')"
u="$(printf '%s' '/Us')$(printf '%s' 'ers/')"
r="$(printf '%s' '/ro')$(printf '%s' 'ot/')"
path_hits="$(git grep -lI -e "$h" -e "$u" -e "$r" -- . \
  ':!tests/gso-t24-no-local-paths-secrets.sh' ':!docs/' || true)"
if [ -n "$path_hits" ]; then
  fail "chemin absolu de workstation dans des fichiers suivis :"
  printf '%s\n' "$path_hits" | sed 's/^/      | /'
else
  pass "aucun chemin absolu de workstation hors documentation"
fi

# --- 3. Aucun vault ni fichier de secret suivi ---
secret_tracked="$(git ls-files | grep -E '(^|/)vault\.ya?ml$|\.vault$|\.vault_pass$|(^|/)\.vault-password$|vault[-_].*\.ya?ml$' || true)"
if [ -n "$secret_tracked" ]; then
  fail "fichier de secret suivi par Git :"
  printf '%s\n' "$secret_tracked" | sed 's/^/      | /'
else
  pass "aucun vault ni fichier de secret suivi"
fi

# --- 3b. Garde Git du vault : exception .example etroite et nommee (GSO-REQ-098) ---
# Seul le chemin exact du modele d'exemple est suivable ; tout autre fichier
# de forme vault reste ignore.
allowed="inventories/example/group_vars/all/vault.yml.example"
if git check-ignore -q "$allowed"; then
  fail "le modele d'exemple $allowed est ignore (il doit etre suivable)"
else
  pass "modele d'exemple suivable : $allowed"
fi
for p in \
  "inventories/example/group_vars/all/vault.yml" \
  "inventories/production/group_vars/all/vault.yml.example" \
  "tests/fixtures/x/vault.yml.example" \
  "docs/vault.yaml" \
  "anywhere/vault_secrets.yml" ; do
  if git check-ignore -q "$p"; then
    pass "ignore : $p"
  else
    fail "NON ignore alors qu'il devrait l'etre : $p"
  fi
done

# --- 3c. Les VALEURS sensibles du vault d'exemple n'apparaissent que la ---
# (GSO-REQ-024, GSO-REQ-074). La liste est derivee du fichier lui-meme
# (tests/lib/vault_values.py), jamais recopiee dans le code de test.
EXVAULT="inventories/example/group_vars/all/vault.yml.example"
stray=0
if [ -f "$EXVAULT" ]; then
  while IFS= read -r m; do
    [ -z "$m" ] && continue
    hits="$(git grep -lF -- "$m" -- ":!$EXVAULT" || true)"
    if [ -n "$hits" ]; then
      fail "valeur du vault presente hors du modele d'exemple :"
      printf '%s\n' "$hits" | sed 's/^/      | /'
      stray=1
    fi
  done < <(python3 "$DIR/lib/vault_values.py" "$EXVAULT")
  [ "$stray" -eq 0 ] && pass "valeurs sensibles confinees au modele d'exemple"
else
  fail "modele de vault d'exemple absent : $EXVAULT"
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
