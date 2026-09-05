#!/usr/bin/env bash
# GSO-T03 — Installation du role depuis requirements.yml.
#
# Installe sepp67.grav_site dans un repertoire temporaire propre, sans
# aucun lien local vers le depot du role (GSO-REQ-059, GSO-REQ-140).
# Necessite un acces reseau a GitHub.

TEST_ID="GSO-T03"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

if [ ! -f requirements.yml ]; then
  fail "requirements.yml absent"
  finish
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if ansible-galaxy role install -r requirements.yml -p "$tmp" >"$tmp/out.log" 2>&1; then
  pass "ansible-galaxy role install (code 0)"
else
  sed 's/^/      | /' "$tmp/out.log"
  fail "echec de l'installation du role"
  finish
fi

if [ -d "$tmp/sepp67.grav_site" ] && [ -f "$tmp/sepp67.grav_site/meta/main.yml" ]; then
  pass "role installe sous le nom sepp67.grav_site"
else
  fail "sepp67.grav_site/meta/main.yml introuvable apres installation"
fi

info_file="$tmp/sepp67.grav_site/meta/.galaxy_install_info"
if [ -f "$info_file" ]; then
  installed_version="$(grep -E '^version:' "$info_file" | awk '{print $2}')"
  info "version installee : ${installed_version:-inconnue}"
fi

finish
