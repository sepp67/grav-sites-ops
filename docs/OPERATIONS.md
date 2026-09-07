# Exploitation

Résumé normatif : contrat architectural `v0.5.0`, sections 8.5, 13 et 14
(`docs/CONTRAT-ARCHITECTURAL.md`). En cas de divergence, le contrat fait foi.

Livré par les **lots L3** (sélecteur fermé, préflight lecture seule), **L4**
(déploiement d'un site) et **L5** (redémarrage, arrêt). `check` / `check-all`
seront ajoutés au lot L6.

## Interface opérateur

| Commande | Effet | Mutation |
|---|---|---|
| `make validate SITE=<hôte>` | sélecteur fermé : valide que `SITE` désigne un hôte actif unique | aucune |
| `make preflight SITE=<hôte>` | sélecteur + cohérence inventaire ↔ registre ↔ vault | aucune |
| `make deploy SITE=<hôte>` | **déploie / actualise** l'instance de `<hôte>` selon le registre | oui (via le rôle) |
| `make restart SITE=<hôte>` | **redémarre** l'instance **sans** changer sa référence désirée (GSO-REQ-088) | oui (via le rôle) |
| `make stop SITE=<hôte>` | **arrête** le conteneur, sans rien supprimer ni retirer du parc (GSO-REQ-089) | oui (via le rôle) |
| `scripts/{validate-target,preflight,deploy,restart-site,stop-site}.sh <hôte>` | idem, sans `make` | — |

Toutes les cibles n'acceptent que `SITE`. **`grav_state` n'est jamais fourni
par l'opérateur** : l'action est déterminée par le point d'entrée invoqué
(`deploy` → état du registre ; `restart` → `restarted` ; `stop` → `stopped`).

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

## Action (lots L4–L5)

Le sélecteur L3 est **agnostique de l'action** : il valide une identité de
cible, pas ce qu'on va en faire. La liste **fermée** des actions opérateur
normatives est `deploy`, `restart`, `stop`, `check` (contrat §13.1 ; constante
`NORMATIVE_ACTIONS` dans `scripts/lib/gso_validate.py`). L'action n'est **jamais
une option** : elle est déterminée par le point d'entrée invoqué
(`scripts/deploy.sh`, `scripts/restart-site.sh`, `scripts/stop-site.sh`), qui
fixe le playbook dédié et, par lui, l'intention `_gso_intent`. L'opérateur ne
peut pas fournir `grav_state`, `--limit`, `-e`, ni aucune option d'inventaire.

`grav_state` est traduit **depuis l'intention seule** (`playbooks/_shared/translate.yml`) :
`restart` → `restarted`, `stop` → `stopped`, `deploy` → l'état du registre. Le
`restart` ne change **ni** version **ni** digest **ni** aucun fichier
persistant (GSO-REQ-088) ; il n'est **pas** un redéploiement. Le `stop`
n'entraîne **aucune** suppression de conteneur, volume, donnée persistante ou
fichier de déploiement (GSO-REQ-089).

Un site à l'état désiré `stopped` reste un **projet actif** du registre : il
est une cible d'identité légitime pour les trois intentions.

## Concurrence

La règle « une seule mutation à la fois sur un même site » (GSO-REQ-096,
contrat §14.3) est appliquée par un **verrou `flock` par site**
(`scripts/lib/site-mutation.sh`), acquis avant toute invocation du rôle et
**partagé** par `deploy`, `restart` et `stop` : le même fichier
`${XDG_RUNTIME_DIR:-…}/grav-sites-ops/locks/<hôte>.lock` sérialise les trois
intentions, ce qui empêche deux mutations concurrentes sur un même site. Une
tentative concurrente échoue proprement (**code 75**) sans lancer le rôle. Le
noyau libère le descripteur en succès, échec ou interruption. Le sélecteur et
le préflight, en lecture seule, restent exécutables sans restriction.

## Ce que le sélecteur / préflight ne font jamais

- ouvrir ou déchiffrer un vault opérationnel ;
- se connecter en SSH, exécuter `ansible-playbook`, invoquer `sepp67.grav_site` ;
- modifier un fichier, un conteneur, un volume ou l'état d'un site ;
- accepter une cible globale ou multiple ;
- utiliser un inventaire autre que `inventories/production/hosts.yml`.
