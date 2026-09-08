# Exploitation

Résumé normatif : contrat architectural `v0.5.0`, sections 8.5, 13 et 14
(`docs/CONTRAT-ARCHITECTURAL.md`). En cas de divergence, le contrat fait foi.

Livré par les **lots L3** (sélecteur fermé, préflight lecture seule), **L4**
(déploiement d'un site), **L5** (redémarrage, arrêt), **L6** (contrôle de
dérive, `check` / `check-all`, lecture seule), **L7** (procédures
déclaratives de mise à jour et de rollback, gardes de persistance), **L8**
(cycle de vie documentaire : retrait, réactivation, validateur lecture seule)
et **L9** (migration documentaire site par site — voir
[`MIGRATION.md`](MIGRATION.md)).

## Interface opérateur

| Commande | Effet | Mutation |
|---|---|---|
| `make validate SITE=<hôte>` | sélecteur fermé : valide que `SITE` désigne un hôte actif unique | aucune |
| `make preflight SITE=<hôte>` | sélecteur + cohérence inventaire ↔ registre ↔ vault | aucune |
| `make deploy SITE=<hôte>` | **déploie / actualise** l'instance de `<hôte>` selon le registre | oui (via le rôle) |
| `make restart SITE=<hôte>` | **redémarre** l'instance **sans** changer sa référence désirée (GSO-REQ-088) | oui (via le rôle) |
| `make stop SITE=<hôte>` | **arrête** le conteneur, sans rien supprimer ni retirer du parc (GSO-REQ-089) | oui (via le rôle) |
| `make check SITE=<hôte>` | **compare** désiré / appliqué / réel de `<hôte>` et **classe** la dérive (§16.5) | **aucune** (lecture seule) |
| `make check-all` | même contrôle sur **tout le parc actif** (`grav_servers`) | **aucune** (lecture seule) |
| `scripts/{validate-target,preflight,deploy,restart-site,stop-site,check-site}.sh <hôte>`, `scripts/check-all.sh` | idem, sans `make` | — |

Les cibles ciblées n'acceptent que `SITE` ; `check-all` n'accepte **aucun**
argument. **`grav_state` n'est jamais fourni par l'opérateur** : l'action est
déterminée par le point d'entrée invoqué (`deploy` → état du registre ;
`restart` → `restarted` ; `stop` → `stopped`). Le contrôle ne fournit ni ne
modifie aucun état.

## Les trois intentions de mutation (lots L4–L5)

`deploy`, `restart` et `stop` partagent **le même chemin** et **le même
verrou** (`scripts/lib/site-mutation.sh`). Elles ne diffèrent que par le
playbook dédié invoqué et par l'état traduit. `make <intention> SITE=<hôte>`
→ `scripts/<wrapper>.sh` exécute **strictement dans cet ordre** :

```
SITE littéral
  └─▶ 1. préflight local / sélecteur    scripts/validate-target.sh (sélecteur fermé L3)
  └─▶ 2. verrou de concurrence          flock par site (GSO-REQ-096)
  └─▶ 3. ansible-playbook <intention>-site.yml --limit <hôte>  (deploy- / restart- / stop-),
          play qui fixe _gso_intent, puis _shared/mutate.yml :
          ├─ 3a. assertions du playbook       --limit == inventory_hostname,
          │        un seul hôte, jamais all/groupe/multiple (GSO-REQ-016/017/057/082/094)
          ├─ 3b. second préflight structurel  gso_validate.py preflight <hôte>
          │        (registre + vault + bootstrap tri-state + secrets, no_log — GSO-REQ-204)
          ├─ 3c. traduction fermée            _gso_intent + grav_sites[hôte] + vault_grav_sites[hôte]
          │        → grav_* + grav_state (exacte, aucune valeur globale, aucun repli)
          └─▶ 4. include_role: sepp67.grav_site   — exactement une fois (GSO-REQ-087)
```

Le **préflight local** (étape 1, `scripts/validate-target.sh`) et le **second
préflight structurel** (étape 3b, tâche du playbook) sont deux contrôles
distincts : le premier valide l'identité de la cible avant même le verrou ; le
second revalide, à l'intérieur du play et juste avant la traduction, la
cohérence structurelle des données de l'hôte sélectionné (GSO-REQ-085, préflight
à deux niveaux).

Règles impératives :

- **aucune** invocation du rôle avant réussite du préflight local **et** des
  assertions du playbook (`any_errors_fatal`) ;
- `--limit` vaut **exactement** le littéral `SITE` validé ; une valeur globale,
  multiple, vide ou différente de l'hôte courant fait échouer le playbook avant
  toute mutation ;
- accès au registre **uniquement** par `grav_sites[inventory_hostname]`, aux
  secrets **uniquement** par `vault_grav_sites[inventory_hostname]` — aucun
  `grav_site_target`, aucun repli ;
- `grav_secrets` transmis **tel quel** (`name` + `content`), **jamais** `src` ;
- bootstrap administrateur **tri-state** (0 ou 3 identifiants) ;
- `no_log` sur toute tâche manipulant une valeur secrète ; aucune valeur secrète
  dans les logs, erreurs, commandes ou rapports (GSO-REQ-024/092/101) ;
- verrou acquis avant toute mutation, **libéré de façon fiable** (le noyau
  ferme le descripteur `flock` en succès, échec ou interruption) ; une tentative
  concurrente échoue proprement (code 75) **sans** lancer le rôle ;
- aucune fonctionnalité de rotation d'identifiants n'est déclarée ni simulée
  (GSO-REQ-071).

L'inventaire de production reste **fourni hors dépôt** : `make deploy` échoue
tant qu'`inventories/production/hosts.yml` n'existe pas.

## Le sélecteur fermé

`SITE` est l'identifiant **exact** d'un hôte d'inventaire. Il est transmis
ensuite à Ansible comme `--limit`, entre guillemets, **sans réinterprétation
par le shell** (GSO-REQ-084).

Règles (toutes vérifiées avant toute opération, échec = code ≠ 0) :

1. `SITE` présent et non vide (GSO-REQ-083).
2. `SITE` respecte **exactement** `^[a-z][a-z0-9-]*$` — aucune majuscule, aucun
   espace, aucune virgule, aucun deux-points, aucun `/`, `*`, `?`, `[`, `..`,
   `$`, backtick, `;`, `|`, `_` … (GSO-REQ-084, GSO-REQ-138).
3. `SITE` n'est jamais une cible globale : `all`, `*`, un nom de groupe
   (`grav_servers`, `ungrouped`), `localhost` sont refusés (GSO-REQ-138 ; §14.1).
4. La racine du dépôt et l'inventaire (`inventories/production/hosts.yml`) sont
   déterminés **exclusivement** depuis l'emplacement canonique du script
   (`scripts/lib/gso_validate.py`, via `realpath`). Ils ne dépendent **ni** du
   répertoire courant, **ni** d'une option (`-i`, `--inventory`, `--limit`,
   `--root` — toutes rejetées), **ni** d'une variable d'environnement. Le seul
   argument accepté par `validate-target.sh` / `preflight.sh` est `SITE`
   (GSO-REQ-053).
5. `SITE` résout **exactement un** hôte du groupe `grav_servers`
   (GSO-REQ-017, GSO-REQ-057). Un hôte absent → échec (GSO-REQ-086,
   GSO-REQ-056), jamais un « succès vide ».
6. `SITE` possède une entrée dans le registre actif `grav_sites`, et
   l'ensemble inventaire ↔ registre est cohérent (validateur partagé, mêmes
   règles qu'à L1).
7. `SITE` n'est **pas** un projet retiré (`registry/retired-sites.yml`) —
   disjonction stricte (GSO-REQ-052).
8. Lorsqu'un modèle de vault en clair est résolvable, `SITE` possède une
   entrée `vault_grav_sites` cohérente (mêmes règles qu'à L2). Le contrôle de
   vault opérationnel **avant déploiement** relève du préflight de déploiement
   (lot L4, GSO-REQ-204).

En cas de succès, le sélecteur écrit `TARGET <hôte>` sur la sortie standard :
la valeur à passer à `--limit`.

## Le préflight opérateur

`scripts/preflight.sh` = sélecteur + réutilisation des validateurs de registre
et de vault (**une seule implémentation** : `scripts/lib/gso_validate.py`).

Ordre (contrat §14.2) :

1. contrôles locaux de dépôt et de paramètres ;
2. résolution de l'inventaire imposé ;
3. validation de la cible unique ;
4. cohérence structurelle inventaire ↔ registre ↔ vault, **sans afficher de
   valeur** ;
5. *(lots ultérieurs)* validation des valeurs non secrètes, connexion à la VM,
   invocation du rôle.

Le préflight est **strictement en lecture seule** : il ne déploie rien,
n'ouvre aucun vault chiffré, ne contacte aucune machine, ne modifie aucun
fichier. Il **échoue fermé** : toute ambiguïté ou incohérence → code ≠ 0,
avant toute opération mutante (GSO-REQ-026, 038, 094, 095, 107).

## Action (lots L4–L6)

Le sélecteur L3 est **agnostique de l'action** : il valide une identité de
cible, pas ce qu'on va en faire. La liste **fermée** des actions opérateur
normatives est `deploy`, `restart`, `stop`, `check` (contrat §13.1 ; constante
`NORMATIVE_ACTIONS` dans `scripts/lib/gso_validate.py`). L'action n'est **jamais
une option** : elle est déterminée par le point d'entrée invoqué
(`scripts/deploy.sh`, `scripts/restart-site.sh`, `scripts/stop-site.sh`,
`scripts/check-site.sh`, `scripts/check-all.sh`), qui fixe le playbook dédié.
L'opérateur ne peut pas fournir `grav_state`, `--limit`, `-e`, ni aucune option
d'inventaire.

`grav_state` est traduit **depuis l'intention seule** (`playbooks/_shared/translate.yml`) :
`restart` → `restarted`, `stop` → `stopped`, `deploy` → l'état du registre. Le
`restart` ne change **ni** version **ni** digest **ni** aucun fichier
persistant (GSO-REQ-088) ; il n'est **pas** un redéploiement. Le `stop`
n'entraîne **aucune** suppression de conteneur, volume, donnée persistante ou
fichier de déploiement (GSO-REQ-089).

Un site à l'état désiré `stopped` reste un **projet actif** du registre : il
est une cible d'identité légitime pour les trois intentions.

## Mise à jour et rollback (lot L7) — usages déclaratifs de `deploy`

La mise à jour et le rollback **ne sont pas des intentions techniques** ni des
playbooks : ce sont **deux usages déclaratifs de `deploy-site.yml`** (contrat
§13.1 — interface fermée ; §15.1 / §15.4). Il n'existe **aucun**
`update-site.yml`, `rollback-site.yml`, `make update`, `make rollback`, ni
`_gso_intent` de mise à jour ou de rollback.

### Procédure de mise à jour (contrat §15.1)

```
1. identifier la nouvelle image applicative publiée (version, digest éventuel)
2. modifier l'entrée du site dans grav_sites.yml (registre)
3. examiner le diff Git
4. committer la décision
5. make check SITE=<hôte>          (vérifier l'écart avant d'agir)
6. make deploy SITE=<hôte>         (appliquer exactement l'état déclaré)
7. make check SITE=<hôte>          (confirmer désiré = appliqué = réel — GSO-REQ-116/118)
```

### Procédure de rollback (contrat §15.4 — « suit le même chemin qu'une mise à jour »)

```
1. identifier la dernière référence applicative connue comme SAINE
2. re-déclarer EXPLICITEMENT `version` (et le cas échéant `digest`) dans grav_sites.yml
3. examiner le diff Git puis committer la décision de rollback
4. make check SITE=<hôte>
5. make deploy SITE=<hôte>
6. make check SITE=<hôte>
```

Le rollback **n'est pas** une action CLI, **ne choisit pas** dans l'historique
Docker, **ne déduit pas** automatiquement une version antérieure, **n'accepte
aucune** surcharge `--version` / `--digest` / `--image` / `--extra-vars`
(GSO-REQ-109) et **ne dépend d'aucun tag flottant**. `version` et `digest`
proviennent **exclusivement** du registre committé (`translate.yml` :
`_reg.version`, `_reg.digest`), transmis **séparément** au rôle qui construit
la référence effective — l'orchestrateur ne reconstruit **jamais** une
référence hybride `image:version@digest` (GSO-REQ-110). Un rollback vers le
**même digest** mais une **version humaine différente** reste une déclaration
distincte, explicite et tracée.

Un échec de mise à jour **ne déclenche aucun rollback automatique**
(GSO-REQ-114) : la procédure s'arrête, l'opérateur analyse les diagnostics du
rôle. Chaque application produit une nouvelle entrée dans le journal du rôle ;
`grav-sites-ops` **ne tronque ni ne réécrit** ce journal (GSO-REQ-117).

### Persistance — image ≠ contenu

> Le rollback logiciel rétablit une version déclarée de l'image. Les données
> persistantes restent dans leur état courant. Une restauration de contenu
> constitue une opération différente, hors du rollback applicatif automatique.

Aucune opération `grav-sites-ops` (déploiement, mise à jour, redémarrage,
arrêt, rollback) ne supprime un volume, ne recrée un répertoire persistant à
vide, n'efface `pages` / `accounts` / `data` / `images`, ne supprime les
secrets applicatifs, n'exécute `docker compose down --volumes` / `docker
volume rm` / `prune` / `rm -rf` d'un chemin persistant, ni ne restaure
automatiquement une sauvegarde (GSO-REQ-040/075/076/077/078/079/113). Les
quatre chemins persistants (`{base_directory}/data/{pages,accounts,data,images}`)
et `{base_directory}/secrets` sont dérivés par le rôle de `grav_base_directory`
seul ; l'orchestrateur ne transmet **aucun** sous-chemin ni drapeau de
restauration. Un changement de `base_directory` ou `container_name` dans le
registre **n'est pas** une mise à jour applicative banale (GSO-REQ-176).

Le garde-fou statique `tests/l7-persistence-guard.sh` (exécuté par la CI —
GSO-REQ-102) recherche ces opérations interdites dans les playbooks, scripts
et cibles Makefile.

## Contrôle de dérive (lot L6)

`check` et `check-all` sont **strictement en lecture seule** (contrat §13.7,
§16 ; GSO-REQ-090/119/122). Ils comparent les **trois niveaux d'état** et
**classent** l'écart, sans jamais corriger.

| Niveau | Source | Collecte |
|---|---|---|
| désiré | `grav_sites[<hôte>]` au SHA Git courant | variables d'inventaire (aucun secret — GSO-REQ-123) |
| appliqué | `.deployed_state.yml` produit par le rôle | `slurp` (lecture — GSO-REQ-119) |
| réel | conteneur + endpoint | `docker inspect` (lecture), `uri` GET, `stat` de `.last_failure.log` |

Chemin : `SITE fermé → sélecteur fermé L3 → assertion cible unique →
collecte lecture seule → classification (fonction pure `scripts/lib/gso_classify.py`)
→ verdict`. **Aucun verrou de mutation** n'est pris : un contrôle ne bloque
jamais un déploiement. Aucun `include_role`/`import_role` du rôle (le rôle
réécrit `.deployed_state.yml` à chaque invocation — proscrit ici).

**Catégories** (contrat §16.5) : `IN_SYNC`, `NOT_DEPLOYED`, `REFERENCE_DRIFT`,
`CONFIG_DRIFT`, `STOPPED`, `UNHEALTHY`, `UNREACHABLE`, `UNKNOWN`. `STOPPED` est
relatif à l'**état désiré** : un site voulu `stopped` et effectivement arrêté
est `IN_SYNC`, jamais `STOPPED` (GSO-REQ-121).

**Codes de sortie** : le contrat (GSO-REQ-093) impose « code non nul si
l'intention n'est pas atteinte » sans fixer de taxonomie numérique. Convention
retenue : **`0` = `IN_SYNC`** (site, ou parc entier) ; **`≠ 0`** sinon — refus
du sélecteur ou du validateur de registre (codes L3, propagés tels quels) pour
une cible absente / retirée / ambiguë ou un registre incohérent ; sinon échec
de play Ansible pour une dérive détectée ou un état indéterminable. La
**catégorie** §16.5 (affichée, sans secret) porte la distinction fine.

`check-all` vérifie d'abord la **cohérence déclarative** du parc (hôte sans
site, site sans hôte, doublon, actif+retiré) **sans connexion aux VM**
(GSO-REQ-125) : un registre incohérent le fait échouer avant tout parcours.
Un hôte injoignable n'interrompt pas le parcours : il est classé `UNREACHABLE`
et le parc ressort non conforme.

## Cycle de vie d'un projet — retrait et réactivation (lot L8)

Le retrait et la réactivation d'un site sont des **opérations Git manuelles**,
explicites et séquencées (contrat §21). `grav-sites-ops` ne fournit **aucun
playbook, aucun script, aucune cible `make`** qui les applique : il fournit
les **fichiers documentaires** ([`docs/LIFECYCLE-SCHEMA.md`](LIFECYCLE-SCHEMA.md)),
un **validateur en lecture seule** (`make lint-lifecycle`) qui vérifie le
résultat **après coup**, et ces procédures. Aucune de ces opérations n'arrête
une VM, ne supprime un conteneur, un volume ou une donnée persistante
(GSO-REQ-027/029/040/182) ni n'appelle un hyperviseur (GSO-REQ-179).

### Retrait d'un projet (contrat §21.6)

1. relever la dernière référence effectivement déployée ;
2. **vérifier** la sauvegarde de la VM et des volumes (opération distincte,
   hors périmètre — GSO-REQ-078) ;
3. traiter séparément la publication dans le `control-repository` si besoin ;
4. **arrêter manuellement la VM** dans l'hyperviseur (jamais un playbook) ;
5. retirer l'hôte de `inventories/production/hosts.yml` ;
6. retirer sa définition de `…/group_vars/all/grav_sites.yml` ;
7. déplacer ses secrets de `vault_grav_sites` vers `vault_retired_grav_sites`
   (vault local non suivi, modifié séparément) ;
8. ajouter sa fiche **sans secret** dans `registry/retired-sites.yml`
   (schéma : [`LIFECYCLE-SCHEMA.md`](LIFECYCLE-SCHEMA.md)) ;
9. `make lint-lifecycle` — et, si un registre/vault de test est résolvable,
   `python3 scripts/lib/gso_lifecycle.py --retired … --reactivated … --registry … --vault …` ;
10. examiner le **diff Git**, revue humaine, **commit explicite** des seuls
    fichiers non secrets :

```text
inventories/production/hosts.yml
inventories/production/group_vars/all/grav_sites.yml
registry/retired-sites.yml
```

Les suppressions dans l'inventaire et le registre actif et l'ajout au registre
retiré **doivent tenir dans le même changement Git** (GSO-REQ-044, GSO-REQ-178).

### Réactivation d'un projet (contrat §21.8) — chemin inverse

1. vérifier la conservation de la VM, des volumes et de la sauvegarde ;
2. **redémarrer manuellement la VM** ;
3. réinscrire l'hôte dans `hosts.yml` (même nom d'hôte, mêmes chemins
   persistants — GSO-REQ-180) ;
4. replacer sa définition dans `grav_sites.yml` ;
5. déplacer ses secrets archivés de `vault_retired_grav_sites` vers
   `vault_grav_sites` ;
6. **retirer sa fiche** de `registry/retired-sites.yml` **et ajouter un
   événement daté** à `registry/reactivated-sites.yml`, comprenant au minimum
   `reactivated_at` et une copie de la dernière fiche retirée
   (`previous_retirement`) — **dans la même opération** (GSO-REQ-052,
   GSO-REQ-181) ;
7. `make lint-lifecycle` puis `make check SITE=<hôte>` ;
8. `make deploy SITE=<hôte>` (première cible unique — GSO-REQ-175) ;
9. vérifier l'état désiré, appliqué et réel, et les quatre volumes ;
10. diff Git, revue, **commit explicite**.

`registry/reactivated-sites.yml` est un **historique append-only** : aucune
réactivation antérieure n'est jamais réécrite ni supprimée. Après une
réactivation, **aucune clé réactivée ne subsiste dans `retired_grav_sites`**
(test automatique `GSO-T22`).

### Ce que L8 ne fait jamais

Aucun playbook / script de retrait ou de réactivation ; aucune modification
automatique d'un inventaire, d'un registre ou d'un vault ; aucun `git add` /
`git commit` automatisé ; aucun arrêt / suppression de VM ou de conteneur ;
aucun mécanisme de purge ; aucune suppression de donnée persistante ; aucune
destruction définitive (GSO-REQ-182 — exige un contrat séparé). Les
transformations sont **éprouvées uniquement** comme états avant/après sur
fixtures synthétiques.

## Concurrence

La règle « une seule mutation à la fois sur un même site » (GSO-REQ-096,
contrat §14.3) est appliquée par un **verrou `flock` par site**
(`scripts/lib/site-mutation.sh`), acquis avant toute invocation du rôle et
**partagé** par `deploy`, `restart` et `stop` : le même fichier
`${XDG_RUNTIME_DIR:-…}/grav-sites-ops/locks/<hôte>.lock` sérialise les trois
intentions, ce qui empêche deux mutations concurrentes sur un même site. Une
tentative concurrente échoue proprement (**code 75**) sans lancer le rôle. Le
noyau libère le descripteur en succès, échec ou interruption. Le sélecteur, le
préflight et le **contrôle de dérive** (`check` / `check-all`), en lecture
seule, restent exécutables sans restriction et **ne prennent aucun verrou**.

## Ce que le sélecteur / préflight ne font jamais

- ouvrir ou déchiffrer un vault opérationnel ;
- se connecter en SSH, exécuter `ansible-playbook`, invoquer `sepp67.grav_site` ;
- modifier un fichier, un conteneur, un volume ou l'état d'un site ;
- accepter une cible globale ou multiple ;
- utiliser un inventaire autre que `inventories/production/hosts.yml`.
