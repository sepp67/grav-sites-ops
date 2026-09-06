# Architecture de `grav-sites-ops`

Ce document résume l'architecture normée par le **contrat architectural
`v0.5.0`** (statut : normatif, approuvé le 2026-09-05), dont une copie exacte
est conservée dans [`CONTRAT-ARCHITECTURAL.md`](CONTRAT-ARCHITECTURAL.md)
(GSO-REQ-198).

### Ordre de préséance

1. `docs/CONTRAT-ARCHITECTURAL.md` — source normative ; fait foi en cas de
   divergence.
2. Le présent document et les autres fichiers `docs/` — résumés et guides
   d'application, non normatifs.
3. Le code (playbooks, scripts, tests, CI) — mise en œuvre.

Un résumé qui contredirait le contrat est un défaut du résumé, jamais une
évolution de la règle.

## Responsabilité unique

`grav-sites-ops` **décrit l'état désiré** d'un parc de sites Grav et
**invoque** le rôle atomique `sepp67.grav_site` pour chaque machine
explicitement sélectionnée. Il répond à : quels projets sont actifs, sur
quelles VM, avec quelle image et quelle référence, quels paramètres par
instance, quelle opération sur quelle cible, quels projets sont retirés mais
archivés.

## Ce que ce dépôt ne fait pas

- il ne construit, ne teste ni ne publie d'images (dépôts `grav-runtime`,
  `projet-*`) ;
- il ne provisionne pas de VM : les VM sont des ressources préexistantes ;
- il ne reproduit pas la logique interne du rôle (pas de tâches Docker/Grav
  propres, pas de rôle encapsulant le rôle) ;
- il n'orchestre aucun service autre que Grav ;
- il ne dépend en rien du `control-repository`.

## Chaîne de dépendance

```
grav-runtime  →  projet-gites | projet-lavallee  →  ansible-role-grav-site  →  VM cible
                                                          ▲
                                                          │  requirements.yml (tag épinglé)
                                                   grav-sites-ops
```

`grav-sites-ops` ne connaît que l'**interface publique** du rôle. Sa version
est déclarée uniquement dans `requirements.yml`.

## Invariants (rappel)

- une VM dédiée par projet ;
- un environnement durable unique : `production` ;
- sélection explicite d'une cible unique avant toute mutation ; jamais `all` ;
- secrets non suivis par Git, non divulgués ;
- persistance prioritaire ; aucune destruction automatisée ;
- cloisonnement CI / production : la CI n'ouvre jamais le vault réel et ne
  contacte jamais une VM ;
- toute évolution d'un invariant passe par un amendement du contrat *avant*
  le code.

## Frontières inter-dépôts

| Dépôt | Relation | Interdits |
|---|---|---|
| `ansible-role-grav-site` | consommé via `requirements.yml` (tag) | modification depuis ce dépôt |
| `grav-runtime`, `projet-*` | fournissent les images référencées dans le registre | build/publish ici |
| `control-repository` | **aucune** | dépendance Ansible/Git/CI/exécution |

## Structure du dépôt

Voir `README.md`. Les répertoires `playbooks/` et `registry/` apparaissent
progressivement, lot par lot, selon le préflight de construction.
`inventories/production/` est fourni hors dépôt et n'est jamais suivi par Git.

## Sélection de cible et préflight

Toute opération part du **sélecteur fermé** (`scripts/validate-target.sh`) puis
du **préflight opérateur** (`scripts/preflight.sh`), tous deux en lecture seule
et adossés à une **implémentation unique** des règles de validation
(`scripts/lib/gso_validate.py`, partagée avec les tests). Détails :
[`OPERATIONS.md`](OPERATIONS.md).

## Modèle de données

- **Registre non secret** (inventaire, groupe `grav_servers`, `grav_sites`,
  unicité, chargement automatique) : [`REGISTRY-SCHEMA.md`](REGISTRY-SCHEMA.md).
- **Vault** (bootstrap administrateur tri-state, `grav_secrets` sous la forme
  `name` + `content`, garde Git, disjonction actif/retiré) :
  [`VAULT-SCHEMA.md`](VAULT-SCHEMA.md).

Le registre non secret ne contient jamais de secret ; le vault opérationnel
(chiffré, fourni hors dépôt) n'est jamais suivi par Git ni lu par la CI. Seul un
**modèle d'exemple en clair et synthétique** est versionné.
