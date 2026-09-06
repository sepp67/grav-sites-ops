# Schéma du vault `grav-sites-ops`

Résumé normatif : contrat architectural `v0.5.0`, sections 4.3, 9.4 et 11
(`docs/CONTRAT-ARCHITECTURAL.md`). En cas de divergence, le contrat fait foi.

Livré par le **lot L2** : modèle de vault d'exemple, schéma des paramètres
administrateur et de `grav_secrets`, garde Git du vault. **N'aborde pas** la
sélection de cible ni le préflight opérateur (lot L3), ni la traduction vers le
rôle (lot L4), ni le flux de retrait (lot L8).

## Vault opérationnel vs modèle d'exemple

| | Vault opérationnel | Modèle d'exemple |
|---|---|---|
| Chemin | `inventories/production/group_vars/all/vault.yml` | `inventories/example/group_vars/all/vault.yml.example` |
| Chiffrement | Ansible Vault, obligatoire | aucun (clair) |
| Contenu | secrets réels | valeurs **manifestement fictives**, aucun secret |
| Suivi Git | **jamais** (GSO-REQ-023, GSO-REQ-042, GSO-REQ-069) | oui, par une exception `.gitignore` étroite et nommée |
| Chargement Ansible | automatique (`group_vars/all/`) | **non** (extension `.example`) |
| Mot de passe | fourni par l'environnement opérateur, jamais dans le dépôt | sans objet |

Un **seul** vault opérationnel global pour tout le parc (GSO-REQ-022). Il est
fourni hors dépôt ; `grav-sites-ops` ne le lit, ne le copie et ne le déchiffre
jamais dans ses tests ou sa CI (GSO-REQ-024).

### Garde Git (GSO-REQ-098)

`.gitignore` ignore toute forme de fichier de vault (`**/vault.yml`,
`**/vault.yaml`, `**/vault_*.yml`, `**/vault-*.yml`, `**/*.vault`,
`**/vault.yml.example`, fichiers de mot de passe). **Une seule** ré-inclusion,
au chemin exact `inventories/example/group_vars/all/vault.yml.example`. Un vault
réel placé n'importe où — y compris un `.example` ailleurs — reste ignoré.
`GSO-T24` vérifie ce comportement ; `GSO-T07` vérifie le contenu.

## Structure du vault

Deux dictionnaires racines, et seulement ceux-là :

```yaml
vault_grav_sites:          # sites actifs
  <nom-hôte>:
    ...
vault_retired_grav_sites:  # secrets des projets retirés — {} tant qu'aucun
```

`<nom-hôte>` est la clé de jointure : exactement les mêmes clés que
`grav_servers` (inventaire) et que `grav_sites` (registre) — ni orpheline, ni
manquante, ni surnuméraire (GSO-REQ-061, GSO-REQ-013). Une clé n'est jamais
simultanément dans `vault_grav_sites` et `vault_retired_grav_sites`
(GSO-REQ-073).

## Bootstrap administrateur

Traduit vers les variables publiques `grav_admin_*` du rôle (lot L4).

| Champ du vault | `grav_*` | Règle |
|---|---|---|
| `admin_user` | `grav_admin_user` | **tri-state** |
| `admin_password` | `grav_admin_password` | **tri-state** |
| `admin_email` | `grav_admin_email` | **tri-state** |
| `admin_fullname` | `grav_admin_fullname` | optionnel |
| `admin_title` | `grav_admin_title` | optionnel |
| `admin_language` | `grav_admin_language` | optionnel |
| `admin_type` | `grav_admin_type` | optionnel ; `""` \| `admin` \| `api` \| `both` |

**Tri-state (GSO-REQ-062)** : `admin_user` + `admin_password` + `admin_email`
sont soit **toutes les trois présentes et non vides**, soit **toutes absentes**
— jamais un sous-ensemble. C'est le contrat de complétude imposé par
`ansible-role-grav-site v2.0.0` (`tasks/assert.yml`).

Les champs `admin_fullname` / `admin_title` / `admin_language` / `admin_type`
ne sont pas, isolément, confidentiels. Leur regroupement dans le vault est une
**simplification volontaire** (traduction atomique, aucune jointure
registre ↔ vault), pas une affirmation qu'ils sont secrets.

`admin_*` ne vit **que** dans le vault : le registre non secret `grav_sites.yml`
ne contient jamais de champ `admin_*` ni `secrets` (GSO-REQ-203, GSO-REQ-024).

Modifier une valeur `admin_*` n'est **pas** une rotation garantie d'un compte
Grav déjà persistant (GSO-REQ-071) — voir contrat §11.3.

## Secrets applicatifs — `secrets` → `grav_secrets`

Liste **optionnelle** sous `vault_grav_sites[<hôte>].secrets`, traduite **telle
quelle** vers `grav_secrets` du rôle (lot L4), sans transformation.

```yaml
    secrets:
      - name: email-private.php
        content: |
          <contenu inline synthétique>
```

Règles (GSO-REQ-203) :

- chaque élément a **exactement** `name` et `content` — aucune autre clé ;
- `name` : `^[A-Za-z0-9][A-Za-z0-9._-]*$`, jamais `..`, `/` ni `:` (forme
  validée à l'identique par `ansible-role-grav-site`) ;
- `content` : contenu inline non vide ;
- **la forme `src`** de l'interface du rôle **est interdite** dans
  `grav-sites-ops` : un chemin de fichier local réintroduirait une source de
  secret hors du vault unique (GSO-REQ-022) ;
- `name` et `content` restent dans le même élément du vault, jamais répartis
  entre le vault et le registre.

## Non-divulgation

- Les validateurs (`tests/lib/vault_lint.py`) n'affichent **aucune valeur** :
  uniquement des clés, des comptes et des verdicts.
- Les tests emploient des marqueurs synthétiques (`EXAMPLE-NOT-A-REAL-SECRET…`)
  et vérifient qu'ils n'apparaissent ni dans les sorties, ni dans un autre
  fichier suivi (GSO-REQ-024, GSO-REQ-074).
- Aucune valeur de ce modèle n'est réutilisable : domaines `*.example.invalid`,
  mots de passe littéralement marqués comme non réels.

## Retrait (aperçu, lot L8)

Au retrait d'un projet, son entrée est **déplacée** de `vault_grav_sites` vers
`vault_retired_grav_sites` dans le même vault (GSO-REQ-073), en conservant le
même schéma. Les secrets archivés ne sont jamais copiés dans
`registry/retired-sites.yml`. Le détail du flux relève du lot L8.
