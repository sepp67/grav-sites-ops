# Résultats de tests — `grav-sites-ops`

Résumé normatif : contrat architectural `v0.5.0`, section 18 (`docs/CONTRAT-ARCHITECTURAL.md`).
En cas de divergence, le contrat fait foi. Livré par le **lot L10**, complété
par le **lot L11** (acceptation — §5).

Ce document consigne des **exécutions réellement observées** (GSO-REQ-136,
GSO-REQ-147) : pour chaque test, la dernière exécution constatée, la commande,
le commit, l'environnement et le résultat. Il ne rapporte **aucune preuve
inventée**.

> **CI GitHub Actions — exécutée et comportement bloquant observé ; run
> global pas encore vert.** `main` = `d69a05a` a été **poussé** vers
> `sepp67/grav-sites-ops` le 2026-09-10 (autorisation humaine explicite,
> `push` en avance rapide, aucune réécriture). La CI distante a tourné —
> **run [`34513250088`](https://github.com/sepp67/grav-sites-ops/actions/runs/34513250088)** :
> - jobs métier **verts** (`role`, `translate`, `drift`, `functional-contract`) ;
> - job `static` **rouge** sur **une seule étape**, `L11 — gardes d'acceptation`,
>   à cause d'un **défaut du garde-fou** `tests/l11-acceptance-guards.sh`
>   (contrôle GSO-REQ-192 qui exigeait `main` non poussé) — corrigé depuis ;
> - job `conformance` (porte) **non exécuté**, **correctement bloqué** par
>   l'échec de `static` (0 s, sauté).
>
> **Le caractère bloquant de la CI est donc démontré en pratique**
> (GSO-REQ-145 / 147 / 187) : un échec réel a empêché la porte de conformité
> de passer. **Le run global n'est pas encore au vert** — il le sera au
> prochain `push` du correctif ; ce document ne prétend pas le contraire
> (voir §4). La CI reste non opérationnelle (aucun inventaire de production,
> aucun vault, aucune clé — GSO-REQ-030/046/058/139).

---

## 1. Environnement de référence

| Élément | Version observée |
|---|---|
| Station | Linux x86-64 (poste de construction local) |
| Python | 3.10.12 |
| `ansible-core` | 2.17.14 (borne CI `>=2.17,<2.19`) |
| `ansible-lint` | 26.4.0 |
| `yamllint` | 1.38.0 |
| Docker Engine | 29.1.3 (utilisé uniquement par `GSO-T15`, local) |
| Rôle | `sepp67.grav_site` `v2.0.0` (épinglé, `requirements.yml`) |
| Collection | `community.docker` 5.3.0 (`>=5.0.0,<6.0.0`) |
| Image de test | `ghcr.io/sepp67/grav-runtime:1.0.4` `@sha256:d130f333…` (locale, `GSO-T15`) |

---

## 2. Batterie reproductible — `make test-reproducible`

**Dernière exécution observée** — branche `correctif/ci-192-post-push` @
`3dd6cc2`, date 2026-09-10, environnement §1.
**Commande :** `make clean && make install-role && make test-reproducible`.
**Résultat global : 35 tests exécutés, 35 réussis, 0 échec**
(`GSO-T15` non inclus — voir §3 ; sortie du lanceur : `Total : 35   Reussis : 35   Echecs : 0`).
Stable : **35 / 35 sur 5 exécutions séquentielles** + **`GSO-T18` seul 30 / 30
séquentiels**, machine au repos (le harnais n'a **aucun mécanisme de
ré-essai**).

**Aléa `GSO-T18` « rollback non tracé » — cause racine établie et corrigée**
(commit `3dd6cc2`) : `common.sh` fait `set -o pipefail` ; le contrôle
`git log --oneline | grep -qi 'rollback grav-alpha'` était piégé — `grep -q`
trouve la 1ʳᵉ ligne et sort, `git log` (encore en écriture) reçoit SIGPIPE et
sort en 141, `pipefail` fait échouer le pipeline **alors que grep a trouvé la
ligne**, d'où un faux négatif intermittent. Corrigé sur `GSO-T17` / `GSO-T18`
par **capture + here-string** (jamais `git … | grep -q`) ; `commit_reg` durci
(échec immédiat si le commit du registre ne se matérialise pas exactement).

| Test | Scénario | Nature | Résultat |
|---|---|---|---|
| `GSO-T01` | syntaxe YAML / Ansible / inventaires (`ansible-playbook --syntax-check`, `yamllint`) | statique | OK |
| `GSO-T02` | `ansible-lint --offline` (profil `production` franchi) | statique | OK |
| `GSO-T03` | installation du rôle depuis `requirements.yml` (accès réseau) | structurel | OK |
| `GSO-T04` | référence du rôle épinglée sur un tag `v*` | statique | OK |
| `GSO-T05` | inventaire d'exemple parsable, `grav_servers` peuplé | statique | OK |
| `GSO-T06` | registre `grav_sites` chargé automatiquement, cohérence inventaire ↔ registre | statique | OK |
| `GSO-T07` | correspondance hôte ↔ registre ↔ vault d'exemple, `grav_secrets`, rejet de `src`, non-fuite | statique | OK |
| `GSO-T08` | sélecteur : refus sans inventaire imposé | garde-fou | OK |
| `GSO-T09` | sélecteur : refus sans `SITE` | garde-fou | OK |
| `GSO-T10` | sélecteur : refus `all` / groupe / motif / multiple / shell | garde-fou | OK |
| `GSO-T11` | sélecteur fermé : cible inconnue / vide → code ≠ 0, **sur le validateur** (GSO-REQ-056) | garde-fou | OK |
| `GSO-T12` | aucun contact distant après refus du préflight | garde-fou | OK |
| `GSO-T13` | traduction registre + `grav_secrets` → `grav_*` (**doublure de rôle**) | dynamique isolé | OK |
| `GSO-T14` | secrets du bon hôte uniquement, non-fuite, cohérence structurelle (GSO-REQ-204) | dynamique isolé | OK |
| `GSO-T16` | deux sites : isolation des variables et secrets à la traduction, **sans conteneur** | dynamique isolé | OK |
| `GSO-T17` | mise à jour A→B déclarative, quatre chemins persistants conservés (**doublure**) | dynamique isolé | OK |
| `GSO-T18` | rollback B→A explicitement déclaré, séquence A→B→A traçable (**doublure**) | dynamique isolé | OK |
| `GSO-T19` | contrôle des trois états + classification des 8 catégories de dérive (**fausse CLI docker**) | dynamique lecture seule | OK |
| `GSO-T20` | `check-all` non mutant, aucun `include_role`, cohérence déclarative sans VM (**fausse CLI docker**) | dynamique lecture seule | OK |
| `GSO-T21` | retrait déclaré sans tâche destructive, aucun appel d'hyperviseur, validateur read-only (**fixtures**) | dynamique + statique | OK |
| `GSO-T22` | registres actif / retiré disjoints, append-only inter-version (9 cas) (**fixtures**) | dynamique + statique | OK |
| `GSO-T23` | aucune dépendance au `control-repository` | statique | OK |
| `GSO-T24` | aucun chemin local, symlink externe ou secret suivi | statique | OK |
| `l4-concurrency-lock` | verrou `flock` par site : concurrent → code 75 sans rôle ; libéré après succès/échec (**doublure `ansible-playbook`**) | dynamique isolé | OK |
| `l4-ci-functional-contract` | la CI ne tire ni ne référence `GSO-T15` | statique | OK |
| `l5-restart-stop` | `restart`/`stop` : intention → `grav_state`, 1 invocation, refus, verrou partagé (**doublure**) | dynamique isolé | OK |
| `l5-action-closed` | intentions fermées, `grav_state` jamais fourni par l'opérateur, aucune orchestration destructive | statique | OK |
| `l7-persistence-guard` | aucune opération destructive de volume / répertoire, aucun rollback automatique, aucune voie CLI (GSO-REQ-102) | statique | OK |
| `l8-history-append-only` | append-only **inter-version** de `reactivated-sites.yml` sur l'historique Git ; refus d'un dépôt superficiel | dynamique + statique | OK |
| `l9-migration-doc-guard` | `docs/MIGRATION.md` complet, aucun outil de migration, cible synthétique conforme | statique + fixtures | OK |
| `l10-check-mode` | `deploy-site.yml --check` s'exécute mais **n'applique rien** ; docs n'assimilent pas `--check` à un déploiement (GSO-REQ-091) | dynamique isolé + statique | OK |
| `l10-multisite-isolation` | trois sites, A→B→A sans fuite d'état, `no_log` sous `-vv`, résolution par `inventory_hostname` (GSO-REQ-142) | dynamique isolé | OK |
| `l10-cleanup` | gardes statiques (trap, préfixe, aucun nettoyage non borné) + preuve dynamique zéro résidu (GSO-REQ-148/149) | dynamique + statique | OK |
| `l10-ci-blocking` | CI sans `continue-on-error`, porte de conformité, non opérationnelle, interpréteurs bornés, absence CI observée signalée | statique | OK |
| `l11-acceptance-guards` | premier commit sans capacité de déploiement, aucune automatisation push/tag/release, `ci.yml` sans déclencheur release, commandes documentées = cibles réelles, migration réelle bloquée, licence signalée (GSO-REQ-158/159/183..192/202) | statique | OK |

`make lint` (`yamllint --strict` + `ansible-lint --offline`) : **0 faute**,
22 fichiers traités sur 92 rencontrés, profil `production` franchi — même
commit, même environnement.

---

## 3. Test d'acceptation fonctionnel local — `GSO-T15`

**Non exécuté par la CI** (aucune image `grav-runtime` garantie sur un runner,
aucun identifiant GHCR — GSO-REQ-108). Test d'acceptation **local**.

**Dernière exécution observée** — commit `be9b3ad`, date 2026-09-10,
environnement §1 (Docker Engine 29.1.3, image `1.0.4` présente localement).
Réexécuté pour l'acceptation finale L11 (contrat §19.8 étape 2), même si le
chemin `deploy` est inchangé.
**Commande :** `make install-role && make test-functional`.
**Résultat : OK** — conteneur éphémère `gso-t15-6aa2e59710244825979`,
port `127.0.0.1:18715` ; `http://127.0.0.1:18715/admin` → 200 ; image déployée
par digest épinglé
`sha256:d130f333c6566a26856c271656b21ce2d06793f9c4af24e620b53da14e4d640f` ;
conteneur / réseau / verrou / répertoire temporaire supprimés en fin de test
(`aucun conteneur, réseau, journal, répertoire temporaire ou verrou résiduel`).

Contrôles vérifiés : `scripts/deploy.sh` rc=0 ; ordre sélecteur/verrou →
assertions → préflight structurel → rôle (positions croissantes dans le
journal) ; **1** `include_role` (47 tâches du rôle, `.deployed_state.yml`
écrit) ; **1** conteneur `gso-t15-*` `running + healthy` ; `http://127.0.0.1:<port>/admin`
→ 200 ; image déployée **par digest épinglé** ; aucune valeur synthétique
dans la sortie ; verrou libéré ; **aucun** conteneur / réseau / fichier
temporaire / verrou résiduel ; dossier runtime réel inchangé.

**Obligation de release :** `GSO-T15` **doit** être vert avant toute future
autorisation de release ; son résultat daté est consigné ici et dans le
rapport d'exécution du lot concerné.

---

## 4. Limitations connues

| Élément | Limitation | Suivi |
|---|---|---|
| CI GitHub Actions — run global | **run `34513250088` non vert** : une étape (`l11-acceptance-guards`, défaut du garde-fou GSO-REQ-192) a fait échouer `static` → porte `conformance` bloquée. **Aucun run global vert consigné à ce jour.** | correctif poussé → nouveau run attendu vert |
| `GSO-REQ-070` / `161` (sauvegarde vault avant migration) | preuve **documentaire** — le contrat les déclare non vérifiables par test automatisé | rapport d'opérateur daté lors d'une **migration réelle** autorisée (GSO-REQ-188) |
| `GSO-REQ-171` (verdict de migration par site) | aucun site réel migré → aucun verdict réel | migration réelle autorisée |
| `GSO-REQ-091` (`--check`) | comportement prouvé avec la **doublure** de rôle ; `--check` contre le **vrai** rôle non exercé | acceptable — `--check` n'est proposé que comme vérification complémentaire (contrat §13.8) |
| `GSO-REQ-158` (tag sur SHA CI-vert) | aucun tag ; le SHA **final de release** (postérieur à `d69a05a` : `LICENSE` + version + `CHANGELOG` daté) devra avoir un **run global CI au vert** | lot de préparation de release |
| `GSO-REQ-188` (migration réelle) | conformité du dépôt établie sur fixtures ; **aucune preuve propre à un site réel** | migration réelle — autorisation opérationnelle distincte |
| `GSO-REQ-192` (publication) | `main` = `d69a05a` **poussé** (2026-09-10, autorisation explicite, avance rapide, aucune réécriture) ; **l'autorisation humaine** est consignée dans le rapport d'exécution, pas prouvable par un test seul | tag + release = autorisation distincte |
| Fichier `LICENSE` | absent — `README.md` : « licence non fixée » (résidu L0) | **décision humaine** avant toute release publique |
| `docs/COMPLIANCE-MATRIX.md` | statut des 204 exigences au commit courant | distribution recalculée mécaniquement par `make matrix` — voir `docs/ACCEPTANCE.md` |

---

## 5. Acceptation L11 + correctif post-publication — verdicts séparés

Lot **L11** : revue d'acceptation locale (contrat §22, §19.8), acceptée et
intégrée à `main` = `d69a05a`. **Lot correctif** (post-`push`) : correction du
garde-fou GSO-REQ-192 et réconciliation documentaire après la première
exécution CI distante.

| Domaine | Verdict | Fondé sur |
|---|---|---|
| **Construction locale** | **ACCEPTED** | L0–L11 acceptés à `d69a05a` ; 24/24 tests normatifs verts, `GSO-T15` OK, `make lint` 0 faute, `make matrix-check` OK |
| **Publication** (`push` de `main`) | **effectuée** — CI distante à ramener au vert | `main` = `d69a05a` poussé (autorisation explicite, avance rapide) ; run `34513250088` **non vert** (défaut de garde-fou, corrigé) ; comportement bloquant **observé** |
| **Release** (tag + release) | **BLOCKED** | SHA **final de release** (postérieur, avec `LICENSE` + version + `CHANGELOG` daté) → **run CI global vert** (GSO-REQ-158) + autorisation de release distincte (GSO-REQ-192) |
| **Migration réelle** | **BLOCKED** | autorisation opérationnelle distincte (GSO-REQ-188) ; `inventories/production/` + vault opérationnel hors dépôt |

Détail exigence par exigence et conditions exactes : `docs/ACCEPTANCE.md`.
Les 13 exigences L11 : le `push` autorisé et la première exécution CI font
**évoluer** GSO-REQ-145 / 147 / 187 (preuve distante du blocage désormais
disponible) et GSO-REQ-192 (mécanique du `push` en avance rapide vérifiée ;
autorisation humaine consignée dans le rapport). **GSO-REQ-158** (tag sur SHA
CI-vert) et **GSO-REQ-188** (migration réelle) restent **non démontrées**.
Distribution recalculée mécaniquement — voir `docs/COMPLIANCE-MATRIX.md` §Synthèse.
