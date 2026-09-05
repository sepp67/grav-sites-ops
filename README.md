# grav-sites-ops

Dépôt d'orchestration Ansible consacré à l'**exploitation** d'un parc de sites
web [Grav](https://getgrav.org/) sur des VM existantes du réseau local.

`grav-sites-ops` décrit l'état désiré du parc et invoque, pour chaque machine
explicitement sélectionnée, le rôle atomique
[`ansible-role-grav-site`](https://github.com/sepp67/ansible-role-grav-site)
(`sepp67.grav_site`). Il ne définit pas le mécanisme interne de déploiement
d'une instance Grav : ce mécanisme appartient exclusivement au rôle.

## Statut

**Construction en cours — lot L0 (harnais).**

Le dépôt est un squelette **non opérationnel par défaut** : il ne contient ni
inventaire de production, ni vault, ni playbook. Aucune commande de déploiement
n'existe encore.

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
| `make clean` | supprime les artefacts locaux non suivis |

## Structure

```
ansible.cfg          aucun inventaire par défaut ; -i explicite obligatoire
requirements.yml     unique source de vérité de la version du rôle (tag épinglé)
Makefile             points d'entrée documentés
inventories/         example/ (fixtures de test) ; production/ fourni hors dépôt
playbooks/           opérations Ansible (ajoutées à partir du lot L4)
registry/            historiques retired-sites / reactivated-sites (lot L8)
scripts/             contrôles locaux, dont la validation de cible (lot L3)
tests/               scripts GSO-T* et lanceur
docs/                architecture, versionnement, gouvernance
.github/workflows/   CI (jobs statiques)
```

## Dépendances

`grav-sites-ops` est **indépendant** du `control-repository`, des dépôts
d'images applicatives et de `grav-runtime`. Sa seule dépendance déclarée est le
rôle `sepp67.grav_site`, épinglé dans `requirements.yml`.

## Licence

Non encore fixée (résidu de lot L0, voir le rapport d'exécution).
