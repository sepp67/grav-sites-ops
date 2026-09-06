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
site).**

Le dépôt reste **non opérationnel par défaut** : ni inventaire de production,
ni vault opérationnel. Les seules données versionnées sont l'inventaire, le
registre et le modèle de vault d'**exemple** (`inventories/example/…`),
entièrement synthétiques. `make validate` / `make preflight` sont en lecture
seule ; `make deploy SITE=<hôte>` exécute le chemin complet
sélecteur → verrou → préflight → rôle, mais **échoue tant qu'aucun
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
| `make test` | exécute toute la batterie de tests disponible (`GSO-T*`) |
| `make test-static` | tests statiques uniquement (sans accès réseau) |
| `make test-role` | vérifie l'installation du rôle (accès réseau requis) |
| `make validate SITE=<hôte>` | sélecteur fermé, lecture seule (voir `docs/OPERATIONS.md`) |
| `make preflight SITE=<hôte>` | préflight opérateur, lecture seule |
| `make deploy SITE=<hôte>` | déploie / actualise l'instance d'un site (sélecteur → verrou → rôle) |
| `make lint-registry` | valide le registre d'exemple (même validateur que `GSO-T06`) |
| `make lint-vault` | valide le modèle de vault d'exemple (même validateur que `GSO-T07`) |
| `make clean` | supprime les artefacts locaux non suivis |

## Structure

```
ansible.cfg          aucun inventaire par défaut ; -i explicite obligatoire
requirements.yml     unique source de vérité de la version du rôle (tag épinglé)
Makefile             points d'entrée documentés
inventories/example/ inventaire + registre grav_sites (L1) + vault.yml.example (L2)
inventories/production/  fourni hors dépôt ; jamais suivi par Git
playbooks/           opérations Ansible (ajoutées à partir du lot L4)
registry/            historiques retired-sites / reactivated-sites (lot L8)
scripts/             sélecteur fermé + préflight (L3) ; lib/gso_validate.py = validateur partagé
tests/               scripts GSO-T*, lanceur, helpers (tests/lib/), fixtures
docs/                architecture, contrat, schémas registre/vault, exploitation, versionnement, gouvernance
.github/workflows/   CI (jobs statiques)
```

Modèle de données : [`docs/REGISTRY-SCHEMA.md`](docs/REGISTRY-SCHEMA.md) (registre non secret) ·
[`docs/VAULT-SCHEMA.md`](docs/VAULT-SCHEMA.md) (vault : bootstrap admin, `grav_secrets`).

## Dépendances

`grav-sites-ops` est **indépendant** du `control-repository`, des dépôts
d'images applicatives et de `grav-runtime`. Sa seule dépendance déclarée est le
rôle `sepp67.grav_site`, épinglé dans `requirements.yml`.

## Licence

Non encore fixée (résidu de lot L0, voir le rapport d'exécution).
