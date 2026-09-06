# Schéma du registre `grav_sites`

Résumé normatif : contrat architectural `v0.5.0`, sections 3.3, 7 et 8
(`docs/CONTRAT-ARCHITECTURAL.md`). En cas de divergence, le contrat fait foi.

Ce document est livré par le **lot L1**. Il décrit la couche de données
déclaratives : inventaire, groupe `grav_servers`, registre `grav_sites`,
contraintes d'unicité, chargement automatique. Il **n'aborde pas** les secrets
ni le vault (lot L2), ni la sélection de cible (lot L3), ni la traduction vers
le rôle (lot L4).

## Les quatre ensembles de données

| Ensemble | Emplacement | Sensibilité | Lot |
|---|---|---|---|
| Inventaire | `inventories/<env>/hosts.yml` | opérationnel, non secret | L1 |
| Registre actif | `inventories/<env>/group_vars/all/grav_sites.yml` | opérationnel, non secret | L1 |
| Vault global | `inventories/production/group_vars/all/vault.yml` (opérationnel) · `inventories/example/group_vars/all/vault.yml.example` (modèle) | secret, chiffré, non suivi / modèle synthétique en clair | L2 — voir [`VAULT-SCHEMA.md`](VAULT-SCHEMA.md) |
| Registre retiré | `registry/retired-sites.yml`, `registry/reactivated-sites.yml` | historique, non secret | L8 |

Le **nom d'hôte d'inventaire** est l'unique clé de jointure entre ces ensembles
(GSO-REQ-008, GSO-REQ-037). Aucun identifiant secondaire, aucune table de
traduction.

## Environnements

- `inventories/production/` — environnement **durable unique** des sites Grav
  (GSO-REQ-005). **Fourni hors dépôt**, jamais suivi par Git ; son `vault.yml`
  est git-ignoré. Non créé à ce stade.
- `inventories/example/` — inventaire d'exemple pour les tests et la
  documentation (GSO-REQ-006). Adresses TEST-NET-1 (`192.0.2.0/24`, RFC 5737),
  données fictives, jamais utilisable comme production (GSO-REQ-058,
  GSO-REQ-068).

`ansible.cfg` ne désigne aucun inventaire par défaut : chaque commande fournit
`-i` explicitement (GSO-REQ-053).

## Inventaire et groupe `grav_servers`

Les hôtes actifs appartiennent au groupe unique et explicite `grav_servers`
(GSO-REQ-054). Une VM dédiée par projet, un hôte d'inventaire par VM
(GSO-REQ-007, GSO-REQ-036).

```yaml
all:
  children:
    grav_servers:
      hosts:
        grav-example-alpha:
          ansible_host: 192.0.2.11
```

Dans l'inventaire de production, `ansible_host` porte l'adresse LAN réelle de la
VM ; les paramètres de connexion (`ansible_user`, port SSH, élévation) sont
définis au niveau approprié de l'inventaire, sans mot de passe en clair. Les
exemples n'utilisent que des adresses documentaires.

## Registre `grav_sites`

Dictionnaire racine **unique** `grav_sites` (GSO-REQ-128), dans un fichier de
`group_vars/all/` chargé automatiquement par Ansible — aucun `include_vars`,
aucun chemin de workstation (GSO-REQ-012). Chaque fichier auto-chargé a des
clés racines distinctes ; la conformité ne dépend pas de l'ordre de chargement.

Correspondance **totale** : tout hôte de `grav_servers` a exactement une entrée
`grav_sites`, et réciproquement (GSO-REQ-013).

### Champs obligatoires

| Champ | Règle |
|---|---|
| `project_name` | identité humaine stable ; unique dans le parc |
| `image` | image applicative **sans tag ni digest incorporé** (GSO-REQ-010) |
| `version` | version humaine explicite, non vide, jamais `latest` (GSO-REQ-021, GSO-REQ-154) |
| `digest` | chaîne vide `""` ou `sha256:<64 hex>` ; ne remplace jamais `version` |
| `container_name` | nom Docker unique dans la VM ; unique dans le parc |
| `base_directory` | chemin absolu propre au projet ; unique dans le parc |
| `bind_address` | adresse **IPv4 littérale** de la VM sur le LAN (GSO-REQ-065) |
| `http_port` | entier `1`–`65535` (GSO-REQ-065) |

### Champs optionnels reconnus

| Champ | Défaut | Notes |
|---|---|---|
| `state` | `started` | `started` \| `stopped` \| `restarted` — jamais destructif (GSO-REQ-051) |
| `force_pull` | `false` | |
| `manage_docker` | `true` | |
| `site_check_path` | (défaut du rôle) | chemin HTTP de contrôle applicatif |
| `extra_environment` | `{}` | variables d'environnement supplémentaires, non secrètes |

Un défaut n'est défini qu'à un seul niveau (valeur commune documentée dans
`inventories/production/group_vars/all/main.yml`, ou défaut public du rôle) —
jamais redéfini à plusieurs endroits (contrat §7.3, §7.6).

Les noms de champs ci-dessus sont **propres à l'orchestrateur**. Leur traduction
vers les variables publiques `grav_*` du rôle est centralisée dans les
playbooks et introduite au **lot L4** ; le registre ne contient jamais de
fragment de tâche Ansible.

### Sémantique de `state`

- `started` — état normal d'un projet actif.
- `stopped` — conteneur arrêté sur une VM toujours administrée. Ni retrait du
  parc, ni arrêt de la VM, ni suppression de données.
- `restarted` — redémarrage demandé.

Aucune valeur n'entraîne la suppression de volumes persistants (GSO-REQ-051).

## Contraintes d'unicité (GSO-REQ-050)

Le préflight doit faire échouer, **avant toute mutation**, toute collision sur :

- `project_name` ;
- `container_name` ;
- `base_directory` ;
- le couple (`bind_address`, `http_port`) ;
- l'égalité clé de registre ↔ hôte actif ;
- l'absence de la clé dans `retired_grav_sites` (GSO-REQ-052 ; vérifié dès que
  `registry/retired-sites.yml` existe, lot L8).

Au lot L1, ces contrôles sont réalisés par le validateur statique
`tests/lib/registry_lint.py` sur l'inventaire d'exemple. Leur intégration au
préflight opérateur avant déploiement relève des lots L3–L4.

## Ce qui n'est pas dans le registre

- la version de `grav-runtime` (transitive via l'image — GSO-REQ-011,
  GSO-REQ-155) ;
- un tag d'image (`image` reste sans tag — GSO-REQ-010, GSO-REQ-020) ;
- le moindre secret ou identifiant (lot L2) ;
- une variable de sélection de cible type `grav_site_target` (GSO-REQ-037).
