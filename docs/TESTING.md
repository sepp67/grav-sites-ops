# Tests

Deux catégories, volontairement distinctes.

## 1. Batterie reproductible (CI + local)

Entièrement déterministe : aucune image, aucun conteneur, aucune connexion,
aucun identifiant. Exécutée par la CI (`.github/workflows/ci.yml`) et par
`make test-reproducible`.

| Test | Objet |
|---|---|
| `GSO-T01` | syntaxe YAML / Ansible / inventaires |
| `GSO-T02` | `ansible-lint` |
| `GSO-T03` | installation du rôle depuis `requirements.yml` |
| `GSO-T04` | référence du rôle épinglée sur un tag |
| `GSO-T05` | inventaire d'exemple parsable |
| `GSO-T06` | registre chargé automatiquement |
| `GSO-T07` | correspondance hôte–registre–vault d'exemple |
| `GSO-T08`–`T12` | sélecteur fermé + préflight (lecture seule) |
| `GSO-T13` | traduction registre + `grav_secrets` → `grav_*` (**doublure de rôle**) |
| `GSO-T14` | isolation des secrets, non-fuite, GSO-REQ-204 (**doublure**) |
| `GSO-T16` | deux sites : isolation à la traduction, **sans conteneur** (**doublure**) |
| `GSO-T23`, `GSO-T24` | contrôles statiques (control-repository, chemins, secrets) |
| `l4-concurrency-lock` | verrou de concurrence (**doublure de `ansible-playbook`**) |
| `l4-ci-functional-contract` | garde-fou : la CI ne tire ni ne référence `GSO-T15` |
| `l5-restart-stop` | `restart` / `stop` : intention → `grav_state`, 1 invocation, refus, verrou partagé, propagation des codes (**doublure de rôle**) |
| `l5-action-closed` | garde-fou statique : intentions fermées, `grav_state` jamais fourni par l'opérateur, aucune orchestration destructive, aucun nouvel identifiant GSO-T |
| `GSO-T19` | contrôle des trois états + classification de dérive (8 catégories §16.5), non-mutation, non-fuite (**fausse CLI `docker`**) |
| `GSO-T20` | `check-all` non mutant, sans `include_role` du rôle, cohérence déclarative sans VM, verdict de parc (**fausse CLI `docker`**) |
| `GSO-T17` | mise à jour A→B déclarative : image/version/digest exacts de B, digest non hybride, chemins persistants conservés (**doublure de rôle + dépôt Git jetable**) |
| `GSO-T18` | rollback B→A explicitement déclaré : séquence A→B→A, références committées et traçables, aucune restauration de contenu (**doublure**) |
| `l7-persistence-guard` | garde statique (CI) : aucune opération destructive de volume / répertoire persistant, aucun rollback automatique, aucune voie de surcharge CLI, aucun playbook/wrapper `update*`/`rollback*` (GSO-REQ-102) |
| `GSO-T21` | retrait déclaré sans tâche destructive : aucun playbook / script / cible de transformation, aucun appel d'hyperviseur, validateur read-only, transformation avant→après cohérente, données persistantes conservées (**fixtures synthétiques**) |
| `GSO-T22` | registres actif / retiré strictement disjoints y compris après réactivation : disjonction stricte, transformation de réactivation, **append-only inter-version** (9 cas : inchangé / ajout en fin / nouvelle clé acceptés ; suppression / modification / inversion / insertion / clé supprimée / remplacement refusés) (**fixtures synthétiques**) |
| `l8-history-append-only` | preuve **inter-version** : `scripts/lifecycle-history-check.sh` parcourt l'historique Git de `registry/reactivated-sites.yml` ; accepte l'historique réel + une transition d'ajout ; refuse réécriture / suppression ; **refuse explicitement un dépôt superficiel** ; tolère le commit initial |

Toutes les preuves L4–L8 « logiques » (traduction exacte, `name`+`content` sans
`src`, tri-state, une seule invocation, second contrôle de cible, non-fuite,
verrou partagé, `restart`/`stop` fermés, contrôle de dérive lecture seule,
mise à jour / rollback déclaratifs, gardes de persistance, disjonction du
cycle de vie) sont dans cette catégorie.

Le cycle de vie (L8) n'exécute **aucun** Docker, réseau ni connexion :
`GSO-T21` / `GSO-T22` construisent des états avant/après dans `mktemp` et
lancent le validateur **strictement en lecture seule** `gso_lifecycle.py`.
Aucun outil livré à l'opérateur n'applique une transformation de cycle de vie.

Le contrôle de dérive (L6) n'exécute **jamais** de vrai `docker` : `GSO-T19` et
`GSO-T20` utilisent une fausse CLI `docker` en lecture seule, qui **refuse
bruyamment** toute sous-commande mutante, et des `.deployed_state.yml`
synthétiques. Aucun conteneur, aucune connexion.

La mise à jour et le rollback (L7) sont des **usages déclaratifs de
`deploy-site.yml`** : `GSO-T17` / `GSO-T18` rejouent le vrai chemin `deploy`
avec la **doublure du rôle** et un dépôt Git jetable, éditant `grav_sites.yml`
entre chaque passage pour prouver la séquence A→B→A et la conservation des
chemins persistants. Le journal append-only produit par la doublure sert
**uniquement** à vérifier l'orchestration : la responsabilité réelle de
`.deployed_state.yml` / `deployed_versions.log` reste celle de
`sepp67.grav_site` (vérifiée par son propre contrat et par `GSO-T15`).

Les preuves L5, le garde `l7-persistence-guard` et
`l8-history-append-only` n'ont **pas** d'identifiant `GSO-Txx` : le préflight
ne prévoit de scénario `GSO-T` dédié ni pour L5, ni pour le garde de
persistance, ni pour la preuve inter-version (les deux `GSO-T` de L8 sont
`GSO-T21` / `GSO-T22`). Elles sont tracées comme preuves non numérotées
(`tests/l5-*.sh`, `tests/l7-*.sh`, `tests/l8-*.sh`).

## 2. Test d'acceptation fonctionnel local — `GSO-T15`

`GSO-T15` exécute le **vrai** chemin opérateur (`scripts/deploy.sh` →
`scripts/lib/site-mutation.sh` → sélecteur → verrou → `deploy-site.yml` →
`_shared/mutate.yml` : assertions → second préflight structurel → traduction
fermée → vrai rôle `sepp67.grav_site v2.0.0`) et crée **un** conteneur
`grav-runtime` **éphémère**, puis le détruit. `restart` et `stop` partagent ce
chemin ; L5 ne les exécute **jamais** sur un vrai conteneur.

**Non exécuté par la CI standard** : il exige une image déjà présente
localement, sans pull implicite ni identifiant GHCR (GSO-REQ-108).

### Lancement

```bash
make test-functional              # GSO-T15 seul
make test                         # batterie reproductible + GSO-T15 (gate locale complète)
bash tests/run-all.sh --functional
```

### Préconditions (sinon : ÉCHEC — jamais un SKIP, jamais un succès)

| Précondition | Vérification |
|---|---|
| Docker Engine + plugin `compose` opérationnels | `docker version`, `docker compose version` |
| Rôle `sepp67.grav_site` installé (`v2.0.0`) | `make install-role` |
| Collection `community.docker` installée (`>=5.0.0,<6.0.0`) | `make install-role` |
| Image de test **déjà présente localement** | `docker image inspect ghcr.io/sepp67/grav-runtime:1.0.4` |

### Image de test

- Référence : `ghcr.io/sepp67/grav-runtime` version `1.0.4`
- **Digest exact** :
  `sha256:d130f333c6566a26856c271656b21ce2d06793f9c4af24e620b53da14e4d640f`
- Déterminée par les sources approuvées : `ansible-role-grav-site`
  (`molecule/deploy`, `molecule/multi_instance`).
- `GSO-T15` déploie **par digest** (`image@sha256:…`) avec `grav_force_pull:
  false` → aucun pull si l'image est présente.
- Si l'image manque : la tirer **manuellement** et **par une référence
  nommée / épinglée par digest**, jamais `latest`. Aucune commande du dépôt ne
  tire d'image.

### Garanties du test

localhost + `ansible_connection=local` uniquement ; données, identifiants et
secrets synthétiques ; noms préfixés `gso-t15-` + suffixe unique ; publication
HTTP sur `127.0.0.1` + port de test sans collision ; répertoire `mktemp -d` ;
nettoyage en succès **comme en échec**, borné aux seules ressources créées ;
jamais de `docker … prune` ; vérification finale d'absence de conteneur,
réseau, fichier temporaire ou verrou résiduel.

### Obligation de release

`GSO-T15` **doit** être exécuté et vert avant toute future autorisation de
release (préparation de tag). Son résultat daté est consigné dans le rapport
d'exécution du lot concerné (et, à partir du lot L10, dans
`docs/TEST-RESULTS.md`).
