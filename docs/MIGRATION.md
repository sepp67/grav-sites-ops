# Migration depuis l'ancien profil d'exploitation

Résumé normatif : contrat architectural `v0.5.0`, **section 20** et §3.5, §11.2,
§17.7-17.8 (`docs/CONTRAT-ARCHITECTURAL.md`). En cas de divergence, le contrat
fait foi.

Livré par le **lot L9**. Ce document est **documentaire et probatoire** : il
décrit une procédure **manuelle**, site par site, exécutée par l'opérateur.
`grav-sites-ops` **ne fournit aucun script, playbook ou cible `make`** qui
applique une migration (garde-fou : `tests/l9-migration-doc-guard.sh`).

> **L9 ne migre aucun site réel.** L'exécution réelle de la migration est une
> **décision humaine distincte de la construction** (GSO-REQ-188, GSO-REQ-163),
> autorisée séparément. Les fixtures de ce lot (`tests/fixtures/l9-*`) sont
> **entièrement synthétiques**.

---

## 0. Ce que la migration transfère — et ne transfère pas

| Transféré vers `grav-sites-ops` | **Jamais** transféré |
|---|---|
| les **données d'exploitation** : hôtes, définitions non secrètes, secrets | les playbooks, templates, tâches ou rôles de `ansible-role-grav-site` (GSO-REQ-133) |
| reclassées selon le **schéma du contrat** (registre + vault) | l'ancien fichier `main.yml` copié **en bloc** |
| les **chemins persistants existants**, conservés à l'identique | le **contenu** des volumes (jamais recopié ni réinitialisé) |

**Principe de non-destruction (GSO-REQ-160) :** la migration est une **copie
contrôlée suivie d'une validation**. Elle ne commence **jamais** par le
déplacement, le renommage ou la suppression d'un fichier source. Aucun fichier
historique non suivi n'est touché avant la validation complète de sa
destination.

---

## 1. Précondition — harnais vert avant toute donnée réelle (GSO-REQ-163)

Avant d'introduire le moindre profil réel :

- [ ] `make test-reproducible` — **vert** (batterie complète, doublures) ;
- [ ] `make lint` — **0 faute** ;
- [ ] `make lint-lifecycle` — **vert** ;
- [ ] `make test-functional` (GSO-T15) — **vert** au moins une fois sur la
      station de migration ;
- [ ] `inventories/production/` **n'existe pas encore** (le dépôt est non
      opérationnel par défaut).

Tant qu'un de ces points est rouge, **la migration ne commence pas**.

---

## 2. Inventaire et diagnostic de l'existant (GSO-REQ-162 — sans divulgation)

L'ancien profil se trouve dans l'ancien dépôt `ansible-role-grav-site`,
notamment :

```text
inventories/production/hosts.yml
inventories/production/group_vars/grav_servers/main.yml     # variables grav_* à plat
inventories/production/group_vars/grav_servers/vault.yml    # secrets à plat, NON suivi
```

Produire un **rapport de diagnostic** (`docs/`, hors secrets) qui identifie,
**sans jamais reproduire une valeur du vault** :

- [ ] les fichiers suivis historiques **déjà retirés** du rôle ;
- [ ] le **vault local non suivi** : chemin, date, taille, permissions, somme
      de contrôle — **pas** le contenu ;
- [ ] les **noms de variables publiques** présentes (`grav_image`,
      `grav_version`, `grav_container_name`, …) ;
- [ ] les **projets / hôtes** représentés ;
- [ ] les **valeurs manquantes** ou **variables obsolètes** ;
- [ ] les indirections `{{ vault_* }}` de `main.yml` vers le vault.

Le rapport est **descriptif** : il ne modifie rien.

---

## 3. Sauvegarde externe vérifiée du vault (GSO-REQ-070, 160, 161 — contrat §20.3)

**Bloquant.** La migration du vault est interdite tant que cette sauvegarde
n'existe pas et n'a pas été vérifiée. Cette exigence est satisfaite par une
**preuve documentaire** (rapport d'opérateur daté) et **n'est pas vérifiable
par un test automatisé**.

Procédure :

1. **Choisir un chemin de destination explicite, HORS des deux dépôts**
   (`grav-sites-ops` et `ansible-role-grav-site`) — p. ex. un support amovible
   chiffré ou `$HOME/backups/grav-vault/`. Ce chemin **ne doit jamais** être
   à l'intérieur d'un dépôt Git.
2. **Copier le vault historique chiffré** vers cette destination, **sans le
   déchiffrer** :
   ```bash
   src="…/ansible-role-grav-site/inventories/production/group_vars/grav_servers/vault.yml"
   dst="$HOME/backups/grav-vault/vault-$(date +%Y%m%d).yml"
   umask 077 && cp -p "$src" "$dst"
   chmod 600 "$dst"
   ```
3. **Permissions restrictives** : `600` (ou `400`) sur la copie, répertoire
   parent `700`.
4. **Somme de contrôle avant / après** — elle prouve l'**identité des octets**,
   pas la validité du mot de passe ni la complétude logique :
   ```bash
   sha256sum "$src" "$dst"        # les deux empreintes DOIVENT être identiques
   ```
5. **Preuve de lisibilité / déchiffrabilité** par le mécanisme autorisé, **sans
   afficher le contenu** :
   ```bash
   ansible-vault view "$dst" >/dev/null   # rc 0 = déchiffrable ; aucune valeur affichée
   ```
   (`--vault-password-file` ou `--ask-vault-pass` selon l'environnement
   opérateur ; le mot de passe **n'est jamais** stocké dans un dépôt.)
6. **Consigner** dans le rapport de migration : chemin, date, taille,
   permissions, somme de contrôle, résultat de la vérification Ansible Vault.
7. **Conservation séparée** : la sauvegarde reste hors des dépôts, pendant une
   période de sécurité décidée par l'opérateur.
8. **Exclusion Git** : vérifier que le chemin de sauvegarde **ne peut pas** être
   suivi (il est hors dépôt ; par sécurité, `git check-ignore` sur tout chemin
   de forme `vault*` reste actif — `.gitignore`, GSO-REQ-069).
9. **Arrêt immédiat** si l'une des vérifications échoue (empreintes
   différentes, `ansible-vault view` en erreur, permissions trop larges) :
   **ne pas poursuivre**, corriger, recommencer.

---

## 4. Cartographie ancien → nouveau (GSO-REQ-133, 164 — traduction explicite)

Aucune conversion **implicite**. Chaque variable migrée a une **destination
documentée** ou est **explicitement classée obsolète**. La clé de jointure est
le **nom d'hôte d'inventaire** (`inventory_hostname`).

| Ancien profil (`ansible-role-grav-site`) | Nouveau (`grav-sites-ops`) | Notes |
|---|---|---|
| hôte de `inventories/production/hosts.yml` (groupe `grav_servers`) | **`inventory_hostname`** | clé de jointure unique — jamais un identifiant secondaire |
| `ansible_host` (inventaire) | `inventories/production/hosts.yml` → `ansible_host` | recopié tel quel |
| `grav_image` (`main.yml`, à plat) | `grav_sites[<hôte>].image` | |
| `grav_version` (`main.yml`) | `grav_sites[<hôte>].version` | jamais `latest` ; revoir contre un tag réellement publié |
| *(absent dans l'ancien)* | `grav_sites[<hôte>].digest` | **décision humaine** : `""` (référence par tag) ou digest vérifié épinglé |
| `grav_container_name` | `grav_sites[<hôte>].container_name` | **chemin structurant** — §5 |
| `grav_base_directory` | `grav_sites[<hôte>].base_directory` | **chemin structurant** — §5 ; **jamais** recréé ni réinitialisé |
| `grav_bind_address` (souvent `0.0.0.0`) | `grav_sites[<hôte>].bind_address` | v2.0.0 accepte IPv4 stricte ou `0.0.0.0` ; IPv6 refusée |
| `grav_http_port` | `grav_sites[<hôte>].http_port` | **chemin structurant** (exposition) — §5 |
| *(implicite `started`)* | `grav_sites[<hôte>].state` | **décision humaine** documentée : `started` / `stopped` |
| `grav_force_pull`, `grav_manage_docker`, `grav_site_check_path`, `grav_extra_environment` | mêmes clés sous `grav_sites[<hôte>]` **si présentes** ; sinon défauts du rôle | ne pas inventer de valeur |
| `grav_admin_user` = `{{ vault_grav_admin_user }}` | `vault_grav_sites[<hôte>].admin_user` | l'**indirection est résolue** : la valeur réelle passe dans le nouveau vault |
| `grav_admin_password` = `{{ vault_grav_admin_password }}` | `vault_grav_sites[<hôte>].admin_password` | tri-state : 0 **ou** 3 identifiants |
| `grav_admin_email` = `{{ vault_grav_admin_email }}` | `vault_grav_sites[<hôte>].admin_email` | |
| `grav_admin_fullname` / `_title` / `_language` | `vault_grav_sites[<hôte>].admin_fullname` / `_title` / `_language` | optionnels |
| *(éventuel)* `grav_admin_type` | `vault_grav_sites[<hôte>].admin_type` | ∈ `{'', 'admin', 'api', 'both'}` |
| `grav_secrets: [{name, content: "{{ vault_… }}"}]` | `vault_grav_sites[<hôte>].secrets: [{name, content}]` | forme `name` + `content` **uniquement** ; **jamais** `src` ; nom `^[A-Za-z0-9][A-Za-z0-9._-]*$` |
| état des volumes existants (`pages`, `accounts`, `data`, `images` sous `base_directory`) | **conservés en place** sur la VM | **jamais** recopiés, déplacés ou réinitialisés automatiquement |

**Champ sans correspondance normative** → **arrêt** et **décision humaine
documentée** dans le rapport (destination retenue, ou classification
« obsolète » avec justification). Ne jamais deviner.

---

## 5. Chemins structurants — toute modification est une migration (renvoi GSO-REQ-176)

Les éléments suivants **ne doivent jamais** être modifiés silencieusement par
un déploiement ordinaire. En modifier **un seul** est une **migration
structurante** qui **désolidarise l'instance de ses volumes** :

1. l'**identité de l'hôte** (`inventory_hostname`) ;
2. `container_name` ;
3. `base_directory` ;
4. l'**adresse ou le port d'exposition** (`bind_address`, `http_port`) ;
5. l'**organisation des données persistantes** (sous-arborescence `pages` /
   `accounts` / `data` / `images`) ;
6. l'**emplacement ou la structure du vault**.

Si la migration doit changer l'un de ces éléments (p. ex. renommer un
conteneur), c'est une opération à part entière, **hors** de la migration
« à l'identique » : préciser dans le rapport, obtenir une décision humaine, et
traiter le déplacement des volumes séparément.

---

## 6. Migration site par site (GSO-REQ-167 — une à la fois)

> **Interdit :** toute forme de migration **globale** (boucle sur `grav_servers`,
> `--limit all`, script « migrate-all »). L'acceptation d'un site **précède**
> le début de la migration du site suivant.

Pour **chaque** site, dans l'ordre :

1. **Ajouter l'hôte** à `inventories/production/hosts.yml` (groupe
   `grav_servers`, `ansible_host`).
2. **Ajouter sa définition** non secrète à
   `inventories/production/group_vars/all/grav_sites.yml` selon la cartographie
   (§4). Ne pas copier l'ancien `main.yml`.
3. **Ajouter ses secrets** au **nouveau vault** (§7), sous
   `vault_grav_sites[<hôte>]`, indirections résolues.
4. **Examiner le diff Git** — un site à la fois, aucune autre entrée touchée.
5. **Préflight statique** :
   ```bash
   make validate  SITE=<hôte>
   make preflight SITE=<hôte>
   ```
6. **Contrôle de dérive** :
   ```bash
   make check SITE=<hôte>
   ```
   Comparer la **référence actuellement déployée** sur la VM à la référence
   désirée du registre — elles **doivent** coïncider (migration ≠ mise à jour).
7. **Revue humaine** du diff et des verdicts.
8. **Autorisation** explicite du premier déploiement de ce site (gate humain).
9. **Déploiement de validation** (§8).
10. **Vérification après déploiement** (§9).
11. **Consigner le verdict** de ce site **avant** de passer au suivant
    (GSO-REQ-171).

---

## 7. Création et vérification du nouveau vault (GSO-REQ-165, 166 — contrat §20.7-20.8)

Création :

- Le nouveau vault est créé **directement chiffré** à l'emplacement normatif
  `inventories/production/group_vars/all/vault.yml`.
- La transformation évite **tout fichier temporaire en clair suivi ou
  persistant** (GSO-REQ-165) : utiliser `ansible-vault create` / `edit`, ou un
  pipe en mémoire ; **ne jamais** écrire un export déchiffré sur disque.
- Structurer sous `vault_grav_sites[<hôte>]` ; commentaires pour séparer les
  projets ; comparer les clés à l'interface `ansible-role-grav-site v2.0.0`.

Vérification (**sans afficher les valeurs**) :

- [ ] le fichier est **chiffré** (`head -c 14` = `$ANSIBLE_VAULT`) ;
- [ ] il **s'ouvre** avec le mécanisme prévu (`ansible-vault view … >/dev/null`) ;
- [ ] **chaque hôte actif** possède une entrée ;
- [ ] **aucune entrée active orpheline** (clé sans hôte) ;
- [ ] le **bootstrap** respecte le tri-state du contrat du rôle (0 ou 3) ;
- [ ] **permissions restrictives** (`600`) ;
- [ ] **Git l'ignore effectivement** (`git check-ignore -q …/vault.yml`).

> La **seule existence** du nouveau `vault.yml` **n'est pas** une migration
> réussie (GSO-REQ-166).

---

## 8. Déploiement de validation (GSO-REQ-168 — sans upgrade implicite)

- Le premier déploiement depuis `grav-sites-ops` utilise **exactement la
  référence déjà attendue sur la VM** — `make deploy SITE=<hôte>` sur un
  registre qui reproduit `image:version` (+ `digest`) de l'existant.
- **Ne pas** combiner migration et montée de version applicative, sauf décision
  explicite et documentée.
- Le déploiement doit confirmer l'**idempotence** de l'orchestration et la
  **préservation des quatre volumes**.

---

## 9. Vérification après déploiement

- [ ] `make check SITE=<hôte>` → `IN_SYNC` : les **trois états** (désiré,
      appliqué, réel) concordent ;
- [ ] les **quatre chemins persistants** (`pages`, `accounts`, `data`,
      `images`) sont inchangés — mêmes chemins, contenu non touché ;
- [ ] l'endpoint HTTP répond comme avant ;
- [ ] `deployed_versions.log` (tenu par le rôle) n'a **pas** gagné de ligne si
      la référence est identique.

---

## 10. Critères de fin de migration (contrat §20.12) et autonomie (GSO-REQ-170)

La migration est **terminée** lorsque :

- [ ] chaque VM active est dans le nouvel inventaire ;
- [ ] chaque hôte a une définition **et** des secrets cohérents ;
- [ ] chaque site a réussi un `check` **et** un `deploy` ciblés ;
- [ ] références désirée / appliquée / réelle concordent pour tous ;
- [ ] les volumes sont préservés partout ;
- [ ] le **vault de destination est sauvegardé** (même procédure qu'au §3) ;
- [ ] **aucune opération courante ne dépend plus de l'ancien profil** —
      `grav-sites-ops` fonctionne **sans aucun chemin, lien ou lecture** dans
      l'ancien dépôt du rôle (GSO-REQ-170, garde-fou
      `tests/l9-migration-doc-guard.sh` + `GSO-T23`).

**Rapport de migration** (hors secrets, GSO-REQ-171) : étapes, preuves, écarts,
décisions ; **distinguer** tests locaux / contrôles sur VM / opérations non
réalisées ; **un verdict daté par site**.

---

## 11. Ancien vault et ancien profil après migration (GSO-REQ-169)

- L'**ancien vault est conservé** pendant une période de sécurité décidée par
  l'opérateur.
- Sa suppression éventuelle est une **opération humaine distincte**, précédée
  d'une **nouvelle** vérification de la sauvegarde et du nouveau vault.
- Le **nettoyage de l'ancien profil ne fait PARTIE ni d'un playbook, ni du
  commit de migration** (GSO-REQ-169). `grav-sites-ops` ne contient **aucun
  script** qui supprime automatiquement l'ancien fichier.

---

## 12. Retour arrière de la migration (GSO-REQ-172 — contrat §20.14)

> **Distinct du rollback d'image (lot L7).** Le rollback L7 change la
> `version`/`digest` désirée dans le registre puis redéploie. Le **retour
> arrière de migration** est **organisationnel** : les images et volumes de la
> VM **restent inchangés** ; seul **le point de contrôle Ansible utilisé par
> l'opérateur** change (on revient à l'ancien profil).

Possible **tant que l'ancien profil et sa sauvegarde sont conservés**.

À documenter, pour chaque site en cours de migration :

1. le **point de non-retour** éventuel (p. ex. après un `deploy` qui a modifié
   la référence effective — mais **pas** les volumes) ;
2. les **conditions d'arrêt avant mutation** : si le `check` révèle un écart
   inattendu, **s'arrêter** avant le `deploy` ;
3. les **fichiers déclaratifs à restaurer** : retirer l'entrée du site de
   `grav_sites.yml`, `vault.yml` et `hosts.yml` du nouveau dépôt (revue + commit
   Git explicite) ;
4. la **restauration de la configuration précédente** : l'opérateur reprend
   l'ancien profil comme point de contrôle — **sans supprimer** de données ;
5. la **vérification du vault sauvegardé** (§3) avant toute reprise ;
6. la **conservation des répertoires persistants** : `pages`, `accounts`,
   `data`, `images` restent en place sur la VM ;
7. **aucune destruction** de VM, de volume ou de contenu ;
8. une **revue humaine** avant toute reprise d'exploitation depuis l'ancien
   profil.

**Aucun script n'applique automatiquement ce retour arrière** — c'est une suite
d'opérations Git et opérateur manuelles.

---

## 13. Checklists opérateur condensées

### Avant de commencer

- [ ] harnais vert (§1)
- [ ] diagnostic de l'existant produit, sans secret (§2)
- [ ] **sauvegarde du vault vérifiée et consignée** (§3) — **bloquant**

### Pour chaque site

- [ ] hôte + définition + secrets ajoutés (un site, cartographie §4)
- [ ] aucun champ non mappé laissé implicite (§4)
- [ ] chemins structurants inchangés (§5)
- [ ] `validate` / `preflight` / `check` verts (§6)
- [ ] revue humaine + autorisation du premier déploiement (§6)
- [ ] `deploy` de validation, sans upgrade implicite (§8)
- [ ] trois états concordants + volumes préservés (§9)
- [ ] **verdict daté consigné** avant le site suivant (§6, §10)

### Clôture

- [ ] tous les critères §20.12 remplis (§10)
- [ ] nouveau vault sauvegardé (§3 à nouveau)
- [ ] `grav-sites-ops` autonome — aucune lecture de l'ancien dépôt (§10)
- [ ] rapport de migration complet (§10)
- [ ] ancien vault conservé ; nettoyage = décision humaine séparée (§11)
