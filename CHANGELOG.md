# Changelog

Toutes les évolutions notables de **`grav-sites-ops` en tant qu'orchestrateur**
sont consignées ici. Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/)
et le versionnement sémantique.

> `CHANGELOG.md` trace les versions **du dépôt d'orchestration**. Il n'est pas
> une source de vérité des versions applicatives actives du parc : celles-ci
> vivent uniquement dans le registre `grav_sites` (GSO-REQ-157). La version du
> rôle consommé est déclarée uniquement dans `requirements.yml` (GSO-REQ-153).

## [Non publié]

### Ajouté — lot L6 (contrôle de dérive, lecture seule)

- `playbooks/check-site.yml` + `playbooks/check-all.yml` + séquence commune
  `playbooks/_shared/observe.yml` : comparaison des **trois niveaux d'état**
  (désiré / appliqué / réel) et **classification** de la dérive
  (GSO-REQ-118). **Strictement non mutant** : `gather_facts: false`
  (GSO-REQ-124), aucun `include_role`/`import_role` de `sepp67.grav_site`,
  collecte en lecture seule uniquement — `slurp` de `.deployed_state.yml`
  (jamais modifié — GSO-REQ-119), `docker inspect`, `uri` GET, `stat` de
  `.last_failure.log` (présence + horodatage, **jamais** le contenu —
  GSO-REQ-123). Aucune remédiation automatique, aucun appel à
  `deploy-site.yml` (GSO-REQ-090/122).
- `scripts/lib/gso_classify.py` : classificateur **pur** des 8 catégories du
  contrat §16.5 (`IN_SYNC`, `NOT_DEPLOYED`, `REFERENCE_DRIFT`, `CONFIG_DRIFT`,
  `STOPPED`, `UNHEALTHY`, `UNREACHABLE`, `UNKNOWN`). `STOPPED` est relatif à
  l'état **désiré** : `stopped` voulu + conteneur arrêté ⇒ `IN_SYNC`
  (GSO-REQ-121). Code de sortie toujours 0 (c'est le playbook qui décide).
- `scripts/lib/site-check.sh` + `scripts/check-site.sh` + `scripts/check-all.sh` :
  chemin opérateur de contrôle **sans verrou de mutation** (un contrôle ne
  bloque jamais un déploiement) ; `check-site` valide `SITE` par le sélecteur
  fermé L3 ; `check-all` vérifie d'abord la **cohérence déclarative** du parc
  **sans VM** (GSO-REQ-125). Aucune bascule possible vers une mutation
  (GSO-REQ-104).
- `Makefile` : cibles `make check SITE=` / `make check-all`.
- Tests (fausse CLI `docker` en lecture seule, 100 % reproductibles) :
  `tests/gso-t19-drift-classification.sh` (les 8 catégories ; trois niveaux
  distingués ; conteneur arrêté → `STOPPED` ; `stopped` désiré → jamais
  `STOPPED` ; fichier illisible / docker indisponible → `UNKNOWN` ; VM
  simulée injoignable → `UNREACHABLE` ; `.deployed_state.yml` inchangé ;
  aucune sous-commande `docker` mutante ; rôle jamais invoqué ; non-fuite ;
  codes stables), `tests/gso-t20-check-all-non-mutating.sh` (gardes statiques
  `check-site.yml`/`check-all.yml` sans `include_role` ; parcours du parc ;
  registre incohérent → échec avant parcours, sans VM ; verdict de parc ;
  non-mutation).
- `.github/workflows/ci.yml` : job `drift` (GSO-T19 + GSO-T20, fausse CLI
  `docker`, 100 % reproductible).
- Doublure de tests : helper `gso_fake_docker_into` (fausse CLI `docker`
  lecture seule qui **refuse** toute sous-commande mutante).

Codes de sortie du contrôle : le contrat (GSO-REQ-093) impose « code non nul
si l'intention n'est pas atteinte » sans taxonomie numérique ; convention
retenue **`0` = `IN_SYNC`**, `≠ 0` sinon, la **catégorie §16.5** (sans secret)
portant la distinction fine.

### Ajouté — lot L5 (redémarrage et arrêt d'un site)

- `playbooks/restart-site.yml` + `playbooks/stop-site.yml` : plays fins qui
  fixent `_gso_intent` (`restart` / `stop`) puis empruntent la séquence
  commune `playbooks/_shared/mutate.yml` (assertions `--limit` → préflight
  structurel → traduction fermée → **une seule** invocation de
  `sepp67.grav_site`). Chaque intention a un playbook **dédié**
  (GSO-REQ-081/082/087/088/089).
- `playbooks/_shared/translate.yml` : `grav_state` **dérivé de la seule
  intention** — `restart` → `restarted`, `stop` → `stopped`, `deploy` → état
  du registre ; `_gso_intent` contraint à `{deploy, restart, stop}` par
  assertion. L'opérateur ne fournit **jamais** `grav_state`.
- `scripts/lib/site-mutation.sh` : chemin opérateur partagé (playbook validé
  contre une liste fermée → sélecteur `validate-target.sh` → **verrou `flock`
  par site, identique à `deploy`** → `ansible-playbook --limit`). Codes du
  sélecteur / verrou (75) / playbook / rôle propagés sans masquage.
- `scripts/restart-site.sh`, `scripts/stop-site.sh` : wrappers fins n'acceptant
  que `SITE`. `scripts/deploy.sh` réécrit sur le même chemin partagé.
- `Makefile` : cibles `make restart SITE=` / `make stop SITE=`.
- Tests (doublure de rôle, 100 % reproductibles, **aucun conteneur**) :
  `tests/l5-restart-stop.sh` (intention → `grav_state`, 1 invocation, `restart`
  n'altère ni version ni digest, `stop` sans orchestration destructive, refus
  sans/avec argument surnuméraire/cible invalide/absente/retirée/incohérente
  sans invocation du rôle, verrou partagé, échec concurrent code 75,
  libération du verrou après succès et échec, non-fuite de secret, fixtures
  inchangées), `tests/l5-action-closed.sh` (garde-fou statique des intentions
  fermées). Preuves L5 **non numérotées** — le préflight ne prévoit aucun
  `GSO-Txx` dédié à L5.
- CI : job `translate` étendu à `l5-restart-stop` et `l5-action-closed`.

`restart` n'est **pas** un redéploiement ni une mise à jour (GSO-REQ-088).
`stop` n'entraîne **aucune** suppression de conteneur, volume, donnée
persistante ou fichier de déploiement (GSO-REQ-089). Aucune action implicite,
combinée ou globale ; `SITE` reste le seul argument opérateur.

### Ajouté — lot L4 (déploiement d'un site)

- `playbooks/deploy-site.yml` + `playbooks/_shared/translate.yml` : assertion
  `--limit` == hôte courant → préflight structurel (`gso_validate.py preflight`,
  `no_log`, GSO-REQ-204) → traduction exacte registre/vault → **une seule**
  invocation de `sepp67.grav_site` (GSO-REQ-015/018/061/087/092).
- `scripts/deploy.sh` : sélecteur fermé → **verrou `flock` par site**
  (GSO-REQ-096) → playbook. `make deploy SITE=`.
- `requirements.yml` : ajout de `community.docker` (dépendance de rôle,
  bornée `>=5.0.0,<6.0.0`) ; `make install-role` installe rôle + collection.
- Tests : `GSO-T13` (traduction + second contrôle de cible), `GSO-T14`
  (isolation des secrets, non-fuite, GSO-REQ-204), `GSO-T15` (**déploiement
  réel** d'un site + conteneur `grav-runtime` éphémère sur localhost, contrôle
  fonctionnel, destruction contrôlée), `GSO-T16` (deux sites, isolation sans
  double conteneur), `tests/l4-concurrency-lock.sh` (verrou).
- Doublure de rôle `tests/lib/spy-role/` + harnais `l4_tmptree`.
- `.ansible-lint` ; `ansible.cfg` : `unparsed_is_failed` retiré.
- CI : jobs `translate` (doublure) et `deploy-functional` (conteneur éphémère).

Traduction, verrou et une-seule-invocation prouvés sans donnée réelle
(doublures) ; GSO-T15 seul crée un conteneur, localhost, éphémère, synthétique.

**Correctif de clôture L4 — contrat d'exécution de GSO-T15.** `GSO-T15` est
retiré de la CI standard : il exige une image `grav-runtime` déjà présente
localement (aucun pull implicite, aucun identifiant GHCR — GSO-REQ-108) et
devient un **test d'acceptation local** (`make test-functional`). La CI
conserve `GSO-T13`/`T14`/`T16` + verrou (100 % reproductibles avec doublures)
et ajoute `l4-ci-functional-contract` (garde-fou : pas de pull, pas de
référence flottante, pas de secret de registre). `make test` reste la gate
locale complète (avec `GSO-T15`) ; `make test-reproducible` = sous-ensemble
CI. `GSO-T15` **échoue** (jamais un SKIP, jamais un succès) si une précondition
manque. Contrat détaillé + digest exact : `docs/TESTING.md`.

### Ajouté — lot L3 (sélecteur fermé + préflight lecture seule)

- `scripts/lib/gso_validate.py` : **implémentation unique** des règles de
  validation (registre, vault, sélecteur, préflight) — remplace
  `tests/lib/registry_lint.py` et `tests/lib/vault_lint.py` (logique promue,
  non dupliquée).
- `scripts/validate-target.sh` : sélecteur fermé — `SITE` ↦ `^[a-z][a-z0-9-]*$`,
  inventaire fixé à `inventories/production/hosts.yml` (non remplaçable), un
  seul hôte actif, cohérence registre/vault, refus des cibles retirées et
  globales (GSO-REQ-053, 056, 057, 083-086, 093-095, 107, 138).
- `scripts/preflight.sh` : préflight opérateur read-only, échoue fermé.
- Cibles `make validate SITE=` / `make preflight SITE=`.
- `docs/OPERATIONS.md`.
- `tests/gso-t08` … `tests/gso-t12` + 4 fixtures synthétiques de production
  isolées (`tests/fixtures/l3-*`).
- `GSO-T06`/`GSO-T07` repointés sur le validateur partagé (sens inchangé).
- CI étendue à `GSO-T08`–`GSO-T12`.

Correctif de clôture L3 : `--root` et `--action` **retirés** de l'interface
opérateur. La racine du dépôt et l'inventaire sont déterminés uniquement
depuis l'emplacement canonique de `gso_validate.py` (`realpath`), jamais
depuis le cwd, une option ou une variable d'environnement. L'injection d'une
racine synthétique n'existe plus que via `run_selector` / `run_preflight`
(fonctions internes appelées par le seul code de test). La liste fermée
`NORMATIVE_ACTIONS` est conservée pour L4.

Aucun playbook, aucun appel au rôle, aucun vault opérationnel, aucun
`inventories/production/` réel, aucune connexion : le dépôt reste non
opérationnel.

### Ajouté — lot L2 (modèle de vault)

- `inventories/example/group_vars/all/vault.yml.example` : modèle de vault en
  clair, entièrement synthétique — `vault_grav_sites` (2 entrées : bootstrap
  admin tri-state + `secrets` `name`/`content` pour alpha), `vault_retired_grav_sites: {}`.
- `.gitignore` : garde Git renforcée du vault ; ré-inclusion **unique et
  nommée** de `inventories/example/group_vars/all/vault.yml.example`
  (GSO-REQ-098).
- `docs/VAULT-SCHEMA.md` : schéma normatif du vault (bootstrap administrateur,
  `grav_secrets` `name` + `content`, forme `src` interdite, garde Git,
  disjonction actif/retiré).
- `tests/lib/vault_lint.py` : validateur statique du vault d'exemple, sans
  affichage de valeur.
- `tests/gso-t07-vault-example.sh` : GSO-T07 (correspondance, schéma admin,
  `grav_secrets`, rejet de `src`, non-fuite) + 4 cas négatifs générés.
- `GSO-T24` étendu : garde Git étroite du vault, confinement des marqueurs
  synthétiques.
- Cible `make lint-vault` ; `make test-static` et CI étendus à `GSO-T07`.

Toujours aucun vault opérationnel, aucun secret réel, aucun sélecteur, aucun
playbook, aucune capacité de déploiement.

### Ajouté — lot L1 (couche de données déclaratives)

- `inventories/example/hosts.yml` : deux hôtes fictifs dans `grav_servers`,
  adresses TEST-NET-1.
- `inventories/example/group_vars/all/grav_sites.yml` : registre `grav_sites`
  synthétique (2 entrées), chargé automatiquement par Ansible.
- `docs/REGISTRY-SCHEMA.md` : schéma normatif du registre (champs obligatoires
  et optionnels, unicité, sémantique de `state`, environnements).
- `tests/lib/registry_lint.py` : validateur statique de cohérence
  inventaire ↔ registre (correspondance totale, unicité, schéma, données
  synthétiques).
- `tests/gso-t05-example-inventory.sh`, `tests/gso-t06-registry-autoload.sh` +
  fixture négative `tests/fixtures/l1-broken/`.
- Cibles `make lint-registry` ; `make test-static` étendu ; CI étendue à
  `GSO-T05`/`GSO-T06`.

Aucun vault, aucun secret, aucun sélecteur, aucun appel au rôle : le dépôt
reste non opérationnel par défaut.

### Ajouté — lot L0 (harnais)

- `ansible.cfg` sans inventaire par défaut ; `-i` explicite obligatoire.
- `requirements.yml` épinglant `sepp67.grav_site` sur le tag `v2.0.0`.
- `.gitignore` couvrant vault, rôles installés, caches et sorties de diagnostic.
- `.yamllint` (configuration du harnais de tests).
- `Makefile` : cibles `help`, `install-role`, `lint`, `test`, `test-static`,
  `test-role`, `clean`.
- Batterie de tests `GSO-T01`, `GSO-T02`, `GSO-T03`, `GSO-T04`, `GSO-T23`,
  `GSO-T24` + lanceur `tests/run-all.sh`.
- CI statique (`.github/workflows/ci.yml`).
- Documentation : `README.md`, `docs/ARCHITECTURE.md`, `docs/VERSIONING.md`,
  `docs/GOVERNANCE.md`.
- Squelette de répertoires (`inventories/example`, `playbooks`, `registry`,
  `scripts`) — non peuplés.
- `docs/CONTRAT-ARCHITECTURAL.md` : copie exacte (à l'octet près) du contrat
  architectural `v0.5.0` approuvé, conservée dans l'historique (GSO-REQ-198) ;
  ordre de préséance établi dans `docs/ARCHITECTURE.md`.

Le dépôt reste **non opérationnel par défaut** : aucun inventaire de
production, aucun vault, aucun playbook.
