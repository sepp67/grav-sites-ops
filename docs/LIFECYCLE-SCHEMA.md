# Schéma des registres de cycle de vie

Résumé normatif : contrat architectural `v0.5.0`, sections 7.7, 3.5 et 21
(`docs/CONTRAT-ARCHITECTURAL.md`). En cas de divergence, le contrat fait foi.

Livré par le **lot L8**. Décrit les deux fichiers **documentaires** qui
consignent le cycle de vie d'un projet retiré ou réactivé. Les **procédures**
opérateur (retrait, réactivation) sont dans [`OPERATIONS.md`](OPERATIONS.md).

## Nature des fichiers

| Fichier | Racine YAML | Rôle | Chargé par Ansible ? |
|---|---|---|---|
| `registry/retired-sites.yml` | `retired_grav_sites` | ensemble **exact** des projets **actuellement** retirés | **non** — lu explicitement |
| `registry/reactivated-sites.yml` | `reactivated_sites` | **historique append-only** des réactivations | **non** — lu explicitement |

- Suivis par Git, **hors de `group_vars/`** : jamais chargés automatiquement,
  jamais une source de déploiement.
- **Aucun secret**, jamais (les secrets archivés vivent dans
  `vault_retired_grav_sites` — voir [`VAULT-SCHEMA.md`](VAULT-SCHEMA.md)).
- Lus en **lecture seule** par `scripts/lib/gso_lifecycle.py`
  (`make lint-lifecycle`). Ce validateur **n'applique aucune transformation** :
  le retrait et la réactivation sont des opérations **Git manuelles**,
  vérifiées **après coup**.
- Le dictionnaire racine est **unique et fixe** ; toute autre clé racine, tout
  champ inconnu, toute date non `YYYY-MM-DD` est refusé. Les deux historiques
  ne dépendent **pas** de l'ordre de chargement des fichiers YAML : chaque
  fichier porte un seul dictionnaire racine, jamais fusionné avec un autre.

## `retired_grav_sites` — une fiche

```yaml
retired_grav_sites:
  grav-example:
    project_name: projet-example          # obligatoire
    retired_at: "2026-09-04"               # obligatoire — date ISO YYYY-MM-DD
    former_inventory_host: grav-example    # obligatoire — ancien nom d'hôte
    former_ansible_host: 192.0.2.10        # obligatoire — adresse TEST-NET / privée
    former_base_directory: /opt/projet-example   # obligatoire — chemin absolu
    container_name: projet-example         # obligatoire
    last_deployment:                       # obligatoire
      image: registry.example.invalid/example/grav-site
      version: "1.0.0"
      digest: ""
    preservation:                          # obligatoire
      vm_status: stopped                   # stopped | running | unknown
      vm_preserved: true                   # booléen
      persistent_data_preserved: true      # booléen
      secrets_archived_in_vault: true      # booléen (drapeau, pas un secret)
    reason: Projet mis temporairement de côté   # obligatoire
```

- **Ensemble fermé de champs** : aucun autre n'est admis. En particulier,
  **jamais** de champ `status` : une fiche `retired_grav_sites` ne porte
  **jamais** le statut `reactivated` (contrat §21.9).
- `last_deployment` : `image`, `version`, `digest` obligatoires ; aucune
  référence `latest`.
- `preservation` : les quatre champs obligatoires ; les trois drapeaux sont
  des booléens.

## `reactivated_sites` — un événement

```yaml
reactivated_sites:
  grav-example:                            # clé -> LISTE d'événements (append-only)
    - reactivated_at: "2026-09-04"         # obligatoire — date ISO
      project_name: projet-example         # obligatoire
      former_inventory_host: grav-example  # obligatoire
      previous_retirement:                 # obligatoire
        retired_at: "2026-08-01"           # obligatoire — date ISO, ≤ reactivated_at
        reason: Projet mis temporairement de côté   # obligatoire
        # `previous_retirement` PEUT porter une copie complète de la dernière
        # fiche retirée (mêmes champs que `retired_grav_sites`).
```

- Chaque clé est associée à une **liste** non vide d'événements.
- **Append-only** : une nouvelle réactivation **ajoute** un événement ; les
  événements antérieurs ne sont **jamais** modifiés ni supprimés. Les
  `reactivated_at` d'une même clé sont en **ordre chronologique**.
- Un projet retiré → réactivé → retiré → réactivé conserve **tous** ses
  événements.

## Disjonction stricte (GSO-REQ-052, GSO-REQ-073, §21.9)

Vérifiée par `make lint-lifecycle` dès qu'un registre actif et/ou un vault
sont fournis :

| Invariant | Règle |
|---|---|
| `grav_sites` ∩ `retired_grav_sites` = ∅ | **sans exception** : une clé active n'est jamais retirée, et inversement |
| `vault_grav_sites` ∩ `vault_retired_grav_sites` = ∅ | une clé n'est jamais dans les deux ensembles de vault |
| GSO-REQ-073 | un projet retiré ne conserve **aucune** entrée dans `vault_grav_sites` ; ses secrets sont dans `vault_retired_grav_sites` |
| Site actif ∉ `vault_retired_grav_sites` | un site actif n'a jamais de secret archivé |
| GSO-REQ-181 | une clé présente dans `reactivated_sites` **et** dans `retired_grav_sites` n'est légitime que si son `retired_at` courant est **postérieur** à sa dernière réactivation (elle a été retirée à nouveau) |
| Réactivation atomique | la fiche est retirée de `retired_grav_sites` **dans la même opération Git** qui rétablit la clé dans `grav_sites` et ajoute l'événement à `reactivated_sites` |

## Ce que le validateur ne fait jamais

- écrire ou modifier un fichier (lecture seule stricte) ;
- appliquer un retrait ou une réactivation ;
- ouvrir un vault chiffré, contacter une machine, lancer un sous-processus ;
- charger `registry/*.yml` comme variables Ansible.
