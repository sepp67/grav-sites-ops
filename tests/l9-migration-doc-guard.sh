#!/usr/bin/env bash
# L9 — Garde-fou de la migration DOCUMENTAIRE (preuve non numérotée : le
# préflight §6 n'attribue AUCUN GSO-T à L9 — « aucun GSO-T supplémentaire,
# aucun GSO-T25 »). Preuve probatoire, cohérente avec la convention
# l4-concurrency-lock / l7-persistence-guard / l8-history-append-only.
#
# 100 % local, déterministe, sans Docker / réseau / connexion / vault réel.
# Prouve (contrat §20 ; GSO-REQ-070/133/160-172) :
#   - docs/MIGRATION.md contient TOUTES les étapes obligatoires ;
#   - traitement site par site ; migration globale interdite ;
#   - sauvegarde vérifiée du vault décrite AVANT toute transformation
#     (chemin hors dépôt, permissions, checksum avant/après, vérification
#     Ansible Vault sans fuite, conservation séparée, exclusion Git, arrêt
#     si échec) ;
#   - cartographie exhaustive des champs connus + détection des champs non
#     mappés ;
#   - protection des chemins structurants ;
#   - conservation des données persistantes ;
#   - distinction migration / mise à jour / rollback d'image ;
#   - procédure de retour arrière NON destructive, sans script ;
#   - AUCUN script / playbook / cible Makefile n'applique la migration ;
#   - AUCUN fichier d'exécution ne lit l'ancien dépôt (GSO-REQ-170) ;
#   - la CIBLE synthétique de migration valide contre les validateurs du
#     contrat (réutilisation GSO-T06/T07/T13 sur données synthétiques) ;
#   - aucun nouvel identifiant GSO-T.

TEST_ID="L9-MIGRATION-DOC-GUARD"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

tmp="$(gso_mktemp_dir l9-migration)"
trap 'rm -rf "$tmp"' EXIT
gso_isolate_runtime "$tmp"

M="docs/MIGRATION.md"
OLD="tests/fixtures/l9-old-profile"
NEW="tests/fixtures/l9-migrated"
GV="$REPO_ROOT/scripts/lib/gso_validate.py"

has() {  # <regex> <libellé>
  if grep -qiE "$1" "$M"; then pass "MIGRATION.md : $2"; else fail "MIGRATION.md : ABSENT — $2"; fi
}

# --------------------------------------------------------------------------
# 1. docs/MIGRATION.md — étapes obligatoires présentes
# --------------------------------------------------------------------------
[ -f "$M" ] && pass "$M existe" || { fail "$M absent"; finish; }

has 'harnais.*vert|test-reproducible.*vert|GSO-REQ-163' "précondition harnais vert avant données réelles (GSO-REQ-163)"
has 'inventaire.*existant|diagnostic de l.existant|GSO-REQ-162' "inventaire / diagnostic de l'existant (GSO-REQ-162)"
has 'sauvegarde.*(externe|vérifiée).*vault|vault.*sauvegarde' "sauvegarde vérifiée du vault (GSO-REQ-070/161)"
has 'cartographie|traduction explicite|GSO-REQ-164' "cartographie ancien -> nouveau (GSO-REQ-164)"
has 'chemins? structurants?' "chemins structurants"
has 'site par site|un site à la fois|une (migration )?à la fois|GSO-REQ-167' "migration site par site (GSO-REQ-167)"
has 'nouveau vault|création.*vault' "création + vérification du nouveau vault (GSO-REQ-165/166)"
has 'validations? statiques?|préflight statique|make (validate|preflight)' "validations statiques"
has 'revue humaine' "revue humaine"
has 'autorisation.*(premier )?déploiement|gate humain' "autorisation du premier déploiement"
has 'déploiement de validation|GSO-REQ-168|sans (upgrade|montée de version) implicite' "déploiement de validation sans upgrade implicite (GSO-REQ-168)"
has 'après (le )?déploiement|trois états|IN_SYNC' "vérification après déploiement"
has 'critères de fin|migration.*terminée|GSO-REQ-170|autonomie' "critères de fin + autonomie finale (GSO-REQ-170)"
has 'rapport de migration|verdict.*(par site|daté)|GSO-REQ-171' "rapport de migration, un verdict par site (GSO-REQ-171)"
has 'retour arrière|GSO-REQ-172' "retour arrière de la migration (GSO-REQ-172)"
has 'ancien vault.*(conservé|après)|nettoyage.*séparé|GSO-REQ-169' "ancien profil conservé, nettoyage séparé (GSO-REQ-169)"
has 'non-destruction|copie contrôlée|GSO-REQ-160|jamais.*supprim' "principe de non-destruction (GSO-REQ-160)"

# --------------------------------------------------------------------------
# 2. Sauvegarde du vault — exigences détaillées (§20.3)
# --------------------------------------------------------------------------
has 'hors des deux dépôts|hors dépôt|hors du dépôt|HORS des deux' "sauvegarde à un chemin hors des dépôts"
has 'chmod (600|400)|permissions restrictives|umask 077' "permissions restrictives sur la sauvegarde"
has 'sha256sum|somme de contrôle|checksum' "somme de contrôle avant / après"
has 'ansible-vault view|déchiffrable|lisibilité' "vérification Ansible Vault sans afficher le contenu"
has 'sans afficher|jamais.*afficher|aucune valeur affichée|sans divulgation' "aucun affichage de valeur secrète"
has 'conservation séparée|conservée? (hors|séparé)' "conservation séparée de la sauvegarde"
has 'ignor(é|e|er).*Git|git check-ignore|exclusion Git|jamais.*suivi' "interdiction de suivre la sauvegarde dans Git"
has 'arrêt (immédiat|avant)|s.arrêter|ne pas poursuivre|bloqu' "arrêt immédiat si la vérification échoue"

# --------------------------------------------------------------------------
# 3. Cartographie — champs connus + champ non mappé
# --------------------------------------------------------------------------
for f in inventory_hostname ansible_host grav_image grav_version digest \
         container_name base_directory bind_address http_port state \
         admin_user admin_password admin_email grav_secrets; do
  grep -q "$f" "$M" && pass "cartographie mentionne \`$f\`" || fail "cartographie : \`$f\` absent"
done
has 'name.*\+.*content|name` \+ `content|format name' "secrets migrés au format name + content (jamais src)"
has 'sans correspondance|non mappé|décision humaine documentée|classé.*obsolète' "champ non mappé -> décision humaine documentée (GSO-REQ-164)"
has 'jamais.*recopi|jamais.*réinitialis|données persistantes.*conserv|volumes.*inchang' "données persistantes conservées, jamais recopiées (GSO-REQ-133)"

# --------------------------------------------------------------------------
# 4. Chemins structurants (les six éléments)
# --------------------------------------------------------------------------
for e in "identité de l.hôte" "container_name" "base_directory" "port d.exposition" "données persistantes" "vault"; do
  grep -qiE "$e" "$M" && pass "chemin structurant : $e" || fail "chemin structurant absent : $e"
done
has 'jamais.*modifié.*silencieux|jamais.*silencieusement|désolidaris' "chemins structurants jamais modifiés silencieusement"

# --------------------------------------------------------------------------
# 5. Retour arrière — distinct de L7, non destructif, sans script
# --------------------------------------------------------------------------
has 'distinct.*(rollback|lot L7)|≠ rollback|rollback d.image \(lot L7\)' "retour arrière distinct du rollback d'image L7"
has 'aucun script.*(applique|automatiquement).*retour|manuel' "aucun script n'applique le retour arrière"
has 'point de non-retour' "point de non-retour documenté"
has 'sans (supprimer|détruire).*(donnée|volume)|aucune destruction' "retour arrière sans destruction de données"

# --------------------------------------------------------------------------
# 6. AUCUN outil de migration livré
# --------------------------------------------------------------------------
if git ls-files 'playbooks/*' | grep -iE 'migrat'; then
  fail "un playbook de migration a été livré"
else
  pass "aucun playbook de migration (playbooks/)"
fi
if git ls-files 'scripts/*' | grep -iE 'migrat'; then
  fail "un script de migration a été livré"
else
  pass "aucun script de migration (scripts/)"
fi
if grep -nE '^[a-z][a-z-]*:.*migrat|migrate' Makefile; then
  fail "une cible Makefile de migration a été livrée"
else
  pass "aucune cible Makefile de migration"
fi

# --------------------------------------------------------------------------
# 7. GSO-REQ-170 : aucun fichier d'exécution ne LIT l'ancien dépôt local
#    (le rôle publié consommé par requirements.yml via une URL Git épinglée
#    n'est PAS l'ancien profil — c'est la dépendance normative, GSO-REQ-153).
# --------------------------------------------------------------------------
if git grep -nIE '(\.\.?/)+2B?-ansible-role-grav|(\.\.?/)+2-ansible-role-grav|group_vars/grav_servers|ansible-role-grav-site/inventories|ansible-role-grav-lavallee' \
     -- 'playbooks/*' 'scripts/*' 'Makefile' 'ansible.cfg' '.github/*' \
     ':!tests/**' ; then
  fail "un fichier d'exécution / config lit l'ancien dépôt LOCAL du rôle (GSO-REQ-170)"
else
  pass "aucun fichier d'exécution ne lit l'ancien dépôt local du rôle (GSO-REQ-170)"
fi

# GSO-REQ-133 : aucun playbook/template/tâche du rôle recopié
if git ls-files 'playbooks/*' 'roles/*' 2>/dev/null | grep -iE 'deploy\.yml$|healthcheck|verify_docker|admin_guard|molecule'; then
  fail "un artefact du rôle a été recopié (GSO-REQ-133)"
else
  pass "aucun playbook / tâche / molecule du rôle recopié (GSO-REQ-133)"
fi

# --------------------------------------------------------------------------
# 8. Fixtures synthétiques : ancien plat vs nouveau indexé, cible valide
# --------------------------------------------------------------------------
python3 -c '
import yaml, sys
old = yaml.safe_load(open(sys.argv[1]))
assert "grav_image" in old and "grav_version" in old, "ancien profil : forme plate attendue"
assert "grav_sites" not in old, "ancien profil ne doit PAS être déjà indexé"
assert "legacy_smtp_relay" in old, "le champ non mappé de démonstration doit être présent"
' "$OLD/group_vars/grav_servers/main.yml" \
  && pass "fixture ancien profil : forme plate grav_image/grav_version (non indexée), avec un champ non mappé" \
  || fail "fixture ancien profil mal formée"

python3 -c '
import yaml, sys
new = yaml.safe_load(open(sys.argv[1]))["grav_sites"]["old-lavallee"]
assert new["image"].endswith("old-lavallee") and new["version"] == "1.0.3"
assert new["container_name"] == "old-lavallee" and new["base_directory"] == "/opt/old-lavallee"
assert new["http_port"] == 8080 and new["state"] == "started" and new["digest"] == ""
' "$NEW/inventories/production/group_vars/all/grav_sites.yml" \
  && pass "fixture cible : cartographie appliquée (image/version/container/base_dir/port/state/digest)" \
  || fail "fixture cible : cartographie incohérente"

# identité d'hôte préservée entre ancien et nouveau (GSO-REQ-180 / §5)
oh="$(python3 -c 'import yaml,sys;print(list(yaml.safe_load(open(sys.argv[1]))["all"]["children"]["grav_servers"]["hosts"])[0])' "$OLD/hosts.yml")"
nh="$(python3 -c 'import yaml,sys;print(list(yaml.safe_load(open(sys.argv[1]))["all"]["children"]["grav_servers"]["hosts"])[0])' "$NEW/inventories/production/hosts.yml")"
[ "$oh" = "$nh" ] && pass "identité d'hôte préservée par la migration ($oh)" || fail "identité d'hôte changée ($oh -> $nh)"

# la CIBLE valide contre le validateur de registre du contrat (réutilise GSO-T06/T07)
if python3 "$GV" registry --inventory "$NEW/inventories/production/hosts.yml" --context production > "$tmp/reg.out" 2>&1; then
  pass "cible synthétique : registre migré VALIDE (gso_validate.py registry — réutilisation GSO-T06/T07)"
else
  sed 's/^/   | /' "$tmp/reg.out" | grep FAIL; fail "la cible migrée ne valide pas"
fi

# un vault migré synthétique (indirections résolues) valide contre gso_validate.py vault
mkdir -p "$tmp/mig/inventories/production/group_vars/all"
cp "$NEW/inventories/production/hosts.yml" "$tmp/mig/inventories/production/hosts.yml"
cp "$NEW/inventories/production/group_vars/all/grav_sites.yml" "$tmp/mig/inventories/production/group_vars/all/grav_sites.yml"
cat > "$tmp/mig/inventories/production/group_vars/all/vault.yml.example" <<'YML'
vault_grav_sites:
  old-lavallee:
    admin_user: SYNTH-L9-ADMIN-USER
    admin_password: SYNTH-L9-ADMIN-PW
    admin_email: admin@example.invalid
    admin_fullname: SYNTH-L9-FULLNAME
    admin_language: fr
    secrets:
      - name: email-private.php
        content: "SYNTH-L9-EMAIL-PRIVATE"
vault_retired_grav_sites: {}
YML
if python3 "$GV" vault --inventory "$tmp/mig/inventories/production/hosts.yml" > "$tmp/vault.out" 2>&1; then
  pass "cible synthétique : vault migré (indirections résolues, name+content) VALIDE (réutilisation GSO-T07/T13)"
else
  sed 's/^/   | /' "$tmp/vault.out" | grep FAIL; fail "le vault migré synthétique ne valide pas"
fi
grep -qE 'SYNTH-L9' "$tmp/reg.out" "$tmp/vault.out" && fail "fuite d'un marqueur synthétique dans la sortie" \
  || pass "aucun marqueur synthétique dans les sorties de validation"

# --------------------------------------------------------------------------
# 9. Aucun nouvel identifiant GSO-T ; aucun vault réel touché
# --------------------------------------------------------------------------
# Capture D'ABORD (le `$( )` attend la fin normale de `git ls-files`), puis
# recherche dans la valeur déjà capturée (here-string) — jamais
# `git ls-files | grep -q` : sous `set -o pipefail`, un `grep -q` qui sort
# dès la 1re ligne trouvée fait recevoir SIGPIPE à `git` -> pipeline en échec
# ALORS QUE grep a trouvé la ligne -> faux négatif possible.
_gsot_files="$(git ls-files 'tests/gso-t*.sh')"; _grc=$?
if [ "$_grc" -ne 0 ]; then
  fail "git ls-files a échoué (rc=$_grc) — impossible de vérifier les identifiants GSO-T"
elif grep -qE 'gso-t2[5-9]|gso-t[3-9][0-9]' <<<"$_gsot_files"; then
  fail "un identifiant GSO-T hors contrat a été créé"
else
  pass "aucun nouvel identifiant GSO-T (preuve L9 : l9-*.sh, non numérotée)"
fi
# --- cas négatif synthétique (copie temporaire, dépôt courant jamais touché) :
# un identifiant hors contrat DOIT être refusé par la même logique corrigée.
_neg="$tmp/sigpipe-neg-t9"; mkdir -p "$_neg/tests"
git -C "$_neg" init -q
: > "$_neg/tests/gso-t30-hors-contrat.sh"
git -C "$_neg" -c user.email=t@t -c user.name=t add -A >/dev/null
git -C "$_neg" -c user.email=t@t -c user.name=t commit -qm "cas négatif"
_neg_files="$(git -C "$_neg" ls-files 'tests/gso-t*.sh')"
if grep -qE 'gso-t2[5-9]|gso-t[3-9][0-9]' <<<"$_neg_files"; then
  pass "cas négatif : un identifiant GSO-T hors contrat (gso-t30) est bien détecté par cette logique"
else
  fail "cas négatif : un identifiant GSO-T hors contrat n'est PAS détecté (faux négatif)"
fi
# motif de chemin home assemblé pour que ce test ne se signale pas à GSO-T24
_hp="/${_h1:-ho}${_h2:-me}/"
if git grep -qnIE "ansible-vault (view|decrypt|edit).*production/group_vars/grav_servers|${_hp}.*vault\.ya?ml" -- tests/ scripts/ playbooks/ ; then
  fail "un fichier suivi lit ou déchiffre un vault opérationnel"
else
  pass "aucun fichier suivi ne lit / déchiffre un vault opérationnel"
fi

# --------------------------------------------------------------------------
# 10. Fixtures et dépôt inchangés ; aucun résidu
# --------------------------------------------------------------------------
# Comparaison avant / après (gso_isolate_runtime a pris l'empreinte au début) :
# n'exige pas un working tree vierge, seulement que CE test ne modifie rien.
gso_assert_runtime_clean
finish
