# Résultats de tests — `grav-sites-ops`

Résumé normatif : contrat architectural `v0.5.0`, section 18 (`docs/CONTRAT-ARCHITECTURAL.md`).
En cas de divergence, le contrat fait foi. Livré par le **lot L10**.

Ce document consigne des **exécutions réellement observées** (GSO-REQ-136,
GSO-REQ-147) : pour chaque test, la dernière exécution constatée, la commande,
le commit, l'environnement et le résultat. Il ne rapporte **aucune preuve
inventée**.

> **CI GitHub Actions — non observée.** `.github/workflows/ci.yml` est validé
> **statiquement et localement** (`tests/l10-ci-blocking.sh`, `yamllint`,
> `GSO-T01`). Le dépôt distant n'existe pas encore et **aucun `push` n'a été
> effectué** : la CI distante **n'a donc jamais été exécutée** et son
> caractère bloquant **n'est pas observé en pratique** (GSO-REQ-147). Sa
> configuration est conçue pour être bloquante (job `conformance` dépendant de
> tous les jobs, aucun `continue-on-error`) et non opérationnelle (aucun
> inventaire de production, aucun vault, aucune clé — GSO-REQ-030/046/058/139).

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
| Collection | `community.docker` 5.2.2 (`>=5.0.0,<6.0.0`) |
| Image de test | `ghcr.io/sepp67/grav-runtime:1.0.4` `@sha256:d130f333…` (locale, `GSO-T15`) |

---

## 2. Batterie reproductible — `make test-reproducible`

**Dernière exécution observée** — commit `RESULTS_COMMIT`, date `RESULTS_DATE`,
environnement §1.
**Commande :** `make clean && make install-role && make test-reproducible`.
**Résultat global : `RESULTS_REPRO`.**

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

`make lint` (`yamllint --strict` + `ansible-lint --offline`) : **0 faute**,
21 fichiers, profil `production` franchi — même commit, même environnement.

---

## 3. Test d'acceptation fonctionnel local — `GSO-T15`

**Non exécuté par la CI** (aucune image `grav-runtime` garantie sur un runner,
aucun identifiant GHCR — GSO-REQ-108). Test d'acceptation **local**.

**Dernière exécution observée** — commit `RESULTS_COMMIT`, date `RESULTS_DATE`,
environnement §1 (Docker Engine 29.1.3, image `1.0.4` présente localement).
**Commande :** `make install-role && make test-functional`.
**Résultat : `RESULTS_T15`.**

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
| CI GitHub Actions | **jamais exécutée à distance** (aucun `push`) — bloquant/non bloquant non observé en pratique | L11 (gate release) — après création du dépôt distant, autorisation de publication distincte |
| `GSO-REQ-070` / `161` (sauvegarde vault avant migration) | preuve **documentaire** — le contrat les déclare non vérifiables par test automatisé | rapport d'opérateur daté lors d'une **migration réelle** autorisée (GSO-REQ-188) |
| `GSO-REQ-171` (verdict de migration par site) | aucun site réel migré → aucun verdict réel | migration réelle autorisée |
| `GSO-REQ-091` (`--check`) | comportement prouvé avec la **doublure** de rôle ; `--check` contre le **vrai** rôle non exercé | acceptable — `--check` n'est proposé que comme vérification complémentaire (contrat §13.8) |
| `docs/COMPLIANCE-MATRIX.md` | statut des 204 exigences au commit courant | mis à jour à chaque lot ; gate d'acceptation §22 = L11 |
