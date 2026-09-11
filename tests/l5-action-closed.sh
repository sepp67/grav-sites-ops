#!/usr/bin/env bash
# L5 — Garde-fou statique : les intentions restart / stop sont fermées.
#
# L'opérateur ne fournit que SITE ; l'action est déterminée par le point
# d'entrée invoqué ; `grav_state` n'est jamais fourni par l'opérateur ;
# chaque intention a un playbook dédié ; aucune action implicite, combinée
# ou globale n'est introduite (GSO-REQ-081/082/088/089).

TEST_ID="L5-ACTION-CLOSED"
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=tests/lib/common.sh
. "$DIR/lib/common.sh"

cd "$REPO_ROOT"

code_only() { grep -vE '^[[:space:]]*#' "$1"; }

# --- 1. Les wrappers restart/stop ne prennent QUE SITE ---
# Capture d'abord (le `$( )` de `code_only` — un `grep -vE` externe — va à son
# terme), grep ensuite sur la valeur déjà capturée (here-string) — jamais
# `code_only "$f" | grep -q` : SIGPIPE possible sous `set -o pipefail` si un
# grep -q aval sort tôt -> faux négatif sur ce garde-fou.
for w in restart-site.sh stop-site.sh deploy.sh; do
  f="scripts/$w"
  fc="$(code_only "$f" || true)"
  if grep -qE '\[ "\$#" -eq 1 \]|"\$#" -ne 1' <<<"$fc"; then
    pass "$w : refuse tout argument autre que SITE"
  else
    fail "$w : ne borne pas le nombre d'arguments à 1"
  fi
  if grep -qE '"\$1"[^)]*$' <<<"$fc" \
     && ! grep -qE 'getopts|--(inventory|limit|root|state|extra-vars)|[[:space:]]-i[[:space:]]|-e[[:space:]]' <<<"$fc"; then
    pass "$w : ne parse aucune option"
  else
    fail "$w : parse des options"
  fi
done
# cas négatif synthétique (fichier temporaire, dépôt courant jamais touché) :
# un wrapper qui parse des options (getopts) DOIT être détecté.
_l5neg="$(gso_mktemp_dir l5-closed-neg)"
trap 'rm -rf "$_l5neg"' EXIT
printf '#!/usr/bin/env bash\nwhile getopts "i:" opt; do :; done\necho "$1"\n' > "$_l5neg/w.sh"
_neg_fc="$(code_only "$_l5neg/w.sh" || true)"
if grep -qE '"\$1"[^)]*$' <<<"$_neg_fc" \
   && ! grep -qE 'getopts|--(inventory|limit|root|state|extra-vars)|[[:space:]]-i[[:space:]]|-e[[:space:]]' <<<"$_neg_fc"; then
  fail "cas négatif : un wrapper synthétique utilisant getopts n'est PAS détecté comme parsant des options (faux négatif)"
else
  pass "cas négatif : un wrapper synthétique utilisant getopts est bien détecté comme parsant des options"
fi

# --- 2. site-mutation.sh valide le playbook contre une liste FERMÉE ---
if grep -qE 'deploy-site\.yml \| restart-site\.yml \| stop-site\.yml\)' scripts/lib/site-mutation.sh; then
  pass "site-mutation.sh : playbook validé contre une liste fermée (deploy/restart/stop)"
else
  fail "site-mutation.sh : pas de liste fermée de playbooks"
fi
# playbook arbitraire refusé
if bash scripts/lib/site-mutation.sh /etc/passwd grav-x >/dev/null 2>&1; then
  fail "site-mutation.sh a accepté un playbook arbitraire"
else
  pass "site-mutation.sh refuse un playbook hors liste"
fi

# --- 3. `grav_state` fixé UNIQUEMENT par la traduction, jamais par l'opérateur ---
# (hors commentaires : un commentaire de playbook a le droit de le nommer.)
stray=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ "$f" = "playbooks/_shared/translate.yml" ] && continue
  # capture d'abord, grep ensuite sur la valeur capturée (même motif que
  # ci-dessus : jamais `code_only "$f" | grep -q`).
  _fc="$(code_only "$f" || true)"
  if grep -qE 'grav_state[:=]' <<<"$_fc"; then stray="$stray $f"; fi
done < <(git ls-files 'playbooks/*' 'scripts/*')
if [ -z "$stray" ]; then
  pass "grav_state n'est assigné que dans playbooks/_shared/translate.yml"
else
  fail "grav_state assigné hors de la traduction :$stray"
fi
# cas négatif synthétique : une assignation grav_state: hors traduction DOIT
# être détectée par cette même logique.
_neg_state='grav_state: started'
grep -qE 'grav_state[:=]' <<<"$_neg_state" \
  && pass "cas négatif : une assignation grav_state: synthétique est bien détectée par cette logique" \
  || fail "cas négatif : une assignation grav_state: synthétique n'est PAS détectée (faux négatif)"
if grep -qE "grav_state: >-" playbooks/_shared/translate.yml \
   && grep -qE "_gso_intent == 'restart'" playbooks/_shared/translate.yml \
   && grep -qE "_gso_intent == 'stop'" playbooks/_shared/translate.yml; then
  pass "grav_state dérivé de l'intention fermée (restart→restarted, stop→stopped, sinon registre)"
else
  fail "grav_state n'est pas dérivé de l'intention"
fi

# --- 4. `_gso_intent` : ensemble fermé, imposé par assertion ---
if grep -qE "_gso_intent in \['deploy', 'restart', 'stop'\]" playbooks/_shared/translate.yml; then
  pass "_gso_intent contraint à {deploy, restart, stop} par assertion"
else
  fail "_gso_intent non contraint par assertion"
fi

# --- 5. Un playbook dédié par intention, chacun fixant _gso_intent ---
declare -A want=( [deploy-site.yml]=deploy [restart-site.yml]=restart [stop-site.yml]=stop )
for pb in "${!want[@]}"; do
  [ -f "playbooks/$pb" ] || { fail "playbook manquant : $pb"; continue; }
  if grep -qE "_gso_intent:[[:space:]]*${want[$pb]}\b" "playbooks/$pb" \
     && grep -qE 'include_tasks:[[:space:]]*_shared/mutate\.yml' "playbooks/$pb"; then
    pass "$pb : intention fixée à « ${want[$pb]} », séquence commune _shared/mutate.yml"
  else
    fail "$pb : intention ou séquence non conforme"
  fi
done

# --- 6. Une SEULE invocation du rôle (un include_role dans mutate.yml) ---
n="$(grep -cE 'include_role:' playbooks/_shared/mutate.yml || true)"
[ "$n" = 1 ] && pass "_shared/mutate.yml : un seul include_role du rôle (GSO-REQ-087)" || fail "$n include_role"

# --- 7. `stop` : aucune orchestration destructive ---
if git grep -nIE 'state:[[:space:]]*absent|\.down\b|--volumes|remove_volumes|remove_orphans|docker[[:space:]]+rm|prune|rm -rf' -- playbooks/ ; then
  fail "orchestration destructive dans les playbooks"
else
  pass "playbooks : aucune tâche de suppression de conteneur / volume / répertoire (GSO-REQ-089)"
fi

# --- 8. `restart` n'est PAS présenté comme un redéploiement / une mise à jour ---
if grep -iE 'redéploiement|redeploy|mise à jour|update|nouvelle version' playbooks/restart-site.yml scripts/restart-site.sh \
   | grep -viE 'ni.*mise à jour|jamais|sans.*mise à jour|pas.*redéploiement|SANS changer'; then
  fail "restart présenté comme un redéploiement / une mise à jour"
else
  pass "restart : décrit comme un simple redémarrage (ni redéploiement, ni mise à jour)"
fi

# --- 9. Aucune action implicite / combinée / globale ; aucun nouveau GSO-T ---
if git grep -qIE 'deploy-all|restart-all|stop-all|hosts:[[:space:]]*all\b' -- playbooks/ scripts/; then
  fail "action globale ou combinée introduite"
else
  pass "aucune action implicite, combinée ou globale"
fi
# Ensemble FERMÉ des identifiants GSO-T du contrat (§18.2) : gso-t01..gso-t24.
# Aucun test ne doit inventer un identifiant hors de cette liste (ex. gso-t25).
known="gso-t01 gso-t02 gso-t03 gso-t04 gso-t05 gso-t06 gso-t07 gso-t08 gso-t09 gso-t10 gso-t11 gso-t12 gso-t13 gso-t14 gso-t15 gso-t16 gso-t17 gso-t18 gso-t19 gso-t20 gso-t21 gso-t22 gso-t23 gso-t24"
extra=""
while IFS= read -r f; do
  id="$(basename "$f" | grep -oE '^gso-t[0-9]+')"
  case " $known " in *" $id "*) : ;; *) extra="$extra $id" ;; esac
done < <(git ls-files 'tests/gso-t*.sh')
if [ -z "$extra" ]; then
  pass "aucun nouvel identifiant GSO-T inventé (preuves L5 : l5-*.sh)"
else
  fail "identifiant(s) GSO-T non prévu(s) :$extra"
fi

# --- 10. deploy / restart / stop empruntent le MÊME chemin ---
if grep -qE 'site-mutation\.sh"? +deploy-site\.yml' scripts/deploy.sh \
   && grep -qE 'site-mutation\.sh"? +restart-site\.yml' scripts/restart-site.sh \
   && grep -qE 'site-mutation\.sh"? +stop-site\.yml' scripts/stop-site.sh; then
  pass "les trois intentions passent par scripts/lib/site-mutation.sh (même sélecteur, même verrou)"
else
  fail "les trois intentions n'empruntent pas le même chemin"
fi

finish
