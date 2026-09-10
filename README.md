# grav-sites-ops

Dépôt d'orchestration Ansible consacré à l'**exploitation** d'un parc de sites
web [Grav](https://getgrav.org/) sur des VM existantes du réseau local.

`grav-sites-ops` décrit l'état désiré du parc et invoque, pour chaque machine
explicitement sélectionnée, le rôle atomique
[`ansible-role-grav-site`](https://github.com/sepp67/ansible-role-grav-site)
(`sepp67.grav_site`). Il ne définit pas le mécanisme interne de déploiement
d'une instance Grav : ce mécanisme appartient exclusivement au rôle.

## Statut

**Construction en cours — lots L0 (harnais), L1 (données déclaratives),
L2 (modèle de vault), L3 (sélecteur fermé + préflight), L4 (déploiement d'un
site), L5 (redémarrage et arrêt d'un site), L6 (contrôle de dérive, lecture
seule), L7 (mise à jour et rollback déclaratifs, gardes de persistance),
L8 (cycle de vie documentaire : retrait, réactivation, validateur lecture
seule), L9 (migration documentaire site par site depuis l'ancien profil),
L10 (consolidation : CI bloquante, `docs/TEST-RESULTS.md`, matrice des 204
exigences), L11 (acceptation : revue §22, verdicts séparés
construction / publication / release / migration — `docs/ACCEPTANCE.md`).**

**La construction locale L0–L11 est acceptée** — `main` = `d69a05a`, **poussé**
(`docs/ACCEPTANCE.md`). La **CI GitHub Actions** a tourné une première fois
(run `34513250088`) : jobs métier verts, **run global pas encore vert** (défaut
d'un garde-fou, corrigé — voir `CHANGELOG`). La **release** (tag) et la
**migration réelle** restent **bloquées** : chacune attend une décision humaine
ou une condition externe précise (`docs/ACCEPTANCE.md` §4).

Le dépôt reste **non opérationnel par défaut** : ni inventaire de production,
ni vault opérationnel. Les seules données versionnées sont l'inventaire, le
registre et le modèle de vault d'**exemple** (`inventories/example/…`),
entièrement synthétiques. `make validate` / `make preflight` / `make check` /
`make check-all` sont en lecture seule ; `make deploy` / `make restart` /
`make stop` `SITE=<hôte>` exécutent le même chemin complet sélecteur → verrou →
préflight → rôle. Toutes **échouent tant qu'aucun
`inventories/production/hosts.yml` n'est fourni** (hors dépôt).

## Source normative

La référence normative de ce dépôt est le **contrat architectural `v0.5.0`**
(statut : normatif, approuvé le 2026-09-05), dont une copie exacte est
conservée dans [`docs/CONTRAT-ARCHITECTURAL.md`](docs/CONTRAT-ARCHITECTURAL.md).
Voir [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) pour l'ordre de préséance et
[`docs/GOVERNANCE.md`](docs/GOVERNANCE.md) pour la gouvernance. La feuille de
route de construction est décrite hors dépôt dans le préflight
`08-preflight-construction.md`.

## Prérequis

- `ansible-core` ≥ 2.17
- `ansible-lint`, `yamllint`
- `python3` avec `PyYAML`
- accès réseau à GitHub pour installer la dépendance de rôle

## Commandes disponibles à ce stade

Toutes les commandes ci-dessous sont couvertes par un test (`make test`).

| Commande | Effet |
|---|---|
| `make help` | liste les cibles |
| `make install-role` | installe `sepp67.grav_site` (tag épinglé) dans `./roles` |
| `make lint` | `yamllint` + `ansible-lint` |
| `make test` | gate locale **complète** : batterie reproductible **+ `GSO-T15`** (exige Docker + rôle + collection + image `grav-runtime` épinglée déjà présents — voir [`docs/TESTING.md`](docs/TESTING.md)) |
| `make test-reproducible` | sous-ensemble 100 % reproductible (identique à la CI ; **sans `GSO-T15`**) |
| `make test-functional` | `GSO-T15` seul : déploiement fonctionnel + conteneur éphémère local |
| `make test-static` | tests statiques uniquement (sans accès réseau) |
| `make test-role` | vérifie l'installation du rôle (accès réseau requis) |
| `make validate SITE=<hôte>` | sélecteur fermé, lecture seule (voir `docs/OPERATIONS.md`) |
| `make preflight SITE=<hôte>` | préflight opérateur, lecture seule |
| `make deploy SITE=<hôte>` | déploie / actualise l'instance d'un site (sélecteur → verrou → rôle) — **aussi la mise à jour et le rollback**, par déclaration dans le registre (voir `docs/OPERATIONS.md`) |
| `make restart SITE=<hôte>` | redémarre l'instance sans changer sa référence désirée (GSO-REQ-088) |
| `make stop SITE=<hôte>` | arrête le conteneur d'un site, sans rien supprimer ni retirer du parc (GSO-REQ-089) |
| `make check SITE=<hôte>` | contrôle de dérive d'un site : désiré vs appliqué vs réel, classé (lecture seule) |
| `make check-all` | contrôle de dérive de tout le parc actif (lecture seule, non mutant) |
| `make lint-registry` | valide le registre d'exemple (même validateur que `GSO-T06`) |
| `make lint-vault` | valide le modèle de vault d'exemple (même validateur que `GSO-T07`) |
| `make lint-lifecycle` | valide `registry/retired-sites.yml` + `reactivated-sites.yml` (lecture seule, L8) |
| `make matrix` / `make matrix-check` | régénère / vérifie `docs/COMPLIANCE-MATRIX.md` (204 exigences, L10) |
| `make clean` | supprime les artefacts locaux non suivis |

## Structure

```
ansible.cfg          aucun inventaire par défaut ; -i explicite obligatoire
requirements.yml     unique source de vérité de la version du rôle (tag épinglé)
Makefile             points d'entrée documentés
inventories/example/ inventaire + registre grav_sites (L1) + vault.yml.example (L2)
inventories/production/  fourni hors dépôt ; jamais suivi par Git
playbooks/           deploy/restart/stop-site.yml (mutations) + check-site/check-all.yml (contrôle L6) + _shared/
registry/            retired-sites.yml + reactivated-sites.yml (documentaires L8, hors group_vars, jamais auto-chargés)
scripts/             sélecteur + préflight (L3) ; deploy/restart/stop-site.sh + lib/site-mutation.sh (mutations, verrou) ; check-site/check-all.sh + lib/site-check.sh + lib/gso_classify.py (contrôle L6, sans verrou) ; lib/gso_validate.py = validateur partagé ; lib/gso_lifecycle.py = validateur cycle de vie L8 (lecture seule)
tests/               scripts GSO-T*, lanceur, helpers (tests/lib/), fixtures
docs/                architecture, contrat, schémas registre/vault/cycle de vie, exploitation, migration (L9), TEST-RESULTS + COMPLIANCE-MATRIX (L10), ACCEPTANCE (L11), versionnement, gouvernance
.github/workflows/   CI (jobs statiques)
```

Modèle de données : [`docs/REGISTRY-SCHEMA.md`](docs/REGISTRY-SCHEMA.md) (registre non secret) ·
[`docs/VAULT-SCHEMA.md`](docs/VAULT-SCHEMA.md) (vault : bootstrap admin, `grav_secrets`).

## Dépendances

`grav-sites-ops` est **indépendant** du `control-repository`, des dépôts
d'images applicatives et de `grav-runtime`. Sa seule dépendance déclarée est le
rôle `sepp67.grav_site`, épinglé dans `requirements.yml`.

## Licence

**Non encore fixée** (résidu de lot L0). L11 la signale comme **décision
humaine bloquante** : un fichier `LICENSE` doit être décidé et ajouté avant
toute release publique (voir `docs/ACCEPTANCE.md` §4). L11 ne choisit aucune
licence.
