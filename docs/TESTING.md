# Tests

Deux catégories, volontairement distinctes.

## 1. Batterie reproductible (CI + local)

Entièrement déterministe : aucune image, aucun conteneur, aucune connexion,
aucun identifiant. Exécutée par la CI (`.github/workflows/ci.yml`) et par
`make test-reproducible`.

| Test | Objet |
|---|---|
| `GSO-T01` | syntaxe YAML / Ansible / inventaires |
| `GSO-T02` | `ansible-lint` |
| `GSO-T03` | installation du rôle depuis `requirements.yml` |
| `GSO-T04` | référence du rôle épinglée sur un tag |
| `GSO-T05` | inventaire d'exemple parsable |
| `GSO-T06` | registre chargé automatiquement |
| `GSO-T07` | correspondance hôte–registre–vault d'exemple |
| `GSO-T08`–`T12` | sélecteur fermé + préflight (lecture seule) |
| `GSO-T13` | traduction registre + `grav_secrets` → `grav_*` (**doublure de rôle**) |
| `GSO-T14` | isolation des secrets, non-fuite, GSO-REQ-204 (**doublure**) |
| `GSO-T16` | deux sites : isolation à la traduction, **sans conteneur** (**doublure**) |
| `GSO-T23`, `GSO-T24` | contrôles statiques (control-repository, chemins, secrets) |
| `l4-concurrency-lock` | verrou de concurrence (**doublure de `ansible-playbook`**) |
| `l4-ci-functional-contract` | garde-fou : la CI ne tire ni ne référence `GSO-T15` |
| `l5-restart-stop` | `restart` / `stop` : intention → `grav_state`, 1 invocation, refus, verrou partagé, propagation des codes (**doublure de rôle**) |
| `l5-action-closed` | garde-fou statique : intentions fermées, `grav_state` jamais fourni par l'opérateur, aucune orchestration destructive, aucun nouvel identifiant GSO-T |

Toutes les preuves L4–L5 « logiques » (traduction exacte, `name`+`content` sans
`src`, tri-state, une seule invocation, second contrôle de cible, non-fuite,
verrou partagé, `restart`/`stop` fermés) sont dans cette catégorie.

Les preuves L5 n'ont **pas** d'identifiant `GSO-Txx` : le préflight de
construction ne prévoit **aucun** scénario `GSO-T` dédié à L5. Elles sont
tracées comme preuves L5 non numérotées (`tests/l5-*.sh`).

## 2. Test d'acceptation fonctionnel local — `GSO-T15`

`GSO-T15` exécute le **vrai** chemin opérateur (`scripts/deploy.sh` →
`scripts/lib/site-mutation.sh` → sélecteur → verrou → `deploy-site.yml` →
`_shared/mutate.yml` : assertions → second préflight structurel → traduction
fermée → vrai rôle `sepp67.grav_site v2.0.0`) et crée **un** conteneur
`grav-runtime` **éphémère**, puis le détruit. `restart` et `stop` partagent ce
chemin ; L5 ne les exécute **jamais** sur un vrai conteneur.

**Non exécuté par la CI standard** : il exige une image déjà présente
localement, sans pull implicite ni identifiant GHCR (GSO-REQ-108).

### Lancement

```bash
make test-functional              # GSO-T15 seul
make test                         # batterie reproductible + GSO-T15 (gate locale complète)
bash tests/run-all.sh --functional
```

### Préconditions (sinon : ÉCHEC — jamais un SKIP, jamais un succès)

| Précondition | Vérification |
|---|---|
| Docker Engine + plugin `compose` opérationnels | `docker version`, `docker compose version` |
| Rôle `sepp67.grav_site` installé (`v2.0.0`) | `make install-role` |
| Collection `community.docker` installée (`>=5.0.0,<6.0.0`) | `make install-role` |
| Image de test **déjà présente localement** | `docker image inspect ghcr.io/sepp67/grav-runtime:1.0.4` |

### Image de test

- Référence : `ghcr.io/sepp67/grav-runtime` version `1.0.4`
- **Digest exact** :
  `sha256:d130f333c6566a26856c271656b21ce2d06793f9c4af24e620b53da14e4d640f`
- Déterminée par les sources approuvées : `ansible-role-grav-site`
  (`molecule/deploy`, `molecule/multi_instance`).
- `GSO-T15` déploie **par digest** (`image@sha256:…`) avec `grav_force_pull:
  false` → aucun pull si l'image est présente.
- Si l'image manque : la tirer **manuellement** et **par une référence
  nommée / épinglée par digest**, jamais `latest`. Aucune commande du dépôt ne
  tire d'image.

### Garanties du test

localhost + `ansible_connection=local` uniquement ; données, identifiants et
secrets synthétiques ; noms préfixés `gso-t15-` + suffixe unique ; publication
HTTP sur `127.0.0.1` + port de test sans collision ; répertoire `mktemp -d` ;
nettoyage en succès **comme en échec**, borné aux seules ressources créées ;
jamais de `docker … prune` ; vérification finale d'absence de conteneur,
réseau, fichier temporaire ou verrou résiduel.

### Obligation de release

`GSO-T15` **doit** être exécuté et vert avant toute future autorisation de
release (préparation de tag). Son résultat daté est consigné dans le rapport
d'exécution du lot concerné (et, à partir du lot L10, dans
`docs/TEST-RESULTS.md`).
