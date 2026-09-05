#!/usr/bin/env bash
# GSO-T04 — Reference du role epinglee sur un tag.
#
# Verifie que requirements.yml epingle sepp67.grav_site sur un tag de
# version explicite, sans branche flottante ni chemin local, et qu'il
# est l'unique source declarant cette reference (GSO-REQ-014,
# GSO-REQ-103, GSO-REQ-153).

TEST_ID="GSO-T04"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

python3 - "$REPO_ROOT/requirements.yml" <<'PY'
import re
import sys

try:
    import yaml
except ImportError:
    print("      | PyYAML absent", file=sys.stderr)
    sys.exit(2)

path = sys.argv[1]
with open(path, encoding="utf-8") as fh:
    data = yaml.safe_load(fh)

roles = (data or {}).get("roles") or []
if not roles:
    print("FAIL  requirements.yml ne declare aucun role")
    sys.exit(1)

forbidden = {"", "main", "master", "head", "devel", "latest", "stable"}
tag_re = re.compile(r"^v?\d+\.\d+\.\d+([.-][0-9A-Za-z.-]+)?$")
rc = 0
for role in roles:
    name = role.get("name", "<sans nom>")
    version = str(role.get("version", "")).strip()
    src = str(role.get("src", "")).strip()

    if version.lower() in forbidden or not tag_re.match(version):
        print(f"FAIL  {name}: version non epinglee sur un tag ({version!r})")
        rc = 1
    else:
        print(f"PASS  {name}: version epinglee sur le tag {version}")

    if src.startswith(("/", "file://", "../", "./")) or src.startswith("~"):
        print(f"FAIL  {name}: src ressemble a un chemin local ({src!r})")
        rc = 1
    elif not src:
        print(f"FAIL  {name}: src vide")
        rc = 1
    else:
        print(f"PASS  {name}: src distant ({src})")

sys.exit(rc)
PY
py_rc=$?
if [ "$py_rc" -eq 2 ]; then
  fail "impossible d'analyser requirements.yml (PyYAML manquant)"
  finish
elif [ "$py_rc" -ne 0 ]; then
  fail "requirements.yml : reference non conforme"
else
  pass "requirements.yml : reference epinglee et distante"
fi

# --- Unicite de la reference : aucun autre fichier ne declare la SOURCE/VERSION du role ---
# Nommer le role (sepp67.grav_site) dans le Makefile ou la doc est autorise ;
# seule une seconde declaration de src/version constitue une violation
# (GSO-REQ-153). On cherche donc l'URL de src et un pin de version explicite.
role_src_matches="$(git grep -lIE 'ansible-role-grav-site\.(git|tar|zip)|ansible-role-grav-site/(archive|releases)|grav_site.*version:[[:space:]]*.?v?[0-9]' -- \
  ':!requirements.yml' ':!tests/gso-t04-role-pinned.sh' ':!docs/' || true)"
if [ -n "$role_src_matches" ]; then
  fail "declaration de source/version du role hors requirements.yml :"
  printf '%s\n' "$role_src_matches" | sed 's/^/      | /'
else
  pass "requirements.yml est l'unique source de la version du role"
fi

# --- Coherence avec un role eventuellement installe localement ---
info_file="$REPO_ROOT/roles/sepp67.grav_site/meta/.galaxy_install_info"
if [ -f "$info_file" ]; then
  declared="$(python3 -c 'import sys,yaml; d=yaml.safe_load(open(sys.argv[1])); print(d["roles"][0]["version"])' "$REPO_ROOT/requirements.yml")"
  installed="$(grep -E '^version:' "$info_file" | awk '{print $2}')"
  if [ "$declared" = "$installed" ]; then
    pass "role installe localement en $installed = version declaree"
  else
    fail "role installe ($installed) different de la version declaree ($declared)"
  fi
else
  skip "aucun role installe localement (./roles absent)"
fi

finish
