# Exploitation

Résumé normatif : contrat architectural `v0.5.0`, sections 8.5, 13 et 14
(`docs/CONTRAT-ARCHITECTURAL.md`). En cas de divergence, le contrat fait foi.

Ce document est livré par le **lot L3**. Il décrit le **sélecteur fermé** et le
**préflight opérateur en lecture seule**. Il **n'aborde pas** les opérations
mutantes (`deploy`, `restart`, `stop`), introduites à partir du lot L4.

## Interface opérateur (à ce stade)

| Commande | Effet | Mutation |
|---|---|---|
| `make validate SITE=<hôte>` | sélecteur fermé : valide que `SITE` désigne un hôte actif unique | aucune |
| `make preflight SITE=<hôte>` | sélecteur + cohérence inventaire ↔ registre ↔ vault | aucune |
| `scripts/validate-target.sh <hôte>` | idem `make validate` | aucune |
| `scripts/preflight.sh <hôte>` | idem `make preflight` | aucune |

Les cibles `deploy` / `restart` / `stop` / `check` (contrat §13.1) seront
ajoutées par les lots suivants. Elles commenceront **toujours** par le
sélecteur ci-dessous.

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

## Action (lot L4)

Le sélecteur L3 est **agnostique de l'action** : il valide une identité de
cible, pas ce qu'on va en faire. La liste **fermée** des actions opérateur
normatives est `deploy`, `restart`, `stop`, `check` (contrat §13.1 ; constante
`NORMATIVE_ACTIONS` dans `scripts/lib/gso_validate.py`). À partir du lot L4,
toute action fournie par l'opérateur sera validée contre cette liste fermée
avant toute mutation ; aucune option d'action n'est exposée avant.

Un site à l'état désiré `stopped` reste un **projet actif** du registre : il
est une cible d'identité légitime. Ce que chaque action autorise ou interdit
sur un site `stopped` sera défini par les playbooks du lot L4.

## Concurrence

`grav-sites-ops` n'a, à ce stade, aucune opération mutante. La règle « une
seule mutation à la fois sur un même site » (GSO-REQ-096, contrat §14.3)
s'appliquera aux playbooks introduits à partir du lot L4 ; le sélecteur et le
préflight, en lecture seule, peuvent être exécutés sans restriction.

## Ce que le sélecteur / préflight ne font jamais

- ouvrir ou déchiffrer un vault opérationnel ;
- se connecter en SSH, exécuter `ansible-playbook`, invoquer `sepp67.grav_site` ;
- modifier un fichier, un conteneur, un volume ou l'état d'un site ;
- accepter une cible globale ou multiple ;
- utiliser un inventaire autre que `inventories/production/hosts.yml`.
