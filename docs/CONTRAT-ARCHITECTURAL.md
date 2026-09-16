# Contrat architectural de `grav-sites-ops`

**Version du document :** 0.5.0 — projet normatif complet  
**Statut :** normatif, approuvé (approbation humaine du 2026-09-05, sur la version 0.5.0)  
**Périmètre de cette livraison :** sections 1 à 23  
**Composant principal consommé :** `ansible-role-grav-site` `v2.0.0`

---

## 1. Objet et statut du document

### 1.1 Objet

Le présent document définit le contrat architectural de `grav-sites-ops`, dépôt d'orchestration Ansible consacré à l'exploitation d'un parc de sites web Grav.

`grav-sites-ops` a pour fonction de décrire l'état désiré du parc Grav et d'invoquer, pour chaque machine explicitement sélectionnée, le rôle atomique `ansible-role-grav-site`. Il centralise la connaissance opérationnelle des projets actifs : machine cible, image applicative, version, digest éventuel, paramètres de déploiement et secrets nécessaires au bootstrap ou à l'administration de l'instance.

Ce dépôt répond aux questions suivantes :

- quels projets Grav sont actifs ;
- sur quelles VM ils sont déployés ;
- quelle image applicative et quelle référence doivent être utilisées ;
- quels paramètres propres à chaque instance doivent être transmis au rôle ;
- quelle opération doit être exécutée sur quelle cible ;
- quels projets ont été retirés du parc actif tout en restant archivés.

Il ne définit pas le mécanisme interne de déploiement d'une instance Grav. Ce mécanisme appartient exclusivement à `ansible-role-grav-site`.

### 1.2 Nature du document

Le présent contrat est normatif. Il précède la création effective du dépôt et doit servir successivement :

1. de référence pour sa structure initiale ;
2. de base à son préflight de conformité ;
3. de cadre pour son implémentation ;
4. de référentiel pour ses tests et ses évolutions ;
5. de frontière contractuelle avec les autres dépôts de la plateforme Grav.

Une implémentation de `grav-sites-ops` ne pourra être déclarée conforme que si elle satisfait les exigences identifiées par le préfixe `GSO-REQ-*`.

### 1.3 Vocabulaire normatif

Les termes suivants ont une valeur normative :

- **DOIT** ou **DOIVENT** : exigence obligatoire ;
- **NE DOIT PAS** ou **NE DOIVENT PAS** : interdiction ;
- **DEVRAIT** ou **DEVRAIENT** : recommandation forte dont tout écart doit être justifié ;
- **PEUT** ou **PEUVENT** : possibilité autorisée mais non obligatoire.

Les exemples YAML, commandes et arborescences illustrent le contrat. Lorsqu'un exemple entre en contradiction avec une exigence formulée en toutes lettres, l'exigence normative prévaut.

### 1.4 Public visé

Ce contrat s'adresse :

- à l'opérateur qui administre les VM Grav ;
- au mainteneur de `grav-sites-ops` ;
- au mainteneur de `ansible-role-grav-site` ;
- à toute personne chargée d'auditer, tester ou faire évoluer la plateforme.

Il suppose une connaissance pratique d'Ansible, de Git, de Docker Compose, d'Ansible Vault et du cycle de vie des images applicatives Grav.

### 1.5 Sources de vérité et ordre de préséance

Pour les responsabilités propres à `grav-sites-ops`, le présent contrat constitue la source normative principale.

Pour le comportement d'une instance Grav, l'interface publique et les invariants de `ansible-role-grav-site` prévalent. `grav-sites-ops` doit consommer cette interface sans réinterpréter ni dupliquer sa logique interne.

En cas de divergence entre le README, les exemples, les playbooks et le présent contrat, la divergence doit être corrigée. Elle ne peut pas être résolue silencieusement en modifiant le sens d'une exigence.

**GSO-REQ-001 — Contrat préalable.** La première implémentation de `grav-sites-ops` DOIT être précédée par l'approbation du présent contrat et par un préflight comparant l'implémentation prévue à ses exigences.

**GSO-REQ-002 — Traçabilité des écarts.** Toute dérogation à une exigence normative DOIT être documentée, justifiée et soumise à un arbitrage humain explicite.

---

## 2. Contexte architectural

### 2.1 Composants de la plateforme Grav

La plateforme repose sur cinq catégories de dépôts ou composants indépendants :

| Composant | Responsabilité |
|---|---|
| `grav-runtime` | Fournir l'environnement technique générique dans lequel Grav s'exécute |
| Dépôts applicatifs, par exemple `projet-gites` ou `projet-lavallee` | Construire l'image propre à un site et choisir la version de `grav-runtime` utilisée par cette image |
| `ansible-role-grav-site` | Déployer et maintenir exactement une instance Grav par invocation |
| `grav-sites-ops` | Décrire le parc actif et orchestrer l'invocation du rôle sur des VM existantes |
| `control-repository` | Publier séparément certains services au moyen du reverse proxy, du routage, des domaines et de TLS |

Les dépendances fonctionnelles suivent le sens suivant :

```text
grav-runtime
    ↓ utilisé pour construire
image applicative du projet
    ↓ déployée par
ansible-role-grav-site
    ↑ invoqué par
grav-sites-ops
```

Le `control-repository` ne se trouve pas dans cette chaîne de déploiement applicatif. Il intervient séparément après qu'une instance est accessible sur le réseau local.

### 2.2 Cycle de vie opérationnel

Le cycle de vie retenu est le suivant :

1. un nouveau projet Grav est créé et testé localement sur la workstation ;
2. son dépôt applicatif produit une image versionnée ;
3. une VM existante est affectée au projet ;
4. `grav-sites-ops` déploie l'image sur cette VM au moyen de `ansible-role-grav-site` ;
5. le site devient accessible sur le réseau local par une adresse IPv4 explicitement définie ;
6. si une publication Internet est souhaitée, le `control-repository` est exécuté séparément afin de configurer le reverse proxy.

Le déploiement sur une VM durable et la publication sur Internet constituent donc deux opérations distinctes.

**GSO-REQ-003 — Déploiement LAN autonome.** `grav-sites-ops` DOIT pouvoir déployer une instance Grav fonctionnelle et accessible sur le réseau local sans connaître, invoquer ou attendre le `control-repository`.

**GSO-REQ-004 — Publication indépendante.** La publication d'un site sur Internet NE DOIT PAS faire partie du succès ou de l'échec d'un déploiement réalisé par `grav-sites-ops`.

### 2.3 Environnement durable unique

La première version de `grav-sites-ops` gère un seul environnement durable nommé `production`.

Dans ce contrat, `production` désigne une instance durable hébergée sur une VM du réseau local. Ce terme n'implique pas que le site soit accessible depuis Internet. Un site de production peut rester exclusivement disponible sur le LAN.

Le développement local sur la workstation n'est pas un environnement géré par `grav-sites-ops`. Aucun environnement `staging` propre aux sites Grav n'est prévu dans la première version.

**GSO-REQ-005 — Environnement unique.** La première version DOIT exposer un inventaire opérationnel unique `inventories/production/` pour les sites Grav durables.

**GSO-REQ-006 — Exemple non opérationnel.** Un inventaire `inventories/example/` PEUT être fourni pour les tests et la documentation, mais il NE DOIT contenir aucune cible réelle ni pouvoir être confondu avec l'inventaire opérationnel.

### 2.4 Modèle d'hébergement

`ansible-role-grav-site` permet techniquement plusieurs invocations sur une même machine. Néanmoins, le modèle d'exploitation retenu pour `grav-sites-ops` est une VM dédiée par projet Grav.

Ce choix permet notamment :

- d'arrêter un projet en arrêtant sa VM ;
- d'isoler les cycles de vie et les incidents ;
- de limiter les collisions de ports, chemins et ressources ;
- de préserver une correspondance simple entre projet, hôte d'inventaire et VM.

**GSO-REQ-007 — Une VM par projet.** Chaque projet actif géré par `grav-sites-ops` DOIT être associé à un hôte d'inventaire distinct représentant une VM dédiée.

**GSO-REQ-008 — Identifiant opérationnel unique.** Le nom de l'hôte d'inventaire DOIT servir d'identifiant opérationnel commun dans l'inventaire, le registre central et le vault.

### 2.5 Indépendance du `control-repository`

La frontière suivante est normative :

> `grav-sites-ops` déploie des instances Grav accessibles sur le réseau local. Le `control-repository`, exécuté séparément, peut ensuite publier certaines de ces instances sur Internet. Aucun des deux dépôts ne dépend de l'autre et aucune transmission automatique de variables n'est nécessaire.

En conséquence :

- `grav-sites-ops` ne doit pas générer la configuration du reverse proxy ;
- il ne doit pas déclencher le `control-repository` ;
- il ne doit pas produire de fichier d'échange destiné à celui-ci ;
- il ne doit pas exiger qu'un domaine public soit défini ;
- le `control-repository` ne doit pas être requis pour tester la santé locale d'une instance Grav.

**GSO-REQ-009 — Absence de dépendance croisée.** Aucune dépendance Ansible, Git, CI ou exécution automatique NE DOIT relier `grav-sites-ops` au `control-repository`.

---

## 3. Responsabilité unique de `grav-sites-ops`

### 3.1 Mission centrale

La responsabilité unique de `grav-sites-ops` est de maintenir et d'appliquer l'état désiré du parc de sites Grav durablement déployés sur des VM existantes.

Cette responsabilité se résume ainsi :

> Déterminer quelle instance Grav doit fonctionner sur quelle VM, avec quelle image applicative, quelle référence et quels paramètres d'exploitation, puis invoquer le rôle atomique pour appliquer cette décision.

`grav-sites-ops` orchestre ; `ansible-role-grav-site` déploie.

### 3.2 État désiré

Pour chaque hôte actif, l'état désiré doit pouvoir exprimer au minimum :

- l'identité du projet ;
- l'image applicative ;
- la version déclarée ;
- le digest éventuel ;
- le nom du conteneur ;
- le répertoire de base ;
- l'adresse d'écoute IPv4 sur le LAN ;
- le port HTTP ;
- les variables optionnelles explicitement autorisées par l'interface publique du rôle ;
- la référence aux secrets correspondant au même identifiant d'hôte.

La version de `grav-runtime` ne fait pas partie de cet état désiré. Elle est déjà sélectionnée et figée par le dépôt applicatif lors de la construction de l'image du projet.

**GSO-REQ-010 — Source de vérité applicative.** La version de l'image applicative et son digest éventuel DOIVENT être déclarés dans `grav-sites-ops`.

**GSO-REQ-011 — Pas de seconde source pour le runtime.** `grav-sites-ops` NE DOIT PAS déclarer séparément la version de `grav-runtime` utilisée par une image applicative.

### 3.3 Registre central actif

Les définitions non secrètes des sites actifs doivent être centralisées dans un fichier chargé automatiquement par Ansible :

```text
inventories/production/group_vars/all/grav_sites.yml
```

Le dictionnaire racine doit être nommé `grav_sites`. Chaque clé doit correspondre exactement à un hôte déclaré dans `inventories/production/hosts.yml`.

Exemple conceptuel :

```yaml
grav_sites:
  grav-gites:
    project_name: projet-gites
    image: ghcr.io/sepp67/projet-gites
    version: "1.0.4"
    digest: ""
    container_name: projet-gites
    base_directory: /opt/projet-gites
    bind_address: 192.0.2.10
    http_port: 8080
```

L'adresse ci-dessus est une adresse documentaire. Elle ne constitue pas une valeur opérationnelle.

**GSO-REQ-012 — Chargement automatique.** Le registre actif DOIT être placé dans un emplacement `group_vars` chargé automatiquement par Ansible. Un playbook opérationnel NE DOIT PAS dépendre d'un `include_vars` implicite, d'un chemin de workstation ou d'un fichier déplacé hors de l'inventaire.

**GSO-REQ-013 — Correspondance totale.** Tout hôte actif DOIT posséder exactement une entrée dans `grav_sites`, et toute entrée de `grav_sites` DOIT correspondre à exactement un hôte actif.

### 3.4 Composition du rôle

`grav-sites-ops` doit consommer `ansible-role-grav-site` comme dépendance externe au moyen d'un `requirements.yml` épinglé sur un tag Git explicite. La première version doit utiliser au minimum `v2.0.0`.

L'orchestrateur doit transmettre les variables publiques du rôle. Il ne doit ni copier ses tâches, ni reproduire ses templates, ni dépendre de ses variables internes préfixées.

**GSO-REQ-014 — Dépendance épinglée.** `ansible-role-grav-site` DOIT être installé depuis Git avec un tag explicite dans `requirements.yml`. Une branche flottante, `main`, `HEAD` ou une version non épinglée NE DOIT PAS être utilisée en exploitation.

**GSO-REQ-015 — Interface publique uniquement.** `grav-sites-ops` NE DOIT consommer que l'interface publique documentée du rôle.

### 3.5 Sélection de la cible

Les opérations ciblées doivent utiliser le mécanisme Ansible natif `--limit`. La première version ne doit pas introduire de variable concurrente telle que `grav_site_target`.

Pour une opération mutante portant sur un site, `--limit` doit sélectionner exactement un hôte appartenant au groupe des serveurs Grav. Une omission de `--limit`, la valeur `all`, un motif vide ou une sélection de plusieurs hôtes doivent provoquer un échec avant toute mutation distante.

**GSO-REQ-016 — Limite obligatoire.** `deploy-site.yml`, `restart-site.yml` et `stop-site.yml` DOIVENT refuser toute exécution sans `--limit` explicite.

**GSO-REQ-017 — Cible unique.** Une opération mutante ciblée DOIT refuser une limite qui sélectionne zéro ou plusieurs hôtes.

**GSO-REQ-018 — Pas de variable de sélection parallèle.** La première version NE DOIT PAS utiliser `grav_site_target` pour sélectionner un projet.

### 3.6 Non-duplication de la logique

L'orchestrateur peut valider la cohérence de son propre registre, la cible demandée et la présence des secrets associés. Il ne doit pas réimplémenter les validations déjà garanties par le rôle pour une instance.

**GSO-REQ-019 — Séparation orchestration/mécanisme.** Les tâches de création des répertoires, rendu Compose, installation Docker, bootstrap administrateur, déploiement, healthcheck et traçabilité effective DOIVENT rester dans `ansible-role-grav-site`.

---

## 4. Périmètre fonctionnel

### 4.1 Gestion déclarative du parc actif

`grav-sites-ops` doit gérer la liste des projets Grav actifs et leur association aux VM existantes.

Il doit fournir :

- un inventaire `production` ;
- un groupe explicite de serveurs Grav ;
- un registre central `grav_sites` ;
- une correspondance vérifiable entre hôtes et définitions ;
- des exemples non opérationnels ;
- une documentation d'ajout et de retrait d'un projet.

### 4.2 Paramètres applicatifs et opérationnels

Le dépôt doit porter les paramètres non secrets nécessaires à chaque invocation du rôle, notamment :

- `grav_image` ;
- `grav_version` ;
- `grav_digest` lorsqu'un déploiement immuable est souhaité ;
- `grav_container_name` ;
- `grav_base_directory` ;
- `grav_bind_address` ;
- `grav_http_port` ;
- l'état demandé et les options publiques du rôle lorsqu'elles sont nécessaires.

Il peut définir des valeurs communes à l'ensemble du parc si celles-ci sont réellement communes et ne masquent pas une décision propre à un site.

**GSO-REQ-020 — Pas de `latest`.** Aucune image opérationnelle NE DOIT utiliser le tag `latest`.

**GSO-REQ-021 — Référence explicite.** Chaque site actif DOIT déclarer une version applicative humaine non vide et PEUT déclarer un digest conforme au contrat du rôle.

### 4.3 Secrets

La première version utilise un vault global unique situé à l'emplacement chargé automatiquement suivant :

```text
inventories/production/group_vars/all/vault.yml
```

Le dictionnaire des secrets actifs doit être nommé `vault_grav_sites`. Ses clés doivent correspondre aux noms des hôtes actifs. Des commentaires internes doivent séparer clairement les projets dans le fichier déchiffré.

Les secrets des projets retirés doivent être conservés dans le même vault sous un dictionnaire distinct `vault_retired_grav_sites`, afin de permettre une réactivation sans perdre la correspondance avec les comptes persistants.

Le vault opérationnel doit rester chiffré et non suivi par Git. Un fichier d'exemple sans secret peut être suivi dans l'inventaire d'exemple.

**GSO-REQ-022 — Vault unique.** La première version DOIT utiliser un seul vault opérationnel global pour les sites Grav.

**GSO-REQ-023 — Aucun secret suivi.** Aucun secret réel, même chiffré, NE DOIT être suivi par Git dans la première version de `grav-sites-ops`.

**GSO-REQ-024 — Absence de divulgation.** Les playbooks, tests, erreurs et sorties de CI NE DOIVENT PAS afficher les valeurs du vault.

### 4.4 Opérations d'exploitation

Le dépôt doit fournir des interfaces documentées permettant au minimum :

- de déployer ou mettre à jour un site explicitement sélectionné ;
- de vérifier un site explicitement sélectionné ;
- de redémarrer un site explicitement sélectionné ;
- d'arrêter le conteneur d'un site explicitement sélectionné ;
- de vérifier la cohérence statique de l'inventaire et du registre ;
- d'installer la version épinglée du rôle ;
- d'exécuter les validations et tests sans contacter de VM réelle.

Une opération globale, si elle est ajoutée, doit posséder un playbook explicitement nommé et des garde-fous distincts. Elle ne peut jamais être déclenchée par l'oubli de `--limit` sur un playbook ciblé.

**GSO-REQ-025 — Commandes explicites.** Chaque opération DOIT avoir une commande ou une cible Makefile documentée et non ambiguë.

**GSO-REQ-026 — Échec sûr.** Une erreur de sélection, de registre, de secrets ou de validation DOIT interrompre l'opération avant toute mutation distante.

### 4.5 Retrait et réactivation d'un projet

Le retrait d'un projet est une désinscription réversible du parc actif. Il ne constitue pas une destruction.

Le processus doit comprendre :

1. la vérification préalable des sauvegardes nécessaires ;
2. l'arrêt manuel de la VM ;
3. le retrait de l'hôte dans `inventories/production/hosts.yml` ;
4. le retrait de sa définition dans `grav_sites.yml` ;
5. le déplacement local de ses secrets de `vault_grav_sites` vers `vault_retired_grav_sites` ;
6. son inscription sans secret dans `registry/retired-sites.yml` ;
7. le traitement séparé de sa publication éventuelle dans le `control-repository`.

`registry/retired-sites.yml` doit être suivi par Git mais placé hors de `group_vars`, afin de ne jamais être chargé comme registre actif. Il doit conserver les informations techniques non secrètes nécessaires à une future réactivation.

**GSO-REQ-027 — Retrait non destructif.** Retirer un projet du parc actif NE DOIT supprimer automatiquement ni sa VM, ni ses conteneurs, ni ses volumes, ni ses sauvegardes, ni ses secrets archivés.

**GSO-REQ-028 — Registre des projets retirés.** Tout projet retiré DOIT être consigné dans `registry/retired-sites.yml` sans secret.

**GSO-REQ-029 — Absence de playbook destructif.** La première version NE DOIT PAS contenir de playbook supprimant un projet, une VM ou ses données persistantes.

### 4.6 Validation et CI

Le périmètre comprend les validations statiques et les tests nécessaires pour démontrer au minimum :

- le chargement correct de l'inventaire exemple ;
- la cohérence entre inventaire, registre et vault d'exemple ;
- le refus d'une opération ciblée sans `--limit` ;
- le refus d'une sélection multiple ;
- l'absence de cible réelle et de secret dans les fichiers suivis ;
- l'installation de `ansible-role-grav-site` depuis la référence épinglée ;
- la transmission correcte des variables publiques ;
- l'impossibilité pour la CI de contacter le réseau de production ;
- l'absence de dépendance au `control-repository`.

**GSO-REQ-030 — CI non opérationnelle.** La CI NE DOIT disposer d'aucun inventaire, secret, routage ou identifiant lui permettant de contacter les VM réelles.

---

## 5. Hors périmètre

### 5.1 Construction des images

`grav-sites-ops` ne construit ni `grav-runtime` ni les images applicatives des projets. Il ne contient pas leurs Dockerfiles, leurs thèmes, leurs plugins ou leur contenu versionné.

**GSO-REQ-031 — Images externes.** La construction, le test et la publication des images DOIVENT rester dans leurs dépôts respectifs.

### 5.2 Logique interne du rôle

Le dépôt ne possède pas la logique permettant :

- d'installer Docker ;
- de créer les répertoires persistants ;
- de rendre `docker-compose.yml` ou `grav.env` ;
- de créer un compte administrateur ;
- de démarrer les conteneurs ;
- de contrôler le healthcheck ;
- de produire l'état déployé.

Ces fonctions appartiennent au rôle.

### 5.3 Provisioning des VM

La première version suppose que les VM existent déjà, disposent d'un système supporté, sont joignables par SSH et peuvent être administrées par Ansible.

Elle ne doit ni créer, ni cloner, ni dimensionner, ni arrêter, ni détruire une VM dans Proxmox ou dans un autre hyperviseur.

**GSO-REQ-032 — VM préexistantes.** `grav-sites-ops` DOIT traiter les VM comme des ressources préexistantes.

Le provisioning automatique est reporté à une évolution ultérieure et devra faire l'objet d'un contrat ou d'une couche dédiée.

### 5.4 Publication réseau

Sont hors périmètre :

- Caddy ou tout autre reverse proxy central ;
- TLS public ;
- certificats ;
- DNS ;
- domaines publics ;
- ouverture de ports Internet ;
- génération d'upstreams pour le `control-repository`.

### 5.5 Contenu, synchronisation et sauvegarde

La modification éditoriale du site et les transferts entre un dépôt Git et les volumes persistants sont hors périmètre.

Sont notamment exclus :

- l'édition des pages depuis Grav ;
- la synchronisation dépôt vers VM ;
- la synchronisation VM vers dépôt ;
- la résolution des divergences de contenu ;
- la sauvegarde des volumes ;
- la restauration des volumes ;
- le rollback automatique des données persistantes.

Ces opérations peuvent utiliser des scripts ou procédures externes, mais elles ne doivent pas être dissimulées dans un déploiement Ansible.

**GSO-REQ-033 — Pas de synchronisation implicite.** Un déploiement, une mise à jour ou un rollback d'image NE DOIT déclencher aucune synchronisation Git–volumes.

### 5.6 Suppression et retrait destructif

La destruction d'un site, de sa VM, de ses volumes, de ses sauvegardes ou de ses secrets est hors périmètre de la première version.

L'arrêt d'un conteneur au moyen du rôle est une opération d'exploitation réversible. Il ne doit pas être confondu avec le retrait administratif du projet ou l'arrêt de sa VM.

### 5.7 Supervision générale

`grav-sites-ops` peut vérifier l'état immédiat d'une instance au moyen du contrat du rôle. Il ne remplace pas une plateforme de supervision, de métriques, de logs centralisés, d'alerting ou de gestion d'incidents.

### 5.8 Gestion généraliste d'autres services

Le dépôt est spécialisé dans Grav. Il ne doit pas orchestrer Matrix, Keycloak, Nextcloud, le Facturier ou d'autres services.

**GSO-REQ-034 — Spécialisation Grav.** Toute orchestration sans rapport direct avec le parc Grav DOIT rester hors de ce dépôt.

---

## 6. Invariants architecturaux

Les invariants ci-dessous s'appliquent à toute version de `grav-sites-ops`, sauf modification explicite du présent contrat par décision architecturale approuvée.

### 6.1 Atomicité du composant consommé

`ansible-role-grav-site` déploie exactement une instance par invocation. `grav-sites-ops` obtient la gestion d'un parc par composition de cette unité, jamais par transformation du rôle en composant multi-sites.

**GSO-REQ-035 — Composition.** La gestion de plusieurs sites DOIT résulter de plusieurs invocations indépendantes du rôle.

### 6.2 Une VM dédiée par projet

Chaque projet actif possède une VM dédiée et un identifiant d'hôte unique. La capacité technique du rôle à héberger plusieurs instances sur une machine ne constitue pas le modèle d'exploitation de ce dépôt.

**GSO-REQ-036 — Isolation d'exploitation.** Deux projets actifs NE DOIVENT PAS partager le même hôte d'inventaire dans la première version.

### 6.3 Identité cohérente

Le nom d'hôte d'inventaire constitue la clé commune :

```text
inventories/production/hosts.yml
            ↓
grav_sites[inventory_hostname]
            ↓
vault_grav_sites[inventory_hostname]
```

**GSO-REQ-037 — Clé commune.** Aucun mécanisme de correspondance parallèle, table de traduction ou variable `grav_site_target` NE DOIT être nécessaire pour trouver la définition et les secrets de l'hôte sélectionné.

### 6.4 Sélection explicite avant mutation

Aucune opération mutante ciblée ne peut utiliser implicitement tous les hôtes. La sélection est une décision de l'opérateur, exprimée par `--limit`.

**GSO-REQ-038 — Refus par défaut.** En l'absence d'une limite explicite sélectionnant exactement un hôte, une opération mutante ciblée DOIT échouer de manière sûre.

Le contrôle doit être exécuté avant les tâches mutantes. Il devrait être délégué localement et accompagné d'un arrêt global du play en cas d'échec.

### 6.5 Séparation des données

Les informations sont séparées selon leur nature :

| Nature | Emplacement normatif |
|---|---|
| Hôtes actifs et connexion Ansible | `inventories/production/hosts.yml` |
| Définitions actives non secrètes | `inventories/production/group_vars/all/grav_sites.yml` |
| Secrets actifs et archivés | `inventories/production/group_vars/all/vault.yml` |
| Projets retirés, sans secret | `registry/retired-sites.yml` |
| Exemples non opérationnels | `inventories/example/` |

**GSO-REQ-039 — Pas de mélange.** Les secrets NE DOIVENT PAS être placés dans le registre non secret ou dans le registre des projets retirés.

### 6.6 Persistance prioritaire

Les quatre ensembles de données `pages`, `accounts`, `data` et `images` doivent survivre aux mises à jour et rollbacks d'image. `grav-sites-ops` ne doit jamais contourner les protections de persistance du rôle.

**GSO-REQ-040 — Données préservées.** Aucune opération normale de `grav-sites-ops` NE DOIT supprimer, recréer à vide ou écraser implicitement les volumes persistants.

### 6.7 Versions maîtrisées

Toute image applicative doit utiliser une version explicite. Un digest peut renforcer l'immutabilité. Le rôle doit rester épinglé sur un tag Git explicite.

**GSO-REQ-041 — Références reproductibles.** Les dépendances et images utilisées en exploitation NE DOIVENT PAS reposer sur une branche flottante ou sur `latest`.

### 6.8 Secrets non divulgués

Le vault réel reste local, chiffré et non suivi. Les secrets ne doivent apparaître ni dans Git, ni dans les logs, ni dans les fichiers de traçabilité produits par l'orchestrateur.

**GSO-REQ-042 — Secret hors historique.** La suppression ultérieure d'un secret du dépôt ne constitue pas une protection suffisante ; aucun secret réel NE DOIT entrer dans l'historique Git.

### 6.9 Indépendance des cycles de vie

Le runtime, les images applicatives, le rôle, l'orchestrateur et la publication réseau évoluent séparément.

**GSO-REQ-043 — Pas de couplage de publication.** La réussite d'une opération `grav-sites-ops` NE DOIT dépendre ni d'un domaine, ni de TLS, ni du reverse proxy central.

### 6.10 Retrait réversible

Un projet retiré sort des registres actifs mais reste récupérable. L'arrêt ou la conservation de la VM relève d'une opération humaine extérieure au dépôt.

**GSO-REQ-044 — Archivage avant oubli.** Une définition active NE DOIT PAS être supprimée sans création ou mise à jour correspondante dans `registry/retired-sites.yml`.

### 6.11 Aucun provisioning implicite

Le dépôt agit sur des VM explicitement inventoriées. Il ne crée aucune infrastructure et ne tente pas de compenser silencieusement l'absence d'une VM.

**GSO-REQ-045 — Frontière infrastructure.** Une cible absente ou injoignable DOIT provoquer un échec explicite, jamais la création automatique d'une ressource.

### 6.12 Tests sans accès à la production

Les exemples et tests doivent fonctionner avec des valeurs fictives et sans secret opérationnel.

**GSO-REQ-046 — Cloisonnement CI.** Aucun workflow de CI NE DOIT pouvoir résoudre ou atteindre les hôtes réels de l'inventaire de production.

### 6.13 Évolution contrôlée

Toute évolution qui introduit le provisioning, plusieurs environnements durables, plusieurs sites par VM, un gestionnaire de secrets externe, une suppression automatisée ou une dépendance à la publication réseau constitue une évolution architecturale. Elle exige un amendement du contrat avant son implémentation.

**GSO-REQ-047 — Amendement préalable.** Une évolution modifiant un invariant DOIT être arbitrée et documentée avant toute modification de code.

---

## 7. Modèle de données du parc

### 7.1 Principes généraux

Le modèle de données de `grav-sites-ops` doit représenter l'état désiré du parc sans recopier l'état technique déjà produit par `ansible-role-grav-site`.

Il distingue quatre ensembles :

| Ensemble | Contenu | Sensibilité |
|---|---|---|
| Inventaire | Hôtes, groupes et paramètres de connexion Ansible | Opérationnel, non secret |
| Registre actif | Définition déclarative de chaque instance Grav | Opérationnel, non secret |
| Vault global | Identifiants et autres valeurs confidentielles | Secret, chiffré, non suivi |
| Registre retiré | Métadonnées des projets désinscrits | Historique, non secret |

Le nom d'hôte d'inventaire est la clé de jointure unique entre ces ensembles. Aucun identifiant secondaire n'est nécessaire pour sélectionner une instance.

### 7.2 Schéma du registre actif

Le registre actif se trouve dans :

```text
inventories/production/group_vars/all/grav_sites.yml
```

Il contient un unique dictionnaire racine `grav_sites`. Chaque entrée suit le schéma conceptuel suivant :

```yaml
grav_sites:
  grav-example:
    project_name: projet-example
    image: registry.example.invalid/example/grav-site
    version: "1.0.0"
    digest: ""
    container_name: projet-example
    base_directory: /opt/projet-example
    bind_address: 192.0.2.10
    http_port: 8080
    state: started
    force_pull: false
    manage_docker: true
    site_check_path: /healthz
    extra_environment: {}
```

Les noms de champs du registre sont propres à l'orchestrateur. Leur traduction vers les variables publiques `grav_*` est centralisée dans les playbooks. Le registre ne doit pas contenir des fragments de tâches Ansible ou des expressions qui dupliquent la logique du rôle.

### 7.3 Champs obligatoires

Chaque entrée active doit définir au minimum :

| Champ | Règle |
|---|---|
| `project_name` | Identité humaine stable du projet |
| `image` | Image applicative sans tag incorporé |
| `version` | Version humaine explicite et non vide |
| `digest` | Chaîne vide ou digest accepté par le rôle |
| `container_name` | Nom Docker unique dans la VM |
| `base_directory` | Chemin absolu propre au projet |
| `bind_address` | Adresse IPv4 explicite de la VM sur le LAN |
| `http_port` | Port HTTP valide et non nul |

Les champs optionnels absents doivent recevoir une valeur déterministe définie dans un emplacement commun documenté ou être laissés aux valeurs par défaut publiques du rôle. Un même défaut ne doit pas être redéfini à plusieurs niveaux.

**GSO-REQ-048 — Schéma explicite.** Le registre actif DOIT faire l'objet d'un schéma documenté distinguant champs obligatoires et optionnels.

**GSO-REQ-049 — Valeurs scalaires sûres.** Les versions, digests, adresses, ports, états et chemins DOIVENT être validés avant l'invocation du rôle.

### 7.4 Contraintes d'unicité

Même si une VM est dédiée à chaque projet, le registre doit vérifier :

- l'unicité de `project_name` ;
- l'unicité de `container_name` ;
- l'unicité de `base_directory` ;
- l'unicité du couple `bind_address` et `http_port` ;
- l'égalité entre la clé du registre et un nom d'hôte actif ;
- l'absence d'entrée active dans `retired_grav_sites` sous la même clé.

**GSO-REQ-050 — Unicité du parc.** Toute collision sur un identifiant, un chemin ou un endpoint DOIT faire échouer le préflight avant toute mutation.

### 7.5 État demandé

Le registre peut exprimer l'état demandé avec les valeurs autorisées par le rôle. La valeur normale d'un projet actif est `started`.

L'état `stopped` signifie que le conteneur doit être arrêté sur une VM toujours administrée. Il ne signifie ni retrait du parc, ni arrêt de la VM, ni suppression des données.

**GSO-REQ-051 — États non destructifs.** Aucun état déclaré dans le registre actif NE DOIT entraîner la suppression des volumes persistants.

### 7.6 Valeurs communes

Les valeurs réellement communes peuvent être placées dans un fichier séparé automatiquement chargé, par exemple :

```text
inventories/production/group_vars/all/main.yml
```

Une valeur commune ne doit pas masquer les propriétés qui caractérisent une instance. L'image, la version, le digest, le nom du conteneur, le répertoire de base, l'adresse et le port restent attachés explicitement au site.

### 7.7 Registre des projets retirés et historique des réactivations

Le registre historique se trouve hors de l'inventaire actif :

```text
registry/retired-sites.yml
registry/reactivated-sites.yml
```

`retired-sites.yml` désigne, sans exception, l'ensemble exact des projets **actuellement** retirés. Son dictionnaire racine est `retired_grav_sites`. Une entrée devrait conserver :

```yaml
retired_grav_sites:
  grav-example:
    project_name: projet-example
    retired_at: "2026-09-04"
    former_inventory_host: grav-example
    former_ansible_host: 192.0.2.10
    former_base_directory: /opt/projet-example
    container_name: projet-example
    last_deployment:
      image: registry.example.invalid/example/grav-site
      version: "1.0.0"
      digest: ""
    preservation:
      vm_status: stopped
      vm_preserved: true
      persistent_data_preserved: true
      secrets_archived_in_vault: true
    reason: Projet mis temporairement de côté
```

Ce fichier n'est jamais une source de déploiement et ne contient aucun secret.

`registry/retired-sites.yml` est un fichier documentaire chargé explicitement par les outils de validation et de gestion du cycle de vie ; il n'est pas chargé automatiquement par Ansible. Son dictionnaire racine normatif est `retired_grav_sites`.

`reactivated-sites.yml` est un historique **append-only**, distinct de `retired-sites.yml`, qui conserve la trace de chaque réactivation sans jamais faire réapparaître la clé dans le registre des projets retirés. Son dictionnaire racine est `reactivated_sites`, chaque clé associée à une **liste** d'événements — un projet retiré puis réactivé plusieurs fois au cours de son existence conserve ainsi l'historique complet, sans perte :

```yaml
reactivated_sites:
  grav-example:
    - reactivated_at: "2026-09-04"
      project_name: projet-example
      former_inventory_host: grav-example
      previous_retirement:
        retired_at: "2026-08-01"
        reason: Projet mis temporairement de côté
```

Ce fichier n'est jamais une source de déploiement et ne contient aucun secret.

`registry/reactivated-sites.yml` est, de la même manière, un fichier documentaire chargé explicitement par les outils de validation et de gestion du cycle de vie ; il n'est pas chargé automatiquement par Ansible. Son dictionnaire racine normatif est `reactivated_sites`.

**GSO-REQ-052 — Registres disjoints.** Une même clé NE DOIT PAS être simultanément active dans `grav_sites` et présente dans `retired_grav_sites`, sans aucune exception. Lors d'une réactivation, la fiche DOIT être retirée de `retired_grav_sites` dans la même opération qui rétablit la clé dans `grav_sites` ; un événement DOIT être ajouté à `registry/reactivated-sites.yml`.

---

## 8. Contrat d'inventaire

### 8.1 Arborescence normative

La première version utilise l'arborescence suivante :

```text
inventories/
├── example/
│   ├── hosts.yml
│   └── group_vars/
│       └── all/
│           ├── grav_sites.yml
│           └── vault.yml.example
└── production/
    ├── hosts.yml
    └── group_vars/
        └── all/
            ├── main.yml
            ├── grav_sites.yml
            └── vault.yml
```

`main.yml` peut être omis si aucune valeur commune n'est nécessaire. `vault.yml` est local, chiffré et ignoré par Git.

### 8.2 Inventaire explicite

`ansible.cfg` ne doit pas désigner `inventories/production/hosts.yml` comme inventaire par défaut. Chaque commande opérationnelle doit fournir explicitement `-i` ou passer par une cible Makefile qui l'ajoute de manière visible.

Exemple :

```bash
ansible-playbook \
  -i inventories/production/hosts.yml \
  playbooks/deploy-site.yml \
  --limit grav-example \
  --ask-vault-pass
```

**GSO-REQ-053 — Aucun inventaire opérationnel par défaut.** Une commande Ansible exécutée sans `-i` NE DOIT PAS pouvoir utiliser implicitement l'inventaire de production.

### 8.3 Groupe des serveurs Grav

Les hôtes actifs doivent appartenir à un groupe unique et explicite, nommé `grav_servers` :

```yaml
all:
  children:
    grav_servers:
      hosts:
        grav-example:
          ansible_host: 192.0.2.10
```

Dans l'inventaire réel, `ansible_host` contient l'adresse LAN réelle de la VM. Les exemples utilisent exclusivement des adresses documentaires non routables.

Les paramètres de connexion tels que `ansible_user`, le port SSH ou la méthode d'élévation peuvent être définis au niveau approprié de l'inventaire, sans contenir de mot de passe en clair.

**GSO-REQ-054 — Groupe fermé.** Les playbooks Grav opérationnels DOIVENT cibler `grav_servers` et non `all`.

### 8.4 Chargement des variables

Les variables actives et le vault sont placés sous `group_vars/all/` afin d'être chargés par le mécanisme standard d'Ansible. Leur chargement ne dépend pas du répertoire courant depuis lequel le playbook est lancé.

Le dépôt ne doit pas utiliser de chemin absolu, de lien symbolique local ou d'`include_vars` pointant vers une arborescence extérieure pour retrouver le registre ou le vault.

Chaque fichier automatiquement chargé DOIT posséder des clés racines distinctes. La conformité du registre NE DOIT PAS dépendre de l'ordre alphabétique de chargement ni de l'écrasement d'une variable par un autre fichier.

**GSO-REQ-055 — Indépendance du répertoire courant.** Une commande documentée DOIT charger le même inventaire et les mêmes variables depuis tout répertoire de travail autorisé.

### 8.5 Garde-fou `--limit`

Les playbooks ciblés `deploy-site.yml`, `restart-site.yml` et `stop-site.yml` doivent vérifier :

1. que `ansible_limit` est défini ;
2. qu'il n'est ni vide ni égal à `all` ;
3. qu'il sélectionne exactement un hôte ;
4. que cet hôte appartient à `grav_servers` ;
5. qu'il possède une entrée dans `grav_sites` ;
6. qu'il possède une entrée active correspondante dans le vault lorsque l'opération nécessite les secrets.

Le contrôle doit précéder toute mutation distante. Une limite inconnue ou ne sélectionnant aucun hôte doit également produire un échec explicite plutôt qu'un succès vide.

**GSO-REQ-056 — Zéro cible interdit.** Une opération demandée avec une limite ne correspondant à aucun hôte DOIT échouer explicitement, avec un code de sortie non nul, avant l'appel à `ansible-playbook`. Ce cas n'est pas garanti détectable par une tâche interne au playbook ; sa détection incombe exclusivement au validateur local (§13.3).

**GSO-REQ-057 — Une seule cible.** Une sélection de plusieurs hôtes DOIT être refusée par les playbooks ciblés, même si elle résulte d'un motif ou d'un nom de groupe valide.

### 8.6 Opérations globales

Une opération de lecture globale peut utiliser un playbook distinct tel que `check-all.yml`.

Une opération mutante globale n'est pas implicitement autorisée par le présent contrat. Si un futur `deploy-all.yml` est créé, il doit être explicitement nommé, documenté, testé et protégé par une confirmation distincte. Il ne doit pas réutiliser silencieusement l'absence de `--limit` comme intention de cibler tout le parc.

### 8.7 Inventaire d'exemple et CI

L'inventaire d'exemple doit :

- être syntaxiquement valide ;
- utiliser un hôte et une adresse non routables ;
- contenir des données fictives ;
- disposer d'un vault d'exemple non chiffré et sans secret ;
- permettre les tests de cohérence et les syntax-checks ;
- ne jamais être utilisable comme inventaire de production.

La CI doit utiliser uniquement cet inventaire ou un inventaire temporaire généré pour les tests.

**GSO-REQ-058 — Inventaire CI isolé.** Aucun workflow NE DOIT charger `inventories/production/group_vars/all/vault.yml` ni tenter une connexion vers `inventories/production/hosts.yml`.

---

## 9. Contrat avec `ansible-role-grav-site`

### 9.1 Dépendance externe

Le rôle est déclaré dans un fichier `requirements.yml` à la racine :

```yaml
roles:
  - name: sepp67.grav_site
    src: git+https://github.com/sepp67/ansible-role-grav-site.git
    version: "v2.0.0"
```

La forme exacte de `src` DOIT être celle effectivement vérifiée par GSO-T03/T04 avant d'être considérée comme la référence documentée — voir le guide d'installation du rôle pour les formes déjà testées par celui-ci.

La commande d'installation doit être documentée, par exemple :

```bash
ansible-galaxy role install -r requirements.yml
```

Le dépôt ne doit pas dépendre d'un clone voisin, d'un lien symbolique ou d'un chemin local vers le rôle.

**GSO-REQ-059 — Installation reproductible.** Une installation neuve DOIT récupérer le rôle sous le nom `sepp67.grav_site` à la version épinglée.

### 9.2 Mise à niveau du rôle

La version du rôle est une dépendance du dépôt, différente de la version des images applicatives. Sa mise à niveau doit suivre une procédure contrôlée :

1. lire le changelog et le guide de migration du rôle ;
2. modifier uniquement la référence dans `requirements.yml` ;
3. réinstaller le rôle dans un environnement propre ;
4. exécuter les tests statiques et fonctionnels de l'orchestrateur ;
5. vérifier au moins un site fictif ;
6. committer séparément la montée de version.

**GSO-REQ-060 — Mise à niveau isolée.** Une montée de version du rôle DOIT être identifiable dans un commit distinct des changements de versions applicatives.

### 9.3 Traduction du registre vers le rôle

Le playbook centralise la traduction suivante :

| Registre | Variable publique du rôle |
|---|---|
| `image` | `grav_image` |
| `version` | `grav_version` |
| `digest` | `grav_digest` |
| `container_name` | `grav_container_name` |
| `base_directory` | `grav_base_directory` |
| `bind_address` | `grav_bind_address` |
| `http_port` | `grav_http_port` |
| `state` | `grav_state` |
| `force_pull` | `grav_force_pull` |
| `manage_docker` | `grav_manage_docker` |
| `site_check_path` | `grav_site_check_path` |
| `extra_environment` | `grav_extra_environment` |

Les valeurs absentes doivent être traitées de manière déterministe. Le playbook ne doit jamais transmettre la chaîne textuelle `omit` ou convertir silencieusement un type invalide.

### 9.4 Variables secrètes

Les valeurs d'administration sont obtenues exclusivement depuis :

```yaml
vault_grav_sites[inventory_hostname]
```

Leur traduction utilise les variables publiques `grav_admin_*` documentées par la version épinglée du rôle. L'orchestrateur doit respecter le contrat de complétude imposé par celui-ci : aucun sous-ensemble incomplet d'identifiants de bootstrap ne peut être transmis.

Les tâches qui valident ou transmettent ces valeurs doivent être protégées contre leur affichage. L'absence d'une entrée active dans le vault doit produire un message générique identifiant le site, jamais le contenu manquant.

**GSO-REQ-061 — Secrets par identifiant d'hôte.** Les secrets transmis à une invocation DOIVENT provenir exclusivement de l'entrée correspondant à `inventory_hostname`.

**GSO-REQ-062 — Ensemble de bootstrap cohérent.** Les variables administrateur DOIVENT être soit totalement absentes lorsque le rôle l'autorise, soit fournies sous la forme complète exigée par `ansible-role-grav-site`.

Un site actif peut, en complément du bootstrap administrateur, nécessiter un ou plusieurs fichiers secrets applicatifs (par exemple une clé d'un plugin d'envoi de courriel), distincts des identifiants de compte. `ansible-role-grav-site` expose cette capacité par sa variable publique `grav_secrets` : une liste d'éléments fournissant chacun un nom de fichier et, au choix, un chemin source sur le contrôleur ou un contenu inline. `grav-sites-ops` transmet cette liste depuis le même vault global, sous la même entrée `vault_grav_sites[inventory_hostname]` que les identifiants administrateur, et n'utilise que la forme à contenu inline — jamais un chemin de fichier local, qui réintroduirait une source de secret hors du vault unique (GSO-REQ-022).

```yaml
vault_grav_sites:
  grav-example:
    admin_user: example-admin
    admin_password: valeur-secrète
    admin_email: admin@example.invalid
    admin_fullname: Example Administrator
    admin_title: Administrator
    admin_language: fr
    admin_type: both
    secrets:
      - name: email-private.php
        content: |
          contenu secret synthétique
```

**GSO-REQ-203 — Secrets applicatifs par site.** Un site actif PEUT déclarer une liste `secrets` dans `vault_grav_sites[inventory_hostname]`. Chaque élément DOIT fournir exactement `name` (identifiant de fichier, validé selon la même forme que `ansible-role-grav-site` : lettres, chiffres, `.`, `_` ou `-`, jamais `..`, `/` ni `:`) et `content` (contenu inline). La forme `src` de l'interface du rôle NE DOIT PAS être utilisée par `grav-sites-ops`. Cette liste DOIT être traduite telle quelle vers la variable publique `grav_secrets` du rôle, sans transformation. `name` et `content` DOIVENT rester associés au sein d'un même élément du vault, jamais répartis entre le vault et le registre non secret ; le registre non secret `grav_sites.yml` NE DOIT PAS contenir cette liste ni aucun de ses éléments.

### 9.5 Responsabilités conservées par le rôle

L'orchestrateur ne doit pas décider :

- comment construire la référence Docker effective ;
- comment appliquer la politique de pull ;
- comment créer les répertoires ;
- comment rendre Compose ou `grav.env` ;
- comment contrôler le compte administrateur ;
- comment attendre le healthcheck ;
- comment écrire `.deployed_state.yml` et le journal de versions.

Il fournit des entrées ; le rôle garantit le mécanisme et produit l'état appliqué.

### 9.6 État retourné et contrôle

`grav-sites-ops` peut lire les fichiers d'état publics produits par le rôle afin de comparer :

- la référence désirée dans le registre ;
- la référence effective consignée sur la VM ;
- l'état réel du conteneur et de l'endpoint HTTP.

Il ne doit pas modifier directement ces fichiers ni les considérer comme une nouvelle source d'état désiré.

**GSO-REQ-063 — Sens unique de l'état.** Les fichiers produits par le rôle PEUVENT servir de preuve, mais NE DOIVENT PAS réécrire automatiquement le registre central.

### 9.7 Compatibilité contrôlée

Toute variable transmise doit exister dans l'interface publique de la version épinglée. La CI doit détecter les variables obsolètes, inconnues ou renommées avant un déploiement réel.

**GSO-REQ-064 — Contrat vérifié.** Les tests de `grav-sites-ops` DOIVENT installer réellement la version épinglée du rôle et vérifier au minimum le parsing, la syntaxe et la traduction des variables sur un site fictif.

---

## 10. Réseau et publication

### 10.1 Réseau local comme frontière de livraison

Le résultat attendu d'un déploiement est une instance Grav saine et accessible depuis le réseau local à l'adresse et au port déclarés dans le registre.

Le rôle reçoit une adresse IPv4 explicite. `0.0.0.0` peut être utilisé si cette décision est volontaire et conforme au contrat du rôle, mais une adresse LAN précise devrait être préférée afin de limiter l'exposition de l'instance.

**GSO-REQ-065 — Endpoint LAN explicite.** Chaque site actif DOIT posséder un `bind_address` et un `http_port` explicites, validés avant déploiement.

### 10.2 Santé locale

Le contrôle de santé utilise l'endpoint local défini par l'image et le rôle. Il ne dépend pas d'un domaine public, de DNS, de TLS ou du reverse proxy.

Une instance peut être considérée correctement déployée même si elle n'est pas publiée sur Internet, dès lors que son conteneur est sain et que son endpoint local répond conformément au rôle.

**GSO-REQ-066 — Santé indépendante d'Internet.** Les vérifications de `grav-sites-ops` DOIVENT être réalisables sans accès Internet entrant et sans domaine public.

### 10.3 Publication ultérieure

Lorsqu'un site doit être publié, l'opérateur exécute séparément le `control-repository` avec les informations qui lui sont propres : domaine, hôte upstream et port upstream.

Cette opération humaine peut avoir lieu immédiatement, ultérieurement ou jamais. `grav-sites-ops` n'enregistre pas son résultat comme condition de l'état du site.

### 10.4 Absence d'échange automatique

Sont interdits :

- un `set_stats` destiné au `control-repository` ;
- un fichier généré automatiquement pour lui transmettre des variables ;
- un sous-module Git entre les deux dépôts ;
- un déclenchement de workflow croisé ;
- un appel de playbook du `control-repository` depuis `grav-sites-ops` ;
- une exigence de domaine public dans le registre Grav.

**GSO-REQ-067 — Zéro transmission automatique.** Aucun mécanisme automatique NE DOIT transmettre l'adresse, le port ou l'identité d'un site de `grav-sites-ops` vers le `control-repository`.

### 10.5 Arrêt ou retrait d'un site publié

Si un site publié est arrêté ou retiré, la suppression de sa publication relève d'une procédure séparée dans le `control-repository`. L'orchestrateur Grav peut rappeler cette étape dans sa documentation, mais ne doit pas la réaliser.

L'indépendance implique qu'un oubli humain peut laisser une route proxy pointant vers un upstream indisponible. Ce risque doit être traité par les procédures d'exploitation et la supervision, non par un couplage automatique des dépôts.

### 10.6 Informations réseau dans Git

Les adresses LAN réelles de production peuvent être suivies dans l'inventaire privé de `grav-sites-ops`, car elles constituent des paramètres opérationnels non secrets nécessaires à Ansible. Elles ne doivent pas apparaître dans l'inventaire d'exemple, les tests, les logs publics ou la documentation générique.

**GSO-REQ-068 — Exemples non opérationnels.** Toute adresse utilisée dans les exemples et tests DOIT appartenir à un espace documentaire ou être locale au banc de test.

---

## 11. Secrets et bootstrap administrateur

### 11.1 Vault global unique

La première version utilise un seul fichier :

```text
inventories/production/group_vars/all/vault.yml
```

Ce choix évite les chargements fragiles liés au déplacement de fichiers vault hors des emplacements reconnus par Ansible. Le fichier contient deux dictionnaires :

```yaml
vault_grav_sites:
  grav-example:
    admin_user: example-admin
    admin_password: valeur-secrète
    admin_email: admin@example.invalid
    admin_fullname: Example Administrator
    admin_title: Administrator
    admin_language: fr
    admin_type: both
    secrets:
      - name: email-private.php
        content: |
          contenu secret synthétique

vault_retired_grav_sites: {}
```

Après le retrait d'un projet, ses secrets archivés prennent la forme suivante, dans un second exemple distinct de l'exemple actif ci-dessus :

```yaml
vault_grav_sites: {}

vault_retired_grav_sites:
  grav-example:
    admin_user: example-admin
    admin_password: valeur-secrète
    admin_email: admin@example.invalid
    admin_fullname: Example Administrator
    admin_title: Administrator
    admin_language: fr
    admin_type: both
    secrets:
      - name: email-private.php
        content: |
          contenu secret synthétique
```

Ce second bloc illustre l'état obtenu **après** retrait : l'entrée n'existe alors que sous `vault_retired_grav_sites` et ne doit jamais coexister avec une entrée active correspondante sous `vault_grav_sites`, conformément à GSO-REQ-073.

Des commentaires internes doivent séparer lisiblement les projets lors de l'édition déchiffrée.

`admin_fullname`, `admin_title`, `admin_language` et `admin_type` ne sont pas, isolément, des valeurs confidentielles. Leur regroupement dans le vault avec `admin_user`/`_password`/`_email` est une **simplification volontaire** : elle garantit une traduction atomique vers le bootstrap du rôle et évite toute jointure entre le registre non secret et le vault — ce n'est pas une affirmation que chacun de ces champs est intrinsèquement secret.

### 11.2 Stockage et accès

Le vault opérationnel doit :

- être chiffré avec Ansible Vault ;
- avoir des permissions locales restrictives ;
- être ignoré par Git ;
- être sauvegardé séparément selon une procédure opérateur ;
- ne jamais être copié dans un artefact CI ;
- ne jamais être utilisé par l'inventaire d'exemple.

Le mot de passe permettant d'ouvrir le vault ne doit pas être stocké dans le dépôt. Son mode de fourniture appartient à l'environnement opérateur.

**GSO-REQ-069 — Vault local protégé.** Le dépôt DOIT ignorer explicitement le vault réel et tout fichier temporaire produit par son édition.

**GSO-REQ-070 — Sauvegarde avant migration.** Toute migration, restructuration ou suppression du vault historique DOIT être précédée d'une sauvegarde externe vérifiée. Cette exigence est satisfaite par une preuve documentaire (rapport d'opérateur daté, conforme à §20.3) et n'est pas vérifiable par un test automatisé.

### 11.3 Sémantique des identifiants administrateur

Les identifiants transmis au rôle servent au bootstrap d'une instance non initialisée et au respect de sa garde administrateur. Ils ne constituent pas nécessairement un mécanisme de rotation du mot de passe d'un compte déjà persistant.

Lorsque le volume `accounts` contient déjà un compte, les données persistantes sont souveraines. La présence d'anciennes valeurs dans un fichier d'environnement rendu ne signifie pas que ces valeurs sont encore les identifiants effectifs du compte Grav.

L'orchestrateur ne doit ni lire le contenu des fichiers de compte, ni tenter d'en déduire ou d'en modifier le mot de passe.

**GSO-REQ-071 — Pas de rotation implicite.** Modifier une valeur administrateur dans le vault NE DOIT PAS être présenté comme une rotation garantie d'un compte Grav existant.

### 11.4 Cas d'une instance initialisée

Pour une instance dont le volume `accounts` est intact, le rôle applique son contrat de garde et de vérification. `grav-sites-ops` lui transmet les valeurs prévues par sa politique sans réimplémenter la détection des comptes.

Une mise à jour d'image ne doit pas recréer le compte ni écraser le fichier présent dans le volume.

### 11.5 Cas d'une instance non initialisée

Pour une première installation ou après perte du volume `accounts`, l'ensemble complet de bootstrap exigé par le rôle doit être disponible. L'absence de compte et l'absence d'identifiants complets doivent entraîner un refus avant mutation, conformément au contrat du rôle.

**GSO-REQ-072 — Bootstrap sûr.** `grav-sites-ops` NE DOIT PAS contourner la garde empêchant le démarrage d'une instance Grav non initialisée sans identifiants complets.

### 11.6 Archivage des secrets d'un projet retiré

Lors du retrait d'un projet, son entrée est déplacée, dans le même vault, de `vault_grav_sites` vers `vault_retired_grav_sites`. Cette opération conserve la possibilité de redémarrer la VM et de réactiver le projet sans perdre la correspondance avec le volume `accounts`.

Les secrets archivés ne doivent jamais être copiés dans `registry/retired-sites.yml`.

**GSO-REQ-073 — Secrets retirés hors ensemble actif.** Un projet absent de l'inventaire actif NE DOIT PAS conserver une entrée dans `vault_grav_sites` ; ses secrets conservés DOIVENT être déplacés vers `vault_retired_grav_sites`.

### 11.7 Non-divulgation

Les opérations manipulant le vault doivent utiliser les protections Ansible adaptées. Les messages d'erreur peuvent identifier l'hôte concerné mais ne doivent afficher ni valeur, ni dictionnaire secret, ni structure susceptible de révéler un identifiant.

Les tests doivent inclure des marqueurs synthétiques afin de prouver leur absence dans :

- les logs Ansible ;
- les sorties CI ;
- les fichiers d'état ;
- les journaux de versions ;
- les templates non secrets ;
- les fichiers suivis par Git.

**GSO-REQ-074 — Test de non-fuite.** La CI DOIT comporter un contrôle automatique empêchant le suivi ou l'affichage de valeurs ressemblant aux secrets synthétiques de test.

---

## 12. Persistance et cycle de vie du contenu

### 12.1 Principe prioritaire

La première règle d'exploitation est la conservation du contenu du site. Les quatre ensembles persistants sont :

```text
pages
accounts
data
images
```

Leur cycle de vie est indépendant de celui de l'image applicative et de celui du rôle.

**GSO-REQ-075 — Persistance prioritaire.** Toute opération de déploiement, mise à jour, redémarrage, arrêt ou rollback DOIT préserver les quatre ensembles persistants.

### 12.2 Propriété des données

Les volumes présents sur la VM constituent l'état vivant du site :

- `pages` contient le contenu éditorial ;
- `accounts` contient les comptes effectifs ;
- `data` contient les données persistantes produites par Grav et ses extensions ;
- `images` contient les médias persistants.

`grav-sites-ops` référence les chemins nécessaires au rôle mais ne devient pas propriétaire du contenu des fichiers.

Les thèmes, plugins, configurations versionnées et autres éléments applicatifs qui appartiennent à l'image restent sous la responsabilité du dépôt applicatif.

### 12.3 Mise à jour d'une image

Mettre à jour un site consiste à modifier dans `grav_sites.yml` sa version applicative et, le cas échéant, son digest, puis à redéployer explicitement l'hôte avec `--limit`.

Cette opération change le logiciel exécuté. Elle ne synchronise pas le contenu et ne remplace pas les volumes par les données contenues dans l'image.

### 12.4 Rollback d'image

Un rollback consiste à revenir, dans Git, à une référence applicative précédemment approuvée puis à invoquer de nouveau le rôle.

Il ne restaure pas automatiquement l'état antérieur des volumes. Cette distinction est essentielle lorsqu'une mise à jour de plugin ou de Grav a fait évoluer les données persistantes.

**GSO-REQ-076 — Rollback limité à l'image.** Un rollback orchestré DOIT changer uniquement la référence applicative demandée et préserver les volumes dans leur état courant.

### 12.5 Incompatibilité entre logiciel et contenu

Si une nouvelle version de plugin casse le contenu du site, le processus opérationnel peut comprendre :

1. un rollback temporaire de l'image ;
2. l'adaptation du contenu dans le dépôt du site sur la workstation ;
3. un commit et un nouveau tag applicatif ;
4. le déploiement de cette nouvelle image ;
5. une comparaison explicite entre le dépôt et les volumes ;
6. une synchronisation déclenchée manuellement dans le sens approprié.

Les étapes 2, 5 et 6 restent hors de `grav-sites-ops`. L'orchestrateur ne doit pas deviner quelle version du contenu est correcte.

### 12.6 Synchronisation explicite

Les scripts de synchronisation dépôt vers VM et VM vers dépôt sont des outils externes. Ils doivent :

- être exécutés volontairement ;
- afficher les différences avant écriture lorsque cela est possible ;
- définir clairement la source et la destination ;
- prévoir une sauvegarde avant toute synchronisation destructive ;
- ne jamais être déclenchés comme effet secondaire d'un playbook de déploiement.

**GSO-REQ-077 — Pas de `rsync` implicite.** Aucun playbook de `grav-sites-ops` NE DOIT exécuter automatiquement un script de synchronisation du contenu.

### 12.7 Sauvegarde et restauration

La sauvegarde et la restauration des quatre ensembles persistants restent hors du mécanisme de déploiement. Les procédures d'exploitation doivent néanmoins exiger une sauvegarde vérifiée avant :

- une migration de VM ;
- une modification majeure susceptible de transformer les données ;
- une synchronisation écrasante ;
- un retrait définitif envisagé ;
- toute opération manuelle sur le volume `accounts`.

`grav-sites-ops` peut documenter ou vérifier l'existence déclarative d'une sauvegarde, mais ne doit pas annoncer qu'un déploiement constitue une sauvegarde.

**GSO-REQ-078 — Déploiement distinct de la sauvegarde.** Le succès d'un playbook NE DOIT PAS être interprété ou documenté comme une preuve de sauvegarde des volumes.

### 12.8 Retrait et conservation

Lorsqu'un projet est retiré, ses volumes restent sur sa VM préservée. `registry/retired-sites.yml` enregistre leur statut déclaré sans prétendre vérifier leur contenu.

La réactivation doit réutiliser les mêmes chemins persistants et les secrets archivés correspondant au compte existant, sauf procédure explicite de restauration ou de migration.

### 12.9 Interdictions destructives

La première version ne doit contenir aucune tâche utilisant une suppression récursive, une recréation forcée de volume ou une commande Docker supprimant les volumes d'un projet.

**GSO-REQ-079 — Absence de destruction automatisée.** Les playbooks opérationnels NE DOIVENT invoquer ni `docker compose down --volumes`, ni `docker volume prune`, ni suppression récursive des répertoires persistants.

### 12.10 Preuves attendues

Les tests de l'orchestrateur doivent démontrer que :

- les quatre chemins persistants sont transmis sans transformation inattendue ;
- une mise à jour de version ne change pas ces chemins ;
- un rollback de version ne change pas ces chemins ;
- le retrait d'une entrée active ne déclenche aucune tâche de suppression ;
- les playbooks ne contiennent aucune commande destructive interdite.

**GSO-REQ-080 — Couverture de persistance.** La conformité de la persistance DOIT être vérifiée par des tests statiques et par au moins un scénario d'orchestration représentatif.

---

## 13. Playbooks et opérations autorisées

### 13.1 Interface opérateur

La première version fournit des opérations simples, nommées selon leur intention et séparées selon qu'elles lisent ou modifient l'état.

| Playbook | Nature | Cible | Effet attendu |
|---|---|---|---|
| `deploy-site.yml` | Mutante | Exactement un hôte | Déployer ou mettre à jour l'instance selon le registre |
| `restart-site.yml` | Mutante | Exactement un hôte | Redémarrer l'instance sans modifier sa référence désirée |
| `stop-site.yml` | Mutante | Exactement un hôte | Arrêter le conteneur sans retirer le projet ni arrêter la VM |
| `check-site.yml` | Lecture | Exactement un hôte | Comparer état désiré, état appliqué et état réel |
| `check-all.yml` | Lecture | Groupe `grav_servers` | Produire une vue de l'ensemble du parc actif |

La première version ne requiert pas de `deploy-all.yml`. Son ajout ultérieur constitue une opération à risque qui devra recevoir des garde-fous et des tests propres.

**GSO-REQ-081 — Un playbook, une intention.** Chaque playbook opérationnel DOIT correspondre à une seule intention clairement documentée.

**GSO-REQ-082 — Pas de déploiement global implicite.** Aucun playbook ciblé NE DOIT devenir un déploiement global lorsque `--limit` est absent.

### 13.2 Point d'entrée supporté

Les opérations courantes doivent être exposées par le `Makefile`. L'opérateur fournit l'identifiant exact de l'hôte au moyen de `SITE`, lequel est transmis à Ansible sous la forme d'un `--limit`.

Exemples d'interface :

```bash
make deploy SITE=grav-gites
make check SITE=grav-gites
make restart SITE=grav-gites
make stop SITE=grav-gites
make check-all
```

Le Makefile ne remplace pas Ansible. Il standardise l'inventaire, le playbook et les contrôles locaux nécessaires à une exécution sûre.

**GSO-REQ-083 — Site obligatoire.** Les cibles `deploy`, `check`, `restart` et `stop` DOIVENT refuser une variable `SITE` absente ou vide.

**GSO-REQ-084 — Site littéral.** `SITE` DOIT être traité comme un nom d'hôte d'inventaire exact, jamais comme une commande shell ou une expression libre non contrôlée.

### 13.3 Validation locale du sélecteur

Ansible peut terminer sans échec lorsqu'un motif `--limit` ne correspond à aucun hôte. Le point d'entrée supporté doit donc valider la cible avant d'appeler `ansible-playbook`.

Un script dédié, par exemple `scripts/validate-target.sh`, ou une logique équivalente du Makefile doit :

1. valider la forme de `SITE` ;
2. interroger explicitement `inventories/production/hosts.yml` avec `ansible-inventory` ;
3. vérifier que le nom correspond à exactement un hôte ;
4. vérifier son appartenance à `grav_servers` ;
5. vérifier sa présence dans le registre actif ;
6. refuser `all`, un groupe, un motif, une liste et toute sélection multiple ;
7. terminer avec un code non nul avant `ansible-playbook` en cas d'écart.

**GSO-REQ-085 — Préflight à deux niveaux.** La cible DOIT être validée localement avant l'appel du playbook ; ce niveau local est seul à garantir la détection d'une limite sélectionnant zéro hôte ou un hôte inconnu. Le playbook DOIT en outre revalider, avant toute mutation, qu'exactement un hôte a été sélectionné pour la play en cours — ce second contrôle est fiable pour une sélection de plusieurs hôtes, mais ne se substitue pas au niveau local pour le cas zéro hôte. La valeur `SITE` DOIT respecter l'expression régulière fermée `^[a-z][a-z0-9-]*$`. Elle DOIT être transmise à chaque commande au moyen d'un mécanisme de citation empêchant toute interprétation par le shell. Le validateur DOIT utiliser exclusivement `inventories/production/hosts.yml`, résoudre exactement un nom d'hôte actif et terminer avec un code non nul avant tout appel à `ansible-playbook` en cas d'écart.

**GSO-REQ-086 — Cible inconnue en échec.** Une valeur `SITE` inconnue DOIT produire un échec explicite ; un succès vide est interdit.

### 13.4 Déploiement et mise à jour

`deploy-site.yml` sélectionne `grav_sites[inventory_hostname]`, récupère les secrets correspondant au même hôte et invoque `sepp67.grav_site` avec l'état `started` ou l'état déclaré.

Le playbook ne doit pas contenir de tâches Docker ou Grav qui appartiennent au rôle. Il peut effectuer des assertions propres à l'orchestrateur avant `include_role`.

Avant cette invocation, le playbook vérifie localement — sans afficher de valeur — que l'hôte possède une entrée cohérente dans le registre et dans le vault, y compris ses éventuels secrets applicatifs. Ce contrôle est distinct de la validation de cible (GSO-REQ-085) : il porte sur le contenu structurel des données de l'hôte déjà sélectionné, pas sur son identité.

**GSO-REQ-087 — Invocation unique.** Pour un hôte sélectionné, `deploy-site.yml` DOIT invoquer `sepp67.grav_site` exactement une fois.

**GSO-REQ-204 — Cohérence structurelle vérifiée avant déploiement.** `deploy-site.yml` DOIT, avant d'invoquer `sepp67.grav_site`, vérifier localement que l'hôte sélectionné possède une entrée `grav_sites`, une entrée `vault_grav_sites` correspondante, un ensemble de bootstrap conforme à GSO-REQ-062, et — si présents — des éléments `secrets` structurellement valides selon GSO-REQ-203. Ce contrôle NE DOIT afficher aucune valeur, DOIT utiliser `no_log` pour toute donnée sensible manipulée, et NE DOIT produire qu'un verdict et un message générique en cas d'écart.

### 13.5 Redémarrage

`restart-site.yml` utilise l'interface publique du rôle pour demander un redémarrage. Il ne doit ni tirer implicitement une image différente, ni modifier le registre, ni changer les volumes.

Un redémarrage est une opération transitoire ; l'état désiré demeure celui du registre.

**GSO-REQ-088 — Redémarrage sans changement de version.** Le redémarrage NE DOIT modifier ni `version`, ni `digest`, ni les fichiers persistants.

### 13.6 Arrêt du conteneur

`stop-site.yml` arrête l'instance gérée sur une VM encore active et inventoriée. Il ne retire pas le site du registre, n'arrête pas la VM et ne modifie pas sa publication éventuelle.

**GSO-REQ-089 — Arrêt réversible.** `stop-site.yml` NE DOIT supprimer ni conteneur, ni volume, ni répertoire persistant.

Le prochain `deploy-site.yml` peut remettre l'instance dans son état désiré normal.

### 13.7 Contrôle ciblé et global

`check-site.yml` vérifie un seul hôte afin de conserver la même interface que les opérations mutantes. `check-all.yml` constitue l'unique interface prévue pour parcourir tout le parc.

Ces playbooks ne doivent pas corriger automatiquement les écarts constatés. Ils produisent des faits et un verdict.

**GSO-REQ-090 — Contrôle sans remédiation.** Une opération `check` NE DOIT déclencher ni rendu de fichier, ni pull, ni démarrage, ni redémarrage. Elle NE DOIT PAS invoquer `sepp67.grav_site` par `include_role` ou `import_role`, ce rôle réécrivant son état structuré à chaque invocation même idempotente. L'inspection DOIT être réimplémentée indépendamment, en lecture seule, au moyen de modules Ansible et Docker génériques.

### 13.8 Mode `--check`

Le mode Ansible `--check` peut être proposé comme vérification complémentaire, mais il ne constitue pas une preuve de déploiement ou de santé Docker. Toute tâche qui ne peut pas fournir un résultat fiable dans ce mode doit le documenter clairement.

**GSO-REQ-091 — Pas de faux succès en check mode.** La documentation NE DOIT PAS présenter `--check` comme équivalent à un déploiement fonctionnel.

### 13.9 Vault et interaction

Les commandes peuvent utiliser `--ask-vault-pass` ou un mécanisme local explicitement configuré par l'opérateur. Le Makefile ne doit contenir ni mot de passe, ni chemin vers un fichier de mot de passe propre à une workstation.

**GSO-REQ-092 — Secret absent des commandes.** Les exemples de commandes NE DOIVENT jamais passer une valeur secrète avec `--extra-vars` ou dans la ligne de commande.

### 13.10 Résultat des opérations

Chaque opération doit se terminer par un verdict non ambigu : succès, échec de préflight, hôte injoignable, rôle en échec, instance non saine ou dérive détectée.

**GSO-REQ-093 — Codes de sortie fiables.** Toute condition empêchant d'atteindre l'intention du playbook DOIT produire un code de sortie non nul.

---

## 14. Sécurité opérationnelle

### 14.1 Refus par défaut

La sécurité repose sur une règle simple : une intention ambiguë ne déclenche aucune mutation.

Sont notamment refusés :

- inventaire absent ;
- `SITE` absent ou vide ;
- `--limit` absent ;
- `--limit all` ;
- nom de groupe utilisé comme cible ;
- motif sélectionnant plusieurs hôtes ;
- cible inconnue ;
- définition de site absente ;
- secrets requis absents ;
- référence applicative invalide.

**GSO-REQ-094 — Ambiguïté non mutante.** Toute ambiguïté de cible ou de configuration DOIT arrêter l'exécution avant la première tâche mutante.

### 14.2 Ordre du préflight

Le préflight se déroule dans l'ordre suivant :

1. contrôles locaux de dépôt et de paramètres ;
2. résolution de l'inventaire ;
3. validation de la cible unique ;
4. cohérence structurelle inventaire–registre–vault, sans affichage de valeur (GSO-REQ-204) ;
5. validation des valeurs non secrètes ;
6. seulement ensuite, connexion à la VM ;
7. invocation du rôle, qui exécute ses propres validations avant mutation.

**GSO-REQ-095 — Validation locale prioritaire.** Les erreurs détectables localement NE DOIVENT PAS nécessiter une connexion SSH pour être révélées.

### 14.3 Concurrence

Une VM étant dédiée à un projet, les opérations ciblées doivent s'exécuter avec une concurrence limitée à une cible. Deux opérations mutantes simultanées sur le même hôte sont interdites.

La première version n'a pas l'obligation d'implémenter un verrou distribué, mais elle doit documenter cette interdiction et éviter tout parallélisme implicite.

**GSO-REQ-096 — Une mutation à la fois.** L'opérateur NE DOIT PAS lancer simultanément deux opérations mutantes sur le même site.

### 14.4 Élévation de privilèges

Les privilèges doivent être limités au play qui les nécessite. Les validations exécutées sur le contrôleur doivent utiliser `become: false`. Les mots de passe d'élévation ne doivent pas être stockés dans les fichiers suivis.

**GSO-REQ-097 — Privilèges minimaux.** Une tâche locale de préflight NE DOIT PAS s'exécuter avec des privilèges élevés.

**Précision (audit privilèges 2026-09, suite au premier déploiement réel de
`grav-platform-docs`) :** GSO-REQ-097 vise strictement les tâches
*locales*, déléguées au contrôleur (`delegate_to: localhost` dans
`playbooks/_shared/mutate.yml` — validation registre/vault/secrets). Il ne
s'applique **pas** à l'invocation distante de `sepp67.grav_site` : ce rôle
exige `become: true` au niveau du play qui l'invoque depuis sa toute
première version (voir son README « Prérequis ») et n'escalade jamais ses
propres privilèges en interne. `deploy-site.yml`, `restart-site.yml` et
`stop-site.yml` passent donc `become: true` au niveau du play — la seule
tâche locale (`_shared/mutate.yml`, préflight structurel délégué) reste
explicitement `become: false`, conformément à GSO-REQ-097. Avant l'audit,
ces trois playbooks portaient `become: false` au niveau du play entier, sur
la foi d'un commentaire non vérifié affirmant que « le rôle escalade au
besoin » — faux : cette confusion entre le périmètre de GSO-REQ-097 (le
préflight local) et l'invocation distante du rôle est la cause racine des
échecs du premier déploiement réel (facts absents, accès Docker refusé,
`/opt/<site>` non créable, `chown` des secrets refusé).

Le compte technique utilisé pour la connexion SSH (fourni par Cloud-init
sur chaque VM, nom variable — voir inventaire) n'a besoin d'aucune
appartenance à un groupe particulier, notamment **pas** le groupe `docker` :
`sudo` (idéalement NOPASSWD, pour l'automatisation non interactive) suffit,
aussi bien pour les tâches système du rôle que pour les commandes Docker.

Un contrôle distant explicite (identité SSH puis `become: true` effectif,
avant toute tâche privilégiée) a été envisagé *dans `_shared/mutate.yml`*
et délibérément écarté : toute tâche de ce fichier qui contacterait
réellement la cible romprait l'isolation dont dépendent GSO-T13/GSO-T14
(chemin opérateur réel avec une DOUBLURE de `sepp67.grav_site`, jamais de
connexion — GSO-REQ-087) et, pour GSO-T19/GSO-T20, empêcherait de
distinguer un échec de privilège d'une cible réellement `UNREACHABLE`.
Ce diagnostic actionnable est donc fourni par le rôle lui-même
(`tasks/privilege_guard.yml`, importé tôt dans `sepp67.grav_site`, juste
après la validation des variables) — lui correctement remplacé par la
doublure dans ces mêmes tests, puisqu'il fait partie du rôle substitué.

`playbooks/_shared/observe.yml` (partagé par `check-site.yml` et
`check-all.yml`, STRICTEMENT non mutants — GSO-REQ-090) reste `become:
false` au niveau du play : seule sa tâche `docker inspect` (lecture seule)
porte un `become: true` local, justifié par la même absence
d'appartenance au groupe `docker` — les autres lectures de cette séquence
(`.deployed_state.yml`, mode `0644` ; `stat` de `.last_failure.log`, qui ne
nécessite qu'un droit de traversée de répertoire, jamais la lecture de son
contenu `0600`) n'en ont jamais eu besoin.

**Historique de cette décision (test d'acceptation réel, VM Proxmox
dédiée, 2026-09-16) :** un `become: true` scopé ici avait d'abord été
retiré, par crainte que `sudo` (qui réinitialise `PATH` via `secure_path`)
rende injoignable la fausse CLI Docker utilisée par GSO-T19/GSO-T20. Un
déploiement réel sur une VM dédiée a ensuite démontré que **sans**
`become` ici, `check`/`check-all` ne peuvent JAMAIS observer l'état réel
du conteneur pour un compte sans groupe `docker` — `docker_unavailable`
→ `UNKNOWN` n'est alors pas une dégradation gracieuse occasionnelle, c'est
le résultat systématique, ce qui vide ces deux commandes de leur fonction.
`become: true` a donc été restauré. La crainte initiale sur `secure_path`
a été confirmée empiriquement sur la même VM (`sudo docker` résout
toujours `/usr/bin/docker`, jamais un `docker` simplement préfixé au
`PATH`) — la tâche accepte donc un chemin de binaire Docker alternatif via
la variable d'environnement `GSO_TEST_DOCKER_BIN` (lue sur le
contrôleur via `lookup(env)`, jamais sur la cible — même mécanisme que
`GSO_SPY_OUTPUT` dans `tests/lib/spy-role`), que GSO-T19/GSO-T20
positionnent sur le chemin ABSOLU de leur fausse CLI pour rester
joignable sous `sudo`. En production, la variable est absente : le
binaire reste `docker`, résolu par `secure_path` vers le vrai binaire.

### 14.5 Protection du vault

Le `.gitignore` doit couvrir le vault réel, ses sauvegardes temporaires et les fichiers d'édition susceptibles de contenir du texte déchiffré. Les permissions locales attendues doivent être documentées.

La CI doit échouer si elle détecte un `vault.yml` opérationnel suivi, même si son contenu paraît chiffré.

**GSO-REQ-098 — Garde Git du vault.** Un contrôle automatique DOIT refuser tout fichier de vault réel ajouté à l'index Git.

### 14.6 Protection contre les données locales

Le dépôt suivi ne doit contenir :

- aucun chemin `/home/...`, `/workspace/...`, `/Users/...` ou équivalent ;
- aucun lien symbolique pointant hors du dépôt ;
- aucun `file://` utilisé comme dépendance opérationnelle ;
- aucun fichier `.env` réel ;
- aucune clé privée ou jeton.

**GSO-REQ-099 — Portabilité du dépôt.** La CI DOIT détecter les chemins absolus de workstation et les liens symboliques externes.

### 14.7 Inventaire de production

Les adresses LAN réelles peuvent être suivies dans l'inventaire privé, mais la CI ne doit pas les contacter. Les tests qui recherchent des adresses privées doivent distinguer l'inventaire de production, où elles sont légitimes, des exemples et fixtures, où elles sont interdites.

**GSO-REQ-100 — Contrôle contextuel des IP.** Un garde-fou NE DOIT PAS rejeter les adresses LAN nécessaires dans `inventories/production/`, mais DOIT les refuser dans `inventories/example/`, `tests/` et la documentation générique.

### 14.8 Journalisation sûre

Les tâches manipulant `vault_grav_sites`, les variables `grav_admin_*` ou d'autres secrets doivent utiliser `no_log` lorsque leur résultat pourrait exposer une valeur.

Les erreurs doivent rester actionnables : elles indiquent le nom du site, la catégorie d'erreur et la correction attendue, sans afficher le dictionnaire secret.

**GSO-REQ-101 — Erreur utile sans fuite.** La protection des secrets NE DOIT PAS réduire toutes les erreurs à un message inexploitable.

### 14.9 Protection des volumes

Les contrôles statiques doivent refuser toute commande connue comme destructive pour les données persistantes, notamment :

```text
docker compose down --volumes
docker volume prune
rm -rf sur un chemin persistant
```

**GSO-REQ-102 — Garde destructif.** La CI DOIT rechercher les opérations destructives interdites dans les playbooks, scripts et cibles Makefile.

### 14.10 Dépendances

Les dépendances Ansible doivent être épinglées. Leur source doit être explicite et utiliser un protocole attendu. Une modification de source ou de tag fait l'objet d'une revue visible.

**GSO-REQ-103 — Dépendances vérifiables.** La CI DOIT valider que `requirements.yml` n'utilise ni branche flottante, ni chemin local, ni référence vide.

### 14.11 Opérations globales

`check-all.yml` est non mutant. Toute future mutation globale devra exiger une autorisation volontaire distincte, par exemple une variable de confirmation littérale, en plus d'un playbook explicitement nommé.

**GSO-REQ-104 — Confirmation globale.** Une future opération mutante globale NE DEVRA PAS pouvoir être lancée par la même interface qu'une opération ciblée.

### 14.12 État sale du dépôt

Une opération de lecture peut être exécutée depuis un dépôt modifié à des fins de diagnostic. Une opération mutante devrait refuser un arbre Git sale, sauf procédure d'urgence documentée et assumée.

**GSO-REQ-105 — État désiré traçable.** Un déploiement normal DEVRAIT partir d'un état Git propre et d'une configuration commitée.

### 14.13 Limites de l'automatisation

`grav-sites-ops` ne contourne ni un échec SSH, ni une validation du rôle, ni un healthcheck rouge. Il ne transforme pas ces conditions en avertissements afin de poursuivre.

**GSO-REQ-106 — Échec non masqué.** `ignore_errors`, `failed_when: false` ou `continue-on-error` NE DOIVENT PAS masquer l'échec d'une opération critique.

### 14.14 Preuve d'absence de contact

Les tests des garde-fous doivent démontrer qu'une commande refusée n'a ouvert aucune connexion vers une VM du parc.

**GSO-REQ-107 — Refus avant SSH.** Le test d'une cible absente, inconnue ou multiple DOIT prouver que le rôle n'a pas été invoqué et qu'aucune cible distante n'a été contactée.

### 14.15 Sécurité de la chaîne de publication

Les commandes de déploiement ne doivent jamais déclencher automatiquement un push Git, un tag, une release ou une construction d'image.

**GSO-REQ-108 — Exploitation distincte de la publication.** Une opération Ansible NE DOIT PAS modifier un dépôt distant ou un registre d'images.

---

## 15. Mise à jour et rollback

### 15.1 Mise à jour déclarative

Une mise à jour commence par une modification de `grav_sites.yml`, jamais par un tag passé uniquement en ligne de commande.

La procédure normale est :

1. identifier la nouvelle image applicative publiée ;
2. vérifier sa version et son digest éventuel ;
3. modifier l'entrée du site dans le registre ;
4. examiner le diff Git ;
5. committer la décision ;
6. exécuter `make check SITE=<hôte>` ;
7. exécuter `make deploy SITE=<hôte>` ;
8. vérifier l'état appliqué et la santé réelle.

**GSO-REQ-109 — Changement dans le registre.** Une version de production NE DOIT PAS être modifiée exclusivement par `--extra-vars` ou une variable d'environnement éphémère.

### 15.2 Version et digest

La version humaine documente la release applicative choisie. Le digest, lorsqu'il est renseigné, fixe les octets de l'image réellement demandée. Les deux informations sont transmises séparément au rôle, qui construit la référence effective.

**GSO-REQ-110 — Digest jamais ignoré.** Lorsqu'un digest est déclaré, l'orchestrateur DOIT le transmettre au rôle sans reconstruire lui-même une référence hybride.

### 15.3 Politique de pull

Le comportement normal conserve la politique de pull définie par le rôle. Un pull forcé doit être une décision explicite et temporaire, représentée par un champ public autorisé.

Un redémarrage ne signifie pas qu'il faut interroger le registre d'images.

**GSO-REQ-111 — Pull explicite.** `force_pull` NE DOIT PAS être activé globalement ou implicitement pour toutes les opérations.

### 15.4 Rollback déclaratif

Un rollback suit le même chemin qu'une mise à jour : il modifie l'état désiré dans Git pour revenir à une version et, le cas échéant, à un digest précédemment approuvés.

La procédure est :

1. identifier la dernière référence applicative connue comme saine ;
2. vérifier sa disponibilité ;
3. modifier `version` et `digest` dans le registre ;
4. committer la décision de rollback ;
5. déployer uniquement l'hôte concerné ;
6. vérifier la santé et l'état effectif ;
7. traiter séparément toute incompatibilité de contenu.

**GSO-REQ-112 — Rollback traçable.** Le retour à une référence antérieure DOIT être visible dans l'historique Git.

### 15.5 Volumes inchangés

Une mise à jour ou un rollback ne modifie pas les chemins persistants. Si les données ont évolué d'une manière incompatible, le rollback de l'image peut ne pas suffire. L'orchestrateur doit signaler cette limite sans restaurer automatiquement les données.

**GSO-REQ-113 — Pas de rollback des données.** Aucun playbook de rollback NE DOIT restaurer ou synchroniser automatiquement `pages`, `accounts`, `data` ou `images`.

### 15.6 Échec et arrêt de la procédure

Si le rôle ou le healthcheck échoue, la procédure s'arrête. L'opérateur examine les diagnostics produits par le rôle avant de décider d'un nouveau déploiement ou d'un rollback.

**GSO-REQ-114 — Pas d'enchaînement aveugle.** Un échec de mise à jour NE DOIT PAS déclencher automatiquement un rollback sans analyse humaine.

### 15.7 Changement de rôle distinct

La mise à jour de `ansible-role-grav-site` ne doit pas être mélangée avec la mise à jour d'une image applicative lors de la même opération normale. Cette séparation permet d'attribuer clairement un éventuel incident.

**GSO-REQ-115 — Une dimension par changement.** Une montée de version du rôle et une montée de version d'un site DEVRAIENT faire l'objet de commits et validations séparés.

### 15.8 Vérification post-opération

Après mise à jour ou rollback, l'opérateur doit comparer la référence désirée et l'`effective_reference` produite par le rôle, puis vérifier le conteneur et l'endpoint HTTP.

**GSO-REQ-116 — Trois états vérifiés.** Une opération réussie DOIT confirmer l'état désiré, l'état appliqué et l'état réel.

### 15.9 Historique

Le journal append-only produit par le rôle est une preuve locale complémentaire. Il ne remplace ni l'historique Git du registre, ni la journalisation externe des opérations.

**GSO-REQ-117 — Historique non réécrit.** `grav-sites-ops` NE DOIT ni tronquer ni recréer le journal de versions maintenu par le rôle.

---

## 16. Traçabilité et contrôle de dérive

### 16.1 Les trois niveaux d'état

L'exploitation distingue :

| Niveau | Source | Question |
|---|---|---|
| État désiré | `grav_sites.yml` au commit courant | Que voulons-nous déployer ? |
| État appliqué | `.deployed_state.yml` et fichiers publics produits par le rôle | Qu'a consigné le dernier déploiement ? |
| État réel | Docker et endpoint HTTP sur la VM | Qu'est-ce qui fonctionne maintenant ? |

Ces trois niveaux peuvent diverger. Le contrôle doit les comparer sans modifier automatiquement l'un à partir de l'autre.

**GSO-REQ-118 — États distincts.** La sortie de contrôle DOIT distinguer explicitement désiré, appliqué et réel.

### 16.2 État désiré

L'état désiré est identifié par :

- le SHA Git de `grav-sites-ops` ;
- le nom d'hôte ;
- l'image ;
- la version déclarée ;
- le digest éventuel ;
- les paramètres structurants de l'instance.

Les secrets ne doivent pas être inclus dans le rapport de traçabilité.

### 16.3 État appliqué

Le contrôle peut lire les champs publics du fichier structuré produit par le rôle, notamment l'image, la version déclarée, le digest, la référence effective et la date de déploiement.

L'absence, l'illisibilité ou l'incohérence de ce fichier doit être signalée comme état inconnu ou dérive, pas corrigée par écriture directe.

**GSO-REQ-119 — État du rôle en lecture seule.** Les playbooks de contrôle NE DOIVENT jamais modifier `.deployed_state.yml`, `.deployed_version` ou `deployed_versions.log`.

### 16.4 État réel

L'état réel comprend au minimum :

- existence du conteneur attendu ;
- image configurée par le conteneur ;
- état `running` ou arrêté ;
- verdict du healthcheck ;
- endpoint local accessible ;
- port publié cohérent avec le registre.

**GSO-REQ-120 — Santé réelle.** La seule présence d'un conteneur NE DOIT PAS suffire à déclarer le site conforme.

### 16.5 Catégories de dérive

Le contrôle doit pouvoir signaler au minimum :

- `IN_SYNC` : les trois états correspondent ;
- `NOT_DEPLOYED` : aucun état appliqué ou conteneur attendu ;
- `REFERENCE_DRIFT` : référence désirée différente de la référence appliquée ou réelle ;
- `CONFIG_DRIFT` : paramètres structurants différents ;
- `STOPPED` : conteneur attendu mais arrêté ;
- `UNHEALTHY` : healthcheck négatif ;
- `UNREACHABLE` : VM non joignable ;
- `UNKNOWN` : preuves insuffisantes ou incohérentes.

Les noms exacts peuvent évoluer, mais leur sémantique doit rester documentée et testable.

**GSO-REQ-121 — Dérive classifiée.** Un contrôle NE DOIT PAS réduire toutes les divergences à un booléen générique. La catégorie `STOPPED` DOIT être déterminée par comparaison avec `grav_sites[host].state` tel que déclaré dans le registre — un site dont l'état désiré est `stopped` et dont le conteneur est effectivement arrêté DOIT être classé `IN_SYNC`, jamais `STOPPED`.

### 16.6 Absence de remédiation automatique

La détection d'une dérive n'autorise pas le playbook de contrôle à déployer ou redémarrer le site. La remédiation exige une commande opérateur distincte.

**GSO-REQ-122 — Lecture séparée de l'action.** Un check en échec DOIT produire un code et un diagnostic, sans appeler `deploy-site.yml`.

### 16.7 Sortie exploitable

La sortie humaine doit identifier le site et le type d'écart sans secret. Une sortie structurée optionnelle peut être produite localement pour audit, mais elle ne doit pas servir de canal automatique vers le `control-repository`.

**GSO-REQ-123 — Rapport sans secret.** Aucun rapport de conformité NE DOIT contenir les variables administrateur, le contenu du vault (y compris les éléments de `secrets`), ou le contenu de `.last_failure.log`. Un rapport de contrôle PEUT signaler la présence et l'horodatage de `.last_failure.log` sur l'hôte cible, mais NE DOIT jamais en afficher ou en transmettre le contenu.

### 16.8 Horodatage et contrôleur

Tout horodatage ajouté par l'orchestrateur doit préciser qu'il provient du contrôleur, sauf preuve contraire. L'orchestrateur ne doit pas activer `gather_facts` uniquement pour obtenir une date.

**GSO-REQ-124 — Pas de facts inutiles.** Les playbooks DOIVENT utiliser `gather_facts: false` lorsque les facts de la cible ne sont pas nécessaires.

### 16.9 Dérive du registre

Les contrôles statiques doivent aussi détecter les incohérences internes : hôte sans site, site sans hôte, secrets actifs orphelins, doublons et projet présent à la fois dans les registres actif et retiré.

**GSO-REQ-125 — Dérive déclarative.** La cohérence du parc DOIT pouvoir être vérifiée sans connexion aux VM.

### 16.10 Aucun retour automatique vers Git

L'état observé sur une VM ne doit jamais modifier automatiquement `grav_sites.yml`, créer un commit ou pousser une branche.

**GSO-REQ-126 — Git sous contrôle humain.** Toute modification de l'état désiré DOIT résulter d'une décision humaine explicite.

---

## 17. Structure normative du dépôt

### 17.1 Arborescence cible

La première version doit tendre vers la structure suivante :

```text
grav-sites-ops/
├── ansible.cfg
├── requirements.yml
├── Makefile
├── inventories/
│   ├── example/
│   │   ├── hosts.yml
│   │   └── group_vars/all/
│   │       ├── grav_sites.yml
│   │       └── vault.yml.example
│   └── production/
│       ├── hosts.yml
│       └── group_vars/all/
│           ├── main.yml
│           ├── grav_sites.yml
│           └── vault.yml
├── playbooks/
│   ├── deploy-site.yml
│   ├── restart-site.yml
│   ├── stop-site.yml
│   ├── check-site.yml
│   └── check-all.yml
├── registry/
│   ├── retired-sites.yml
│   └── reactivated-sites.yml
├── scripts/
│   └── validate-target.sh
├── tests/
├── docs/
│   ├── ARCHITECTURE.md
│   ├── OPERATIONS.md
│   ├── MIGRATION.md
│   └── TEST-RESULTS.md
├── .github/workflows/
│   └── ci.yml
├── .gitignore
├── README.md
└── CHANGELOG.md
```

Le nom exact du script de validation peut évoluer. Sa responsabilité ne doit pas être dispersée entre plusieurs wrappers contradictoires.

### 17.2 Racine du dépôt

La racine contient uniquement les points d'entrée et métadonnées globaux. Elle ne doit pas accumuler des playbooks propres à un site ou des copies du rôle.

**GSO-REQ-127 — Racine lisible.** Les responsabilités principales DOIVENT être identifiables depuis l'arborescence sans connaître un projet particulier.

### 17.3 Inventaires

Les inventaires contiennent la topologie et les variables automatiquement chargées. Aucun sous-répertoire par site n'est requis dans la première version puisque le registre est central.

**GSO-REQ-128 — Registre unique.** Il NE DOIT exister qu'un seul registre actif `grav_sites` pour l'environnement `production`.

### 17.4 Playbooks

Les playbooks restent minces : sélection, préflight, traduction de variables, invocation du rôle ou lecture de l'état. Les tâches partagées peuvent être factorisées dans un répertoire interne clairement nommé, sans créer un nouveau rôle d'orchestration.

**GSO-REQ-129 — Pas de rôle de rôles.** `grav-sites-ops` NE DOIT PAS créer un rôle Ansible qui encapsule `ansible-role-grav-site` et absorbe progressivement l'orchestration.

### 17.5 Scripts

Les scripts servent uniquement aux contrôles locaux difficiles à garantir dans le moteur de playbook, notamment la validation exacte d'un `--limit` avant toute connexion.

Ils doivent être portables sur l'environnement Linux supporté, utiliser un mode strict et ne jamais contenir de secret.

**GSO-REQ-130 — Scripts bornés.** Un script NE DOIT ni déployer directement un conteneur, ni modifier les volumes, ni remplacer le rôle.

### 17.6 Documentation

Le README présente l'installation et les commandes essentielles. Les procédures détaillées sont séparées : architecture, exploitation, migration et résultats de tests.

**GSO-REQ-131 — Documentation cohérente.** Toute commande proposée dans le README DOIT correspondre à un point d'entrée réellement testé.

### 17.7 Fichiers ignorés

`.gitignore` doit couvrir au minimum :

- le vault opérationnel ;
- les fichiers temporaires de vault ;
- les rôles installés localement ;
- les caches Ansible et Molecule éventuels ;
- les fichiers `.retry` ;
- les sorties de diagnostic contenant potentiellement des données d'environnement.

**GSO-REQ-132 — Ignorés testés.** La CI DOIT vérifier que les catégories sensibles prévues ne peuvent pas être suivies accidentellement.

### 17.8 Aucun profil du rôle copié

La migration depuis l'ancien dépôt ne doit pas recopier les playbooks autonomes, templates ou tâches de `ansible-role-grav-site`. Seules les données d'exploitation utiles sont migrées.

**GSO-REQ-133 — Migration de données seulement.** Les fichiers extraits de l'ancien profil DOIVENT être reclassés selon le présent contrat, non copiés en bloc.

### 17.9 Évolutivité

Ajouter un site doit principalement modifier l'inventaire, le registre actif et le vault local. Aucun nouveau playbook propre au site ne doit être nécessaire.

**GSO-REQ-134 — Ajout sans code.** L'ajout normal d'un projet NE DOIT nécessiter aucune modification de playbook ou de script.

### 17.10 Spécialisation

L'arborescence ne doit pas introduire de répertoires `matrix`, `nextcloud` ou génériques destinés à d'autres familles de services.

**GSO-REQ-135 — Dépôt Grav uniquement.** La structure DOIT rester centrée sur les opérations Grav.

---

## 18. Tests et intégration continue

### 18.1 Objectif de preuve

La CI ne cherche pas à administrer un parc réel. Elle démontre que l'orchestrateur sélectionne correctement une cible fictive, charge ses données, protège les secrets et invoque le contrat du rôle sans contact avec la production.

Les tests doivent distinguer présence d'un scénario, exécution réelle et résultat observé.

**GSO-REQ-136 — Preuve observée.** Un test NE DOIT être déclaré conforme que si son exécution et son résultat ont été consignés.

### 18.2 Matrice minimale

La première version doit couvrir au minimum :

| Test | Objet |
|---|---|
| GSO-T01 | Syntaxe YAML, Ansible et inventaires |
| GSO-T02 | `ansible-lint` sans erreur |
| GSO-T03 | Installation du rôle depuis `requirements.yml` |
| GSO-T04 | Référence du rôle épinglée sur un tag |
| GSO-T05 | Inventaire d'exemple parsable |
| GSO-T06 | Registre actif chargé automatiquement |
| GSO-T07 | Correspondance hôte–registre–vault d'exemple |
| GSO-T08 | Refus sans inventaire explicite |
| GSO-T09 | Refus sans `SITE`/`--limit` |
| GSO-T10 | Refus de `all`, groupe, motif et sélection multiple |
| GSO-T11 | Refus d'une cible inconnue ou vide avec code non nul, exercé explicitement sur le validateur local (GSO-REQ-056) |
| GSO-T12 | Aucune connexion distante après refus du préflight |
| GSO-T13 | Traduction correcte du registre et des secrets applicatifs (`grav_secrets`) vers `grav_*` |
| GSO-T14 | Secrets et secrets applicatifs du bon hôte uniquement, aucune fuite, cohérence structurelle registre/vault |
| GSO-T15 | Déploiement fictif d'un seul site, avec conteneur Docker réel |
| GSO-T16 | Deux sites déclarés : isolation des variables et secrets à la traduction, sans conteneur Docker réel |
| GSO-T17 | Mise à jour A→B en conservant les chemins persistants |
| GSO-T18 | Rollback B→A en conservant les chemins persistants |
| GSO-T19 | Contrôle des trois états et classification de dérive |
| GSO-T20 | `check-all` non mutant, sans invocation du rôle |
| GSO-T21 | Retrait déclaré sans tâche destructive |
| GSO-T22 | Registres actif et retiré strictement disjoints, y compris après réactivation |
| GSO-T23 | Absence de dépendance au `control-repository` |
| GSO-T24 | Absence de chemins locaux, symlinks externes et secrets suivis |

### 18.3 Tests statiques

Les tests statiques doivent vérifier :

- structure des fichiers ;
- validité YAML ;
- règles `ansible-lint` ;
- ancrage des liens documentaires ;
- dépendance épinglée ;
- interdictions destructives ;
- absence de `latest` ;
- absence de secrets et chemins locaux ;
- absence de références au `control-repository` dans l'exécution ;
- cohérence des registres, y compris la disjonction stricte entre `retired_grav_sites` et `reactivated_sites` ;
- absence de tout `include_role`/`import_role` de `sepp67.grav_site` dans `check-site.yml` et `check-all.yml` (GSO-REQ-090, rattaché à GSO-T02/GSO-T20).

**GSO-REQ-137 — Garde-fous rejouables.** Chaque interdiction critique DOIT posséder un test automatique positif et, lorsque pertinent, un cas négatif démontrant que le garde-fou détecte l'écart.

### 18.4 Tests du sélecteur

Le validateur local doit être testé avec :

- un hôte valide ;
- une chaîne vide ;
- `all` ;
- le groupe `grav_servers` ;
- une liste de deux hôtes ;
- un motif générique ;
- un hôte inconnu ;
- un nom contenant des caractères de shell interdits.

Le cas « aucun hôte sélectionné » (chaîne vide, hôte inconnu) DOIT être testé sur le validateur local lui-même (GSO-T11), et non déduit d'une simple exécution du playbook seul — voir GSO-REQ-056.

**GSO-REQ-138 — Sélecteur fermé.** Seul un nom littéral correspondant exactement à un hôte actif unique DOIT être accepté.

### 18.5 Tests sans secrets réels

Le vault d'exemple utilise des marqueurs synthétiques. Les tests vérifient qu'ils ne figurent ni dans la sortie, ni dans un artefact, ni dans l'état structuré, y compris pour les éléments `secrets` synthétiques.

Le vault opérationnel ne doit jamais être ouvert, copié ou haché par la CI. Le contrôle structurel prévu par GSO-REQ-204 (correspondance registre/vault, complétude du bootstrap, validité des `secrets`) est une opération de préflight exécutée localement par l'opérateur avant un déploiement réel — jamais un scénario de CI sur le vault de production. Sa preuve automatisée est répartie entre GSO-T07 (cohérence structurelle avec le vault d'exemple) et GSO-T14 (complétude et absence de fuite), chacun exécuté avec un vault synthétique temporaire.

**GSO-REQ-139 — Vault réel absent de CI.** Les workflows DOIVENT fonctionner lorsque `inventories/production/group_vars/all/vault.yml` est absent.

### 18.6 Test de consommation du rôle

La CI doit installer `sepp67.grav_site` depuis `requirements.yml` dans un répertoire temporaire propre et invoquer le rôle par son nom public. Aucun lien local vers le dépôt du rôle ne doit être utilisé.

**GSO-REQ-140 — Même chemin que l'opérateur.** Le test de consommation DOIT utiliser la même référence épinglée que l'installation documentée.

### 18.7 Test sans contact réel

Les scénarios qui valident la traduction peuvent utiliser :

- `localhost` avec connexion locale ;
- des conteneurs éphémères ;
- un rôle espion ou un mécanisme de capture strictement limité aux tests ;
- le mode syntaxique lorsque celui-ci suffit.

Ils ne doivent jamais utiliser l'adresse d'une VM de production.

**GSO-REQ-141 — Réseau de test isolé.** Toute cible fonctionnelle de CI DOIT être locale ou éphémère.

### 18.8 Test multi-site

Le test multi-site vérifie deux définitions et conserve le modèle une VM par projet : deux hôtes fictifs distincts, deux jeux de variables et deux secrets synthétiques, y compris, le cas échéant, des éléments `secrets`. Il NE démarre AUCUN conteneur Docker réel : la preuve porte exclusivement sur la traduction registre/vault vers les variables publiques du rôle, pour chaque hôte pris isolément.

Il doit prouver qu'une opération limitée au site A ne transmet aucune valeur du site B, et réciproquement une opération limitée au site B ne transmet aucune valeur du site A.

Le démarrage réel de plusieurs instances Grav sur un même moteur Docker est une capacité déjà démontrée par les tests propres à `ansible-role-grav-site`. `grav-sites-ops` ne duplique pas cette preuve, ni dans sa CI de commit, ni comme vérification périodique obligatoire — cohérent avec l'invariant « une VM par projet » (§6.2).

**GSO-REQ-142 — Isolation des projets.** Les variables et secrets d'un hôte NE DOIVENT PAS fuiter vers une autre invocation.

### 18.9 Mise à jour et rollback

Les tests A→B→A doivent démontrer que les quatre chemins persistants restent identiques et que les références désirées transmises suivent l'historique attendu.

Ils n'ont pas à restaurer le contenu des volumes, puisque cette opération est hors périmètre.

**GSO-REQ-143 — Persistance testée.** GSO-T17 et GSO-T18 DOIVENT contrôler séparément `pages`, `accounts`, `data` et `images`.

### 18.10 Tests de contrôle de dérive

Le test de `check-site.yml` doit couvrir au minimum un état conforme, une référence différente, un conteneur arrêté, un état inconnu et une VM simulée comme injoignable.

**GSO-REQ-144 — Contrôle non mutant prouvé.** Les tests DOIVENT démontrer qu'aucun fichier ou conteneur n'est modifié par les opérations `check`.

### 18.11 Workflow CI

Le workflow doit séparer autant que nécessaire :

- lint et syntaxe ;
- sécurité statique ;
- cohérence de l'inventaire exemple ;
- tests du sélecteur ;
- consommation du rôle ;
- tests d'orchestration fonctionnels.

Chaque job critique doit échouer réellement ; aucun `continue-on-error` ne peut transformer une régression en succès.

**GSO-REQ-145 — Jobs bloquants.** Tous les jobs de conformité DOIVENT être bloquants pour une release.

### 18.12 Versions de l'environnement de test

Les versions de Python, Ansible et des dépendances de test doivent être compatibles et suffisamment épinglées pour éviter une rupture causée par une version majeure flottante. Les images de test devraient être épinglées par digest lorsqu'elles sont externes.

**GSO-REQ-146 — Outils reproductibles.** La CI NE DOIT PAS dépendre d'un interpréteur majeur non borné tel que `3.x` si cela peut sélectionner une version incompatible.

### 18.13 Résultats de tests

`docs/TEST-RESULTS.md` doit distinguer :

- exigence ou test ;
- scénario implémenté ;
- dernière exécution observée ;
- environnement ;
- résultat ;
- limitation éventuelle.

**GSO-REQ-147 — Pas de preuve inventée.** L'absence d'exécution CI observée DOIT être indiquée comme telle.

### 18.14 Tests du retrait

Le retrait doit être testé comme transformation déclarative. Le test vérifie que l'hôte et sa définition active disparaissent, que le registre retiré reçoit une entrée, et qu'aucune tâche de suppression de VM ou de volume n'existe.

Le déplacement réel des secrets reste une opération locale sur le vault non suivi ; il peut être testé avec une fixture synthétique temporaire.

**GSO-REQ-148 — Retrait simulé.** Aucun test de retrait NE DOIT supprimer une ressource réelle ou un volume persistant.

### 18.15 Nettoyage

Tout test fonctionnel doit supprimer ses conteneurs, réseaux, répertoires temporaires et secrets synthétiques à la fin, y compris après un échec lorsque cela est sûr.

**GSO-REQ-149 — Ressources éphémères.** Une exécution CI terminée NE DOIT laisser aucune ressource de test active.

### 18.16 Critère de conformité de la tranche

La première release de `grav-sites-ops` ne peut être préparée tant que GSO-T01 à GSO-T24 ne sont pas cartographiés et que les tests critiques de sélection, secrets, persistance et absence de contact réel ne sont pas exécutés avec succès.

**GSO-REQ-150 — Matrice complète.** Chaque test GSO-T01 à GSO-T24 DOIT posséder un statut et une preuve avant l'approbation de la première release.

---

## 19. Gestion des versions

### 19.1 Niveaux de version distincts

La plateforme comporte plusieurs versions indépendantes :

| Niveau | Exemple | Décision portée par |
|---|---|---|
| Version de `grav-sites-ops` | `v1.0.0` | Dépôt d'orchestration |
| Version de `ansible-role-grav-site` | `v2.0.0` | `requirements.yml` |
| Version de l'image applicative | `1.0.4` | Entrée du site dans `grav_sites.yml` |
| Digest de l'image applicative | `sha256:…` | Entrée du site dans `grav_sites.yml` |
| Version de `grav-runtime` | Référence du `FROM` | Dépôt applicatif lors de la construction de l'image |

Ces versions ne doivent pas être fusionnées dans une valeur unique ni propagées automatiquement d'un dépôt à l'autre.

**GSO-REQ-151 — Versions séparées.** La documentation et les fichiers DOIVENT distinguer la version de l'orchestrateur, celle du rôle et celle de chaque image applicative.

### 19.2 Version de `grav-sites-ops`

`grav-sites-ops` suit le versionnement sémantique :

- `MAJOR` : rupture du contrat opérateur, de la structure du registre ou du modèle de secrets ;
- `MINOR` : ajout rétrocompatible d'une opération ou capacité ;
- `PATCH` : correction rétrocompatible, documentation ou garde-fou sans rupture.

La première release déclarée exploitable doit être `v1.0.0`. Les versions antérieures peuvent utiliser `0.x.y` tant que le contrat et l'implémentation sont en construction.

**GSO-REQ-152 — Release identifiable.** Toute version publiée DOIT posséder un tag Git annoté et une entrée correspondante dans `CHANGELOG.md`.

### 19.3 Version du rôle

La référence du rôle est épinglée dans `requirements.yml`. Elle ne doit être redéclarée ni dans l'inventaire, ni dans le registre de chaque site.

La montée de `v2.0.0` vers une version ultérieure est une évolution de l'orchestrateur et doit être testée avant utilisation sur une VM réelle.

**GSO-REQ-153 — Une seule référence du rôle.** `requirements.yml` DOIT être l'unique source de vérité de la version de `ansible-role-grav-site`.

### 19.4 Version applicative et digest

Chaque projet actif déclare une version humaine. Le digest est optionnel mais recommandé pour une référence de production immuable.

Lorsque le digest est renseigné :

- la version humaine reste obligatoire pour la traçabilité ;
- le rôle construit la référence effective ;
- l'orchestrateur ne concatène pas `image:version@digest` ;
- un changement de version avec digest identique reste une modification déclarative visible.

**GSO-REQ-154 — Version humaine obligatoire.** Un digest NE DOIT PAS remplacer le champ `version` dans le registre.

### 19.5 Version du runtime

Le dépôt applicatif choisit `grav-runtime` dans son Dockerfile. `grav-sites-ops` déploie le résultat construit et ne doit pas essayer de retrouver, surcharger ou reconstruire cette dépendance.

**GSO-REQ-155 — Runtime transitif.** La version de `grav-runtime` NE DOIT PAS être ajoutée au schéma `grav_sites`.

### 19.6 Changements atomiques

Une modification normale devrait ne changer qu'une dimension :

- version d'un site ;
- version du rôle ;
- structure de l'orchestrateur ;
- ajout ou retrait d'un projet.

Les changements groupés doivent être justifiés lorsqu'ils empêchent d'attribuer clairement un incident.

**GSO-REQ-156 — Historique attribuable.** Une modification de version d'un site DOIT identifier sans ambiguïté le projet concerné.

### 19.7 Changelog

Le changelog de `grav-sites-ops` décrit les changements de l'orchestrateur : structure, playbooks, garde-fous, inventaire et procédures. Il ne recopie pas le changelog complet du rôle ou des images applicatives.

Les changements de versions applicatives peuvent être consignés dans l'historique Git et, si utile, dans une rubrique opérationnelle concise.

**GSO-REQ-157 — Changelog borné.** `CHANGELOG.md` NE DOIT PAS devenir une seconde source de vérité des versions actives du parc.

### 19.8 Préparation d'une release

Avant une release de `grav-sites-ops`, il faut :

1. figer le candidat ;
2. exécuter la matrice GSO-T01 à GSO-T24 ;
3. vérifier les exigences `GSO-REQ-*` ;
4. dater le changelog ;
5. faire valider la CI sur le SHA final ;
6. intégrer linéairement dans `main` ;
7. revalider `main` ;
8. créer et pousser le tag annoté ;
9. publier la release.

**GSO-REQ-158 — Tag sur SHA validé.** Un tag de release DOIT pointer exactement sur un commit dont la CI complète est verte.

### 19.9 Absence de déploiement automatique

Publier une version de `grav-sites-ops` ne doit pas déployer automatiquement le parc. Réciproquement, déployer un site ne doit pas créer une release du dépôt.

**GSO-REQ-159 — Release et exploitation séparées.** Aucun événement Git de release NE DOIT déclencher une mutation des VM de production.

---

## 20. Migration depuis l'ancien profil d'exploitation

### 20.1 Objet de la migration

L'ancien profil d'exploitation se trouve encore localement dans l'ancien dépôt `ansible-role-grav-site`, notamment sous :

```text
inventories/production/group_vars/grav_servers/
```

Les fichiers suivis de l'ancien profil ont été retirés du rôle lors de sa refonte. Un vault opérationnel non suivi subsiste toutefois localement. La migration vise à transférer les données d'exploitation utiles vers `grav-sites-ops` sans recopier la logique, les playbooks ou les structures historiques du rôle.

### 20.2 Principe de non-destruction

La migration est une copie contrôlée suivie d'une validation. Elle ne commence jamais par le déplacement ou la suppression de la source.

**GSO-REQ-160 — Source préservée.** Aucun fichier historique non suivi NE DOIT être supprimé, renommé ou déplacé avant validation complète de sa destination.

### 20.3 Sauvegarde externe du vault

Avant toute manipulation du vault historique, l'opérateur doit créer une sauvegarde externe chiffrée, vérifier sa lisibilité et consigner au minimum :

- le chemin de la sauvegarde, hors des deux dépôts ;
- sa date ;
- sa taille ;
- ses permissions ;
- sa somme de contrôle ;
- la réussite d'une vérification avec Ansible Vault.

La somme de contrôle prouve l'identité des octets, pas la validité du mot de passe ni la complétude logique du contenu.

**GSO-REQ-161 — Sauvegarde vérifiée.** La migration du vault est bloquée tant qu'une sauvegarde externe chiffrée et vérifiée n'existe pas. Cette exigence est satisfaite par une preuve documentaire et n'est pas vérifiable par un test automatisé.

### 20.4 Inventaire des sources

Avant copie, un rapport doit identifier sans afficher de secret :

- les fichiers suivis historiques déjà retirés ;
- le vault local non suivi ;
- les noms de variables publiques attendues ;
- les projets représentés ;
- les métadonnées du fichier secret ;
- les éventuelles valeurs manquantes ou variables obsolètes.

Le rapport ne doit jamais reproduire une valeur du vault.

**GSO-REQ-162 — Cartographie sans divulgation.** L'inventaire de migration DOIT porter sur les clés et structures nécessaires, jamais sur les valeurs secrètes.

### 20.5 Construction préalable du nouveau dépôt

La structure, l'inventaire d'exemple, les tests et les garde-fous de `grav-sites-ops` doivent être fonctionnels avant l'introduction des données réelles.

**GSO-REQ-163 — Harnais avant données réelles.** Aucun profil réel NE DOIT être introduit avant que l'inventaire d'exemple et les tests de sécurité soient verts.

### 20.6 Migration des variables non secrètes

Les anciennes variables sont reclassées dans :

```text
inventories/production/hosts.yml
inventories/production/group_vars/all/grav_sites.yml
```

La migration doit traduire les anciens noms vers le schéma du registre, pas copier l'ancien fichier en bloc. Chaque valeur est revue selon l'interface de `ansible-role-grav-site v2.0.0`.

**GSO-REQ-164 — Traduction explicite.** Chaque variable migrée DOIT avoir une destination documentée ou être explicitement classée obsolète.

### 20.7 Création du nouveau vault

Le nouveau vault est créé directement sous forme chiffrée à l'emplacement normatif. La transformation doit être réalisée avec un mécanisme qui évite tout fichier temporaire en clair suivi ou persistant.

Les valeurs sont structurées sous `vault_grav_sites[inventory_hostname]`. Les clés sont comparées au contrat du rôle. Les commentaires séparent les projets.

**GSO-REQ-165 — Pas de secret en clair sur disque.** La migration NE DOIT PAS créer un export déchiffré persistant du vault historique.

### 20.8 Vérification du nouveau vault

Après création, l'opérateur doit vérifier :

- que le fichier est chiffré ;
- qu'il peut être ouvert avec le mécanisme prévu ;
- que chaque hôte actif possède une entrée ;
- qu'aucune entrée active n'est orpheline ;
- que l'ensemble de bootstrap respecte le contrat du rôle ;
- que les permissions sont restrictives ;
- que Git l'ignore effectivement.

Ces contrôles doivent éviter l'affichage des valeurs.

**GSO-REQ-166 — Destination vérifiée.** La seule existence du nouveau `vault.yml` NE DOIT PAS être considérée comme une migration réussie.

### 20.9 Migration site par site

Les sites sont migrés un par un. Pour chaque site :

1. ajouter l'hôte ;
2. ajouter sa définition ;
3. ajouter ses secrets ;
4. exécuter le préflight statique ;
5. exécuter `check-site` ;
6. vérifier la référence actuellement déployée ;
7. exécuter un déploiement ciblé contrôlé ;
8. vérifier l'absence de changement inattendu des volumes ;
9. consigner le résultat avant de passer au site suivant.

**GSO-REQ-167 — Une migration à la fois.** L'acceptation d'un site DOIT précéder le début de la migration du site suivant.

### 20.10 Déploiement de validation

Le premier déploiement depuis `grav-sites-ops` doit utiliser exactement la référence déjà attendue sur la VM, sauf décision explicite de combiner migration et mise à jour.

Il doit confirmer l'idempotence de l'orchestration et la préservation des quatre volumes.

**GSO-REQ-168 — Migration sans upgrade implicite.** La migration DEVRAIT être validée sans changer simultanément la version applicative.

### 20.11 Ancien vault après migration

Après validation de tous les sites, l'ancien vault reste conservé pendant une période de sécurité décidée par l'opérateur. Son éventuelle suppression est une opération humaine distincte, précédée d'une nouvelle vérification de la sauvegarde et du nouveau vault.

`grav-sites-ops` ne doit contenir aucun script supprimant automatiquement l'ancien fichier.

**GSO-REQ-169 — Nettoyage séparé.** Le nettoyage de l'ancien profil NE DOIT PAS faire partie du playbook ou du commit de migration.

### 20.12 Critères de fin de migration

La migration est terminée lorsque :

- chaque VM active est présente dans le nouvel inventaire ;
- chaque hôte possède une définition et des secrets cohérents ;
- chaque site a réussi un contrôle et un déploiement ciblés ;
- les références désirée, appliquée et réelle concordent ;
- les volumes sont préservés ;
- le vault de destination est sauvegardé ;
- aucune opération courante ne dépend plus de l'ancien profil.

**GSO-REQ-170 — Autonomie finale.** `grav-sites-ops` DOIT fonctionner sans chemin, lien ou lecture dans l'ancien dépôt du rôle.

### 20.13 Rapport de migration

Un rapport hors secrets doit consigner les étapes, preuves, écarts et décisions. Il doit distinguer les tests locaux, les contrôles sur VM et les opérations non réalisées.

**GSO-REQ-171 — Preuves de migration.** Chaque site migré DOIT posséder un verdict documenté avant la clôture de la migration.

### 20.14 Retour arrière de la migration

Tant que l'ancien profil et sa sauvegarde sont conservés, un retour organisationnel reste possible. Il ne doit pas être confondu avec un rollback applicatif : les images et volumes de la VM restent inchangés ; seul le point de contrôle Ansible utilisé par l'opérateur change.

**GSO-REQ-172 — Retour sans mutation applicative.** Abandonner la migration NE DOIT PAS nécessiter la suppression ou la restauration des volumes du site.

---

## 21. Cycle de vie d'un projet

### 21.1 Ajout d'un projet

L'ajout d'un projet actif modifie normalement trois emplacements :

1. `inventories/production/hosts.yml` : ajout de la VM ;
2. `inventories/production/group_vars/all/grav_sites.yml` : ajout de la définition non secrète ;
3. `inventories/production/group_vars/all/vault.yml` : ajout local des secrets dans `vault_grav_sites`.

Il ne nécessite ni nouveau playbook, ni copie du rôle, ni fichier de variables isolé hors de `group_vars`.

**GSO-REQ-173 — Ajout en trois emplacements.** Un ajout normal DOIT être réalisable par l'inventaire, le registre actif et le vault global uniquement.

### 21.2 Préconditions d'ajout

Avant l'ajout, l'opérateur doit disposer :

- d'une VM existante et joignable ;
- d'un nom d'hôte unique ;
- d'une image applicative publiée ;
- d'une version explicite ;
- d'un digest éventuel vérifié ;
- d'une adresse LAN et d'un port ;
- d'un répertoire de base unique ;
- de l'ensemble de bootstrap nécessaire ;
- d'une stratégie de sauvegarde des futurs volumes.

**GSO-REQ-174 — Préconditions complètes.** Un projet incomplet NE DOIT PAS être ajouté comme site actif déployable.

### 21.3 Validation d'un ajout

Après modification :

1. vérifier la syntaxe et les unicités ;
2. vérifier le chargement automatique ;
3. confirmer que le vault est ignoré ;
4. exécuter un check ciblé ;
5. déployer avec `--limit` ;
6. vérifier l'état et les quatre volumes ;
7. traiter séparément une éventuelle publication Internet.

**GSO-REQ-175 — Première cible unique.** Le premier déploiement d'un nouveau site DOIT cibler uniquement sa VM.

### 21.4 Modification de configuration

Une modification ordinaire concerne le registre actif : version, digest, port, état ou autre variable publique. Elle doit être revue et commitée avant le déploiement normal.

Modifier un identifiant structurant tel que l'hôte, le répertoire de base ou le nom du conteneur constitue une migration et exige une procédure dédiée, car cela peut désolidariser l'instance de ses volumes.

**GSO-REQ-176 — Chemins structurants protégés.** Un changement de `base_directory`, `container_name` ou nom d'hôte NE DOIT PAS être traité comme une mise à jour applicative banale.

### 21.5 Modification des secrets

Une modification dans le vault reste locale et n'est pas une preuve de rotation effective dans Grav. Elle doit être sauvegardée et vérifiée sans affichage.

Si une véritable rotation de compte est nécessaire, elle suit une procédure Grav distincte, puis le vault est aligné sur la décision obtenue.

**GSO-REQ-177 — Rotation explicitement opérée.** Le cycle de vie d'un secret DOIT distinguer modification du vault et modification effective du compte applicatif.

### 21.6 Retrait d'un projet

Le retrait approuvé suit ce processus :

1. relever la dernière référence effectivement déployée ;
2. vérifier la sauvegarde de la VM et des volumes ;
3. traiter séparément la publication dans le `control-repository`, si nécessaire ;
4. arrêter manuellement la VM ;
5. retirer l'hôte de `hosts.yml` ;
6. retirer sa définition de `grav_sites.yml` ;
7. déplacer ses secrets vers `vault_retired_grav_sites` ;
8. ajouter sa fiche sans secret dans `registry/retired-sites.yml` ;
9. exécuter les validations statiques ;
10. committer uniquement les fichiers non secrets.

Les fichiers suivis normalement modifiés sont :

```text
inventories/production/hosts.yml
inventories/production/group_vars/all/grav_sites.yml
registry/retired-sites.yml
```

Le vault local non suivi est modifié séparément.

**GSO-REQ-178 — Retrait cohérent.** Les suppressions dans l'inventaire et le registre actif DOIVENT être accompagnées, dans le même changement Git, par l'ajout au registre retiré.

### 21.7 Arrêt manuel de la VM

L'arrêt de la VM est réalisé dans l'hyperviseur par l'opérateur. Il ne doit pas être ajouté au playbook de retrait.

**GSO-REQ-179 — Hyperviseur hors orchestration.** Aucun playbook de cycle de vie d'un projet NE DOIT appeler l'API de Proxmox ou d'un autre hyperviseur.

### 21.8 Réactivation

La réactivation suit le chemin inverse :

1. vérifier la conservation de la VM, des volumes et de la sauvegarde ;
2. redémarrer manuellement la VM ;
3. réinscrire l'hôte dans `hosts.yml` ;
4. replacer sa définition technique dans `grav_sites.yml` ;
5. déplacer ses secrets archivés vers `vault_grav_sites` ;
6. retirer sa fiche de `registry/retired-sites.yml` et ajouter un événement daté dans `registry/reactivated-sites.yml` ;
7. exécuter `check-site` ;
8. déployer explicitement avec `--limit` ;
9. vérifier l'état appliqué, l'état réel et les volumes ;
10. traiter séparément la publication Internet éventuelle.

**GSO-REQ-180 — Même identité à la réactivation.** Une réactivation DEVRAIT réutiliser le même nom d'hôte et les mêmes chemins persistants afin de préserver la continuité.

### 21.9 Historique des réactivations

La convention retenue est un historique distinct : `registry/reactivated-sites.yml` (schéma en §7.7). La réactivation retire la fiche de `retired-sites.yml` et ajoute un événement à `reactivated-sites.yml` dans la même opération :

```yaml
reactivated_at: "YYYY-MM-DD"
```

`retired_grav_sites` désigne ainsi, sans exception, l'ensemble exact des projets actuellement retirés — la règle de disjonction (GSO-REQ-052) s'applique sans cas particulier, et aucune fiche `retired_grav_sites` ne porte jamais de statut `reactivated`.

**GSO-REQ-181 — Historique explicite.** La réactivation d'un projet DOIT retirer sa fiche de `registry/retired-sites.yml` et ajouter un événement daté à `registry/reactivated-sites.yml`, comprenant au minimum la date de réactivation et une copie de la dernière fiche retirée. Cette transformation DOIT être couverte par un test automatique démontrant qu'aucune clé réactivée ne subsiste dans `retired_grav_sites`.

### 21.10 Retrait définitif

La destruction définitive d'un projet n'est pas couverte. Si elle devient nécessaire, elle exige un contrat séparé précisant sauvegardes, rétention, validation humaine et cibles exactes.

**GSO-REQ-182 — Destruction hors procédure.** Le processus de retrait NE DOIT PAS être étendu par commodité à une suppression définitive.

### 21.11 Aucun couplage public

L'ajout, le retrait ou la réactivation peut rappeler une action séparée du `control-repository`, mais ne doit jamais la déclencher automatiquement.

**GSO-REQ-183 — Deux décisions humaines.** Le cycle de vie local d'un site et son exposition publique DOIVENT rester deux décisions opérationnelles distinctes.

---

## 22. Critères d'acceptation

### 22.1 Acceptation du contrat

Le contrat est prêt pour audit lorsque :

- les sections 1 à 23 sont complètes ;
- les exigences sont numérotées sans doublon ;
- les termes normatifs sont cohérents ;
- les décisions humaines sont distinguées des décisions différées ;
- aucune contradiction interne connue ne subsiste.

**GSO-REQ-184 — Audit avant construction.** La création réelle du dépôt DOIT être précédée d'un audit décisionnel et d'un préflight de conformité fondés sur ce contrat.

### 22.2 Acceptation du squelette

Le squelette initial est acceptable lorsque :

- l'arborescence normative existe ;
- aucun profil réel ni vault n'a encore été introduit ;
- l'inventaire d'exemple est parsable ;
- le rôle épinglé peut être installé ;
- lint, syntaxe et garde-fous statiques sont verts ;
- aucune opération ne peut contacter la production par défaut.

**GSO-REQ-185 — Squelette non opérationnel par défaut.** Le premier commit du dépôt NE DOIT contenir aucune cible réelle ou capacité implicite de déploiement.

### 22.3 Acceptation fonctionnelle

L'implémentation fonctionnelle est acceptable lorsque GSO-T01 à GSO-T24 ont été exécutés, consignés et réussis, avec une distinction claire entre tests statiques et fonctionnels.

**GSO-REQ-186 — Zéro test critique manquant.** Aucun `TEST GAP` ne peut subsister pour la sélection, les secrets, la persistance, la consommation du rôle et l'absence de contact réel.

### 22.4 Acceptation de sécurité

Les critères de sécurité sont :

- vault réel absent de Git et de la CI ;
- aucun secret dans les logs ;
- aucun chemin local ou lien externe ;
- aucune opération destructive ;
- refus d'une cible absente, globale, multiple ou inconnue ;
- aucune dépendance au `control-repository` ;
- aucun accès possible à la production depuis la CI.

**GSO-REQ-187 — Échec d'un garde-fou bloquant.** Toute non-conformité de sécurité DOIT bloquer une release.

### 22.5 Acceptation de la migration

La migration réelle n'est acceptable que si :

- le vault source a une sauvegarde externe vérifiée ;
- le nouveau vault est chiffré, ignoré et sauvegardé ;
- chaque site a été migré séparément ;
- les trois niveaux d'état concordent ;
- les quatre volumes sont préservés ;
- aucun site n'a nécessité l'ancien profil après validation.

**GSO-REQ-188 — Migration distincte de la construction.** La conformité du dépôt PEUT être établie avec des données fictives avant la migration ; la conformité opérationnelle exige ensuite des preuves propres aux sites réels.

### 22.6 Acceptation documentaire

Le README et les documents d'exploitation doivent permettre à un opérateur compétent de :

- installer les dépendances ;
- comprendre les frontières ;
- ajouter un site ;
- exécuter chaque opération ;
- mettre à jour ou rollbacker une image ;
- retirer et réactiver un projet ;
- interpréter une dérive ;
- retrouver le guide de migration.

**GSO-REQ-189 — Documentation exécutable.** Les commandes documentées DOIVENT être testées ou explicitement signalées comme exemples non exécutés.

### 22.7 Statuts de préflight

Le préflight de construction doit utiliser des statuts explicites, par exemple :

- `COMPLIANT` ;
- `PARTIALLY COMPLIANT` ;
- `NON-COMPLIANT` ;
- `NOT IMPLEMENTED` ;
- `DOCUMENTATION ONLY` ;
- `TEST GAP` ;
- `DECISION REQUIRED` ;
- `NOT APPLICABLE`.

Chaque exigence reçoit un statut, une preuve et, si nécessaire, un lot de correction.

**GSO-REQ-190 — Matrice exhaustive.** Le préflight DOIT cartographier chaque `GSO-REQ-*` sans omission.

### 22.8 Gate de construction

Le statut autorisant l'implémentation doit être formulé explicitement. Un audit peut conclure :

- `READY FOR IMPLEMENTATION APPROVAL` ;
- `NOT READY FOR IMPLEMENTATION` ;
- `BLOCKED — DECISION REQUIRED` ;
- `BLOCKED — SAFETY ISSUE`.

Une conclusion favorable n'autorise pas à elle seule les mutations : une autorisation humaine distincte reste nécessaire.

**GSO-REQ-191 — Audit non exécutoire.** Un audit ou préflight NE DOIT modifier aucun dépôt sans autorisation séparée.

### 22.9 Gate de release

Une release est autorisable uniquement si le SHA final a réussi la CI complète, si le changelog est prêt et si les matrices d'exigences et de tests ne comportent aucun écart critique.

**GSO-REQ-192 — Publication séparée.** Le push de `main`, le tag et la release DOIVENT rester des étapes explicitement autorisées et vérifiées.

---

## 23. Décisions différées et gouvernance

### 23.1 Décisions différées

Les sujets suivants sont volontairement exclus de la première version :

1. plusieurs environnements durables ;
2. plusieurs sites sur une même VM ;
3. provisioning et destruction de VM ;
4. intégration à l'API de Proxmox ;
5. gestionnaire de secrets externe ;
6. suivi d'un vault chiffré dans Git ;
7. authentification à un registre d'images privé ;
8. sauvegarde et restauration orchestrées ;
9. synchronisation Git–volumes intégrée ;
10. déploiement mutant global ;
11. rollback automatique ;
12. supervision, métriques et alerting centralisés ;
13. transmission automatique au `control-repository` ;
14. transformation en collection Ansible ;
15. orchestration d'autres services que Grav ;
16. exposition, dans le schéma du registre, de réglages avancés du rôle au-delà du minimum actuel (`grav_container_gid`, `grav_restart_policy`, réglages détaillés de healthcheck, d'attente et de contrôle HTTP) — un champ générique de contournement (par exemple `role_overrides`) est explicitement exclu, car il affaiblirait le schéma et permettrait de contourner le contrat ; une variable nommée et validée serait ajoutée par amendement si un besoin réel apparaît.

Leur présence dans cette liste ne constitue ni une promesse d'implémentation, ni une autorisation.

**GSO-REQ-193 — Différé non implicite.** Une décision différée NE DOIT PAS être implémentée avant arbitrage et amendement du contrat.

### 23.2 Décisions architecturales actées

Les décisions suivantes sont actées pour la première version :

- une VM par projet ;
- un environnement durable `production` ;
- un registre central automatiquement chargé ;
- un vault global unique, chiffré et non suivi ;
- sélection des opérations ciblées avec `--limit` ;
- validation locale exacte de la cible ;
- VM préexistantes ;
- retrait réversible et non destructif ;
- dépendance au rôle épinglée sur un tag ;
- indépendance complète du `control-repository`.

**GSO-REQ-194 — Décisions protégées.** Une implémentation conforme NE DOIT PAS contredire une décision actée sous prétexte de flexibilité technique.

### 23.3 Processus d'amendement

Toute proposition modifiant une décision actée doit préciser :

1. le problème rencontré ;
2. les preuves ;
3. les options ;
4. les conséquences sur les frontières ;
5. les exigences touchées ;
6. la migration nécessaire ;
7. les tests à ajouter ;
8. la décision humaine.

**GSO-REQ-195 — Amendement avant code.** Le contrat DOIT être amendé avant l'implémentation d'une rupture architecturale.

### 23.4 Gestion des exigences

Les identifiants `GSO-REQ-*` sont stables. Une exigence retirée ne doit pas être renumérotée ni réutilisée ; elle est marquée obsolète avec la version et la décision correspondantes.

Les nouvelles exigences reçoivent des numéros supérieurs au dernier identifiant existant.

**GSO-REQ-196 — Identifiants immuables.** Un identifiant d'exigence publié NE DOIT PAS être réattribué à une autre règle.

### 23.5 Gestion des tests

Les identifiants `GSO-T*` suivent la même règle de stabilité. Toute nouvelle exigence critique doit être reliée à une preuve existante ou à un nouveau test.

**GSO-REQ-197 — Exigence prouvable.** Toute nouvelle obligation critique DOIT indiquer comment sa conformité sera vérifiée.

### 23.6 Compatibilité du contrat

Une modification éditoriale sans changement de sens peut incrémenter la version mineure ou corrective du document. Une modification d'invariant, de périmètre ou de modèle de données constitue une révision majeure du contrat.

**GSO-REQ-198 — Version du contrat.** Chaque version approuvée du contrat DOIT être identifiable et conservée dans l'historique.

### 23.7 Autorité humaine

Les opérations irréversibles ou externes — suppression, push, tag, release, déploiement réel, modification de secrets, arrêt de VM — exigent une autorisation correspondant précisément à leur périmètre.

Une autorisation d'audit n'est pas une autorisation d'implémentation. Une autorisation d'implémentation n'est pas automatiquement une autorisation de publication ou de déploiement.

**GSO-REQ-199 — Autorisations distinctes.** Les gates d'audit, construction, intégration, publication et exploitation DOIVENT rester séparées.

### 23.8 Propriété des frontières

Chaque dépôt reste maître de son cycle de vie. Une évolution de `grav-sites-ops` ne doit pas modifier un autre dépôt sans une demande et une autorisation propres à celui-ci.

**GSO-REQ-200 — Mutation bornée au dépôt.** Une tâche portant sur `grav-sites-ops` NE DOIT PAS modifier `ansible-role-grav-site`, un dépôt applicatif, `grav-runtime` ou le `control-repository`.

### 23.9 Revue périodique

Le contrat devrait être revu lorsqu'un événement révèle une limite réelle : ajout de plusieurs projets, migration de VM, besoin de registre privé, incident de contenu ou changement du rôle.

La revue doit partir des faits d'exploitation, non d'une recherche abstraite de flexibilité.

**GSO-REQ-201 — Évolution fondée sur les faits.** Une complexité nouvelle DEVRAIT répondre à un besoin observé et documenté.

### 23.10 Statut final du document

La présente version 0.5.0 constitue un projet normatif complet couvrant les sections 1 à 23. Elle a reçu une approbation humaine explicite le 2026-09-05, à l'issue de l'audit de cohérence interne, du préflight décisionnel et de la correction des écarts relevés. Le document est donc au statut « normatif, approuvé » et sert de référence normative pour la préparation du dépôt.

Cette approbation n'autorise pas, à elle seule, la création, l'implémentation, la publication ou le déploiement de `grav-sites-ops`. La phase suivante est documentaire : un préflight de construction comparant l'implémentation prévue aux exigences du présent contrat. La création effective du dépôt exigera une autorisation humaine distincte, conformément à GSO-REQ-199 et à GSO-REQ-202.

**GSO-REQ-202 — Approbation explicite.** Le contrat complet DOIT recevoir une approbation humaine avant de servir de base exécutoire à la création de `grav-sites-ops`.

---

## Conclusion normative

`grav-sites-ops` est un dépôt d'orchestration spécialisé dans l'exploitation de sites Grav sur des VM existantes du réseau local. Il maintient l'état désiré du parc, sélectionne explicitement une cible et compose `ansible-role-grav-site` sans absorber sa logique.

Sa première version repose sur une VM par projet, un inventaire durable unique, un registre central, un vault global local, des opérations ciblées avec `--limit`, une persistance non destructible et une indépendance complète vis-à-vis de la publication Internet.

La conformité exige que le dépôt demeure sûr par défaut : aucune cible implicite, aucun secret suivi, aucun accès à la production depuis la CI, aucun retrait destructif, aucune synchronisation cachée et aucune évolution de frontière sans amendement préalable.
