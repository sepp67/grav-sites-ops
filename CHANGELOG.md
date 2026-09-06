# Changelog

Toutes les évolutions notables de **`grav-sites-ops` en tant qu'orchestrateur**
sont consignées ici. Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/)
et le versionnement sémantique.

> `CHANGELOG.md` trace les versions **du dépôt d'orchestration**. Il n'est pas
> une source de vérité des versions applicatives actives du parc : celles-ci
> vivent uniquement dans le registre `grav_sites` (GSO-REQ-157). La version du
> rôle consommé est déclarée uniquement dans `requirements.yml` (GSO-REQ-153).

## [Non publié]

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
