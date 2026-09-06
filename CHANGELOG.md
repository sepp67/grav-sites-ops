# Changelog

Toutes les évolutions notables de **`grav-sites-ops` en tant qu'orchestrateur**
sont consignées ici. Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/)
et le versionnement sémantique.

> `CHANGELOG.md` trace les versions **du dépôt d'orchestration**. Il n'est pas
> une source de vérité des versions applicatives actives du parc : celles-ci
> vivent uniquement dans le registre `grav_sites` (GSO-REQ-157). La version du
> rôle consommé est déclarée uniquement dans `requirements.yml` (GSO-REQ-153).

## [Non publié]

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
