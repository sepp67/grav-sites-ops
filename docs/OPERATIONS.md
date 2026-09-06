# Exploitation

Résumé normatif : contrat architectural `v0.5.0`, sections 8.5, 13 et 14
(`docs/CONTRAT-ARCHITECTURAL.md`). En cas de divergence, le contrat fait foi.

Livré par les **lots L3** (sélecteur fermé, préflight lecture seule) et **L4**
(déploiement d'un site). Les opérations `restart` / `stop` seront ajoutées au
lot L5, `check` / `check-all` au lot L6.

## Interface opérateur

| Commande | Effet | Mutation |
|---|---|---|
| `make validate SITE=<hôte>` | sélecteur fermé : valide que `SITE` désigne un hôte actif unique | aucune |
| `make preflight SITE=<hôte>` | sélecteur + cohérence inventaire ↔ registre ↔ vault | aucune |
| `make deploy SITE=<hôte>` | **déploie / actualise** l'instance de `<hôte>` selon le registre | oui (via le rôle) |
| `scripts/validate-target.sh <hôte>` / `scripts/preflight.sh <hôte>` / `scripts/deploy.sh <hôte>` | idem, sans `make` | — |

Toutes les cibles n'acceptent que `SITE`.

## Le chemin de déploiement (lot L4)

`make deploy SITE=<hôte>` → `scripts/deploy.sh` exécute **dans cet ordre** :

```
SITE littéral
  └─▶ 1. préflight local     scripts/validate-target.sh (sélecteur fermé L3)
  └─▶ 2. verrou de concurrence   flock par site (GSO-REQ-096)
  └─▶ 3. playbook deploy-site.yml
          ├─ assertion : --limit == inventory_hostname, un seul hôte,
          │              jamais all/groupe/multiple  (GSO-REQ-016/017/057/082/094)
          ├─ préflight structurel : gso_validate.py preflight <hôte>
          │              (registre + vault + bootstrap + secrets, no_log — GSO-REQ-204)
          ├─ traduction : grav_sites[hôte] + vault_grav_sites[hôte] → grav_*
          │              (exacte, aucune valeur globale, aucun repli)
          └─▶ 4. include_role: sepp67.grav_site   — exactement une fois (GSO-REQ-087)
```

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
