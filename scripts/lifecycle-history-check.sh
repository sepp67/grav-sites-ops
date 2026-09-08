#!/usr/bin/env bash
# grav-sites-ops — preuve APPEND-ONLY INTER-VERSION de
# registry/reactivated-sites.yml (lot L8, GSO-REQ-181).
#
# `gso_lifecycle.py` seul ne voit qu'un fichier : il vérifie le schéma et
# l'ordre chronologique de l'ÉTAT COURANT, mais pas la réécriture d'un
# historique entre deux versions. Ce wrapper — SEUL endroit qui touche à Git
# dans la chaîne de validation — parcourt les versions successives du fichier
# dans l'historique Git et fait vérifier CHAQUE transition (ancienne -> neuve)
# par `gso_lifecycle.py --history-before`.
#
# STRICTEMENT en lecture : `git show`, `git log`, `git rev-parse` uniquement.
# Aucune écriture, aucune transformation. Sortie dans un mktemp nettoyé.
#
# Un dépôt superficiel (`--depth`) NE DOIT PAS produire un faux succès : si
# l'historique est tronqué, le contrôle échoue explicitement. Le commit qui
# introduit le fichier n'a pas de prédécesseur : c'est le seul cas où une
# transition est absente sans erreur.

set -euo pipefail

SELF="$(readlink -f "$0" 2>/dev/null || realpath "$0")"
ROOT="$(cd "$(dirname "$SELF")/.." && pwd -P)"
FILE="registry/reactivated-sites.yml"
LC="$ROOT/scripts/lib/gso_lifecycle.py"

cd "$ROOT"

if [ ! -e ".git" ] && ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "lifecycle-history : pas un dépôt Git — contrôle inter-version impossible" >&2
  exit 1
fi

# --- Garde clone superficiel ---
if [ "$(git rev-parse --is-shallow-repository 2>/dev/null || echo true)" = "true" ]; then
  echo "lifecycle-history : dépôt Git SUPERFICIEL — l'append-only inter-version" >&2
  echo "  ne peut pas être prouvé. Récupérer l'historique complet (fetch-depth: 0)." >&2
  exit 1
fi

# --- Versions successives du fichier (récentes -> anciennes) ---
mapfile -t commits < <(git log --format=%H -- "$FILE")
n="${#commits[@]}"

if [ "$n" -eq 0 ]; then
  echo "lifecycle-history : $FILE n'a aucune version suivie — rien à comparer (attendu avant L8)"
  exit 0
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/gso-l8-history.XXXXXXXX")"
trap 'rm -rf "$tmp"' EXIT

fail=0
transitions=0

if [ "$n" -eq 1 ]; then
  echo "lifecycle-history : $FILE — commit initial ($( git rev-parse --short "${commits[0]}" )), aucune transition antérieure"
fi

# Parcourt chaque paire consécutive (plus récent = commits[i], antérieur = commits[i+1]).
for (( i = 0; i < n - 1; i++ )); do
  new="${commits[$i]}"
  old="${commits[$((i + 1))]}"
  git show "$old:$FILE" > "$tmp/before.yml" 2>/dev/null || { echo "  ! version $old illisible" >&2; fail=1; continue; }
  git show "$new:$FILE" > "$tmp/after.yml"  2>/dev/null || { echo "  ! version $new illisible" >&2; fail=1; continue; }
  transitions=$((transitions + 1))
  if python3 "$LC" --history-before "$tmp/before.yml" --reactivated "$tmp/after.yml" > "$tmp/out" 2>&1; then
    echo "lifecycle-history : $(git rev-parse --short "$old") -> $(git rev-parse --short "$new") : append-only OK"
  else
    echo "lifecycle-history : $(git rev-parse --short "$old") -> $(git rev-parse --short "$new") : ÉCHEC append-only"
    sed 's/^/    | /' "$tmp/out"
    fail=1
  fi
done

echo "----"
if [ "$fail" -ne 0 ]; then
  echo "lifecycle-history : au moins une transition viole l'append-only de $FILE"
  exit 1
fi
echo "lifecycle-history : $transitions transition(s) vérifiée(s) — $FILE est append-only sur tout l'historique"
exit 0
