# Changelog

Toutes les évolutions notables de **`grav-sites-ops` en tant qu'orchestrateur**
sont consignées ici. Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/)
et le versionnement sémantique.

> `CHANGELOG.md` trace les versions **du dépôt d'orchestration**. Il n'est pas
> une source de vérité des versions applicatives actives du parc : celles-ci
> vivent uniquement dans le registre `grav_sites` (GSO-REQ-157). La version du
> rôle consommé est déclarée uniquement dans `requirements.yml` (GSO-REQ-153).

## [Non publié]

## [1.0.0] - 2026-09-11

### Ajouté — première release (licence, version, préparation du tag)

Décisions humaines actées le 2026-09-11 : licence **AGPL-3.0-or-later**,
première version **`1.0.0`**. Préparé sur la branche dédiée `release/1.0.0`,
créée depuis `main` = `b2e97f2`. **Tag prévu `v1.0.0` — non créé** : le tag et
la publication de la release GitHub restent des autorisations distinctes,
postérieures à l'intégration de ce commit dans `main`, à son `push` et à un
run CI global vert **sur ce SHA précis**.

- **`LICENSE`** : texte **officiel et intégral, non modifié**, de la GNU
  Affero General Public License v3 (source canonique
  <https://www.gnu.org/licenses/agpl-3.0.txt>), `sha256:0d96a4ff68ad6d4b6f1f30f713b18d5184912ba8dd389f86aa7710db079abcb0`,
  recoupé avec la copie SPDX `license-list-data` (identique mot pour mot, à
  l'exception du schéma http/https dans 3 URL de la FSF).
- **`README.md`** : `SPDX-License-Identifier: AGPL-3.0-or-later` et
  `Copyright © 2026 Sébastien Clem` dans la section « Licence » (jamais dans
  le corps du texte officiel de `LICENSE`) ; version du dépôt `1.0.0`
  affichée en « Statut » ; état réconcilié avec `main` = `b2e97f2` et le run
  CI global vert.
- **`tests/l11-acceptance-guards.sh`** (§7, étendu — **aucun nouvel
  identifiant `GSO-T`**) : garde-fou statique de licence — `LICENSE` comparé
  par **hash SHA-256** au texte officiel (toute altération, même d'un octet,
  est refusée) ; `SPDX-License-Identifier` et mention de copyright vérifiés
  dans `README.md` ; cas négatif synthétique (texte altéré, jamais le fichier
  réel) prouvant que le hash détecte bien une divergence.
- **Run CI vert consigné** :
  [`34591427344`](https://github.com/sepp67/grav-sites-ops/actions/runs/34591427344)
  sur `main` = `b2e97f2` (2026-09-11) — **premier run global entièrement
  vert** du dépôt, porte `conformance` incluse. Voir `docs/TEST-RESULTS.md`.
- `docs/ACCEPTANCE.md`, `docs/TEST-RESULTS.md`, `docs/COMPLIANCE-MATRIX.md` :
  réconciliés — licence et version décidées, run global vert consigné,
  préparation documentaire du tag `v1.0.0`.

**Le contrat architectural reste en version `v0.5.0`** : `1.0.0` est la
version du **dépôt et de sa première release**, pas du contrat
(`docs/VERSIONING.md`). **Non fait / non autorisé à ce stade :** intégration
dans `main`, `push`, tag, release GitHub, mise à niveau des actions GitHub,
migration réelle.

### Corrigé — hygiène SIGPIPE généralisée (13 fichiers + GSO-T15)

Suite du correctif GSO-REQ-192 : le même motif `producteur | grep -q` sous
`set -o pipefail` (risque de faux négatif — ou, sur un garde-fou négatif, de
**faux succès** — si l'élément recherché est réellement présent) fermé sur
**13 fichiers `tests/*.sh`** puis, après classification explicite des 4
occurrences restantes, sur **`tests/gso-t15-real-deploy.sh`** — validé par
une exécution Docker réelle sans résidu. Détail complet : cause racine,
méthode, cas négatifs, gate exécuté →
`audit-grav-sites-ops/21-rapport-correctif-ci-192.md` §12–§17. Ces deux
commits ont ensuite été intégrés (avance rapide) dans `main` et **poussés**
(`b2e97f2`), produisant le premier run CI global vert du dépôt.

### Corrigé — lot correctif post-publication (premier `push` de `main`)

`main` = `d69a05a` a été **poussé** vers `sepp67/grav-sites-ops` le
2026-09-10 (autorisation humaine explicite ; `push` en avance rapide, aucune
réécriture). La CI GitHub Actions a tourné pour la première fois — run
[`34513250088`](https://github.com/sepp67/grav-sites-ops/actions/runs/34513250088) :
jobs métier verts, **une** étape rouge (`l11-acceptance-guards`), porte
`conformance` **correctement bloquée**.

- **`tests/l11-acceptance-guards.sh`** — le contrôle GSO-REQ-192 exigeait
  `main` **strictement en avance** sur `origin/main` (« jamais poussé »), ce
  qui est une **mauvaise interprétation** : GSO-REQ-192 exige un `push`
  **autorisé et vérifié**, pas absent. Le contrôle raisonne désormais sur
  `HEAD` (checkout détaché de GitHub Actions), vérifie une **relation en
  avance rapide** (`origin/main` ancêtre de `HEAD`, aucune divergence,
  `left = 0`) et l'**absence d'automatisation** `push` / `tag` / `release`.
  L'autorisation **humaine** du `push` relève du rapport d'exécution, pas du
  test.
- **`tests/l10-ci-blocking.sh`** (GSO-REQ-147) — accepte désormais deux états
  honnêtes : « CI distante non observée » **ou** « CI observée : run <id> » ;
  **refuse** toute surqualification (« CI complète verte » / « CI conforme »)
  tant qu'aucun run global vert n'est consigné.
- **`docs/TEST-RESULTS.md`**, **`docs/ACCEPTANCE.md`**, **`README.md`** —
  réconciliés avec la réalité : `push` effectué, CI **exécutée et
  comportement bloquant observé**, run global **pas encore vert**.
- **`docs/COMPLIANCE-MATRIX.md`** (régénérée, distribution **recalculée
  mécaniquement**) : GSO-REQ-145 / 147 / 187 citent la **preuve distante du
  blocage** (run `34513250088`) ; **GSO-REQ-192** passe de *non démontré* à
  *établi / documenté* (mécanique testée ; autorisation humaine consignée au
  rapport). Nouvelle synthèse : **138 T / 15 S / 47 D / 2 P / 2 N** — les 2
  *non démontrées* restantes sont **GSO-REQ-158** (tag sur SHA à CI verte) et
  **GSO-REQ-188** (migration réelle).

**Non fait / non autorisé :** aucun `git push` de ce correctif (autorisation
distincte) ; aucun tag, aucune release ; aucune mise à niveau des actions
GitHub (`checkout@v4`, `setup-python@v5`) — commit séparé si nécessaire après
retour au vert. Aucun nouvel identifiant `GSO-T`.

### Ajouté — lot L11 (acceptation : revue §22, verdicts séparés)

- `docs/ACCEPTANCE.md` : revue des critères d'acceptation du contrat (§22),
  **consommation** de la matrice 204/204, évaluation **exigence par exigence**
  des 13 exigences L11 (GSO-REQ-158, 159, 183, 184, 185, 186, 187, 188, 189,
  190, 191, 192, 202), préparation **documentaire** d'une release (§19.8 —
  **aucune étape franchie**), et **quatre verdicts séparés** :
  - **construction locale** : `ACCEPTED` ;
  - **publication** (`push` de `main`) : `BLOCKED` — `main` jamais poussé ;
  - **release** (tag) : `BLOCKED` — CI distante verte + `LICENSE` + version ;
  - **migration réelle** : `BLOCKED` — autorisation opérationnelle distincte.
- `tests/l11-acceptance-guards.sh` (job `static`) : rend re-vérifiables les
  constats — premier commit sans capacité de déploiement (GSO-REQ-185), aucune
  automatisation `git push` / `git tag` / `gh release` (GSO-REQ-159/192),
  `ci.yml` sans déclencheur `release`/`tag`, 21 cibles `make` documentées =
  21 réelles (GSO-REQ-189), matrice 204/204 (GSO-REQ-190), migration réelle
  maintenue `BLOCKED` (GSO-REQ-188), licence signalée comme décision humaine.
- `docs/COMPLIANCE-MATRIX.md` : les 13 exigences L11 passent de « non
  démontré » à **10 « établi / documenté »** (revue L11) + **3 « non
  démontré »** (GSO-REQ-158/188/192, bloquées par un `push`, une CI distante
  ou une migration réelle non autorisés). **201 / 204** adressées.
- `docs/TEST-RESULTS.md` : §5 « Acceptation L11 » ; `GSO-T15` **réexécuté**
  pour l'acceptation finale.
- `README.md` : lot L11 ; état d'acceptation ; licence signalée bloquante.
- `.github/workflows/ci.yml` : étape `l11-acceptance-guards` dans `static`.

### Corrigé — lot L11 (robustesse du harnais)

- `l9-migration-doc-guard`, `l8-history-append-only` : suppression des
  contrôles absolus `git status --porcelain` (échouaient dès qu'un fichier
  suivi **sans rapport** était modifié dans le working tree) → comparaison
  **avant / après** : le test ne doit rien modifier de suivi.
- `l10-cleanup` : journal de l'échantillon dynamique écrit hors du dépôt
  (n'était plus vu par `git status` le temps de l'exécution).

Aucun `push`, tag, release, migration réelle, dépôt distant, vault ou
inventaire opérationnel. Aucun nouvel identifiant `GSO-T`.

### Ajouté — lot L10 (consolidation : CI bloquante, résultats, matrice)

- `docs/TEST-RESULTS.md` (GSO-REQ-136/147) : **exécutions réellement observées**
  — pour chaque test, la dernière exécution, la commande, le commit,
  l'environnement, le résultat. Signale **explicitement** que la CI GitHub
  Actions n'a **jamais été exécutée à distance** (aucun `push`) : son
  caractère bloquant n'est pas observé en pratique.
- `docs/COMPLIANCE-MATRIX.md` (GSO-REQ-150) : les **204 exigences `GSO-REQ`**,
  chacune avec lot porteur, intitulé, preuve principale (nommée) et statut
  parmi **satisfait et testé / satisfait / établi-documenté / partiel / non
  encore démontré**. Régénérée par `make matrix`, vérifiée par
  `make matrix-check` (`scripts/lib/gso_compliance.py`, read-only). État :
  191/204 adressées par L0–L10, 13 (L11) non démontrées.
- `.github/workflows/ci.yml` : job **`conformance`** (`needs:` tous les autres
  jobs — GSO-REQ-145) ; `ansible-core` borné `>=2.17,<2.19` (GSO-REQ-146) ;
  étapes L10.
- `tests/l10-check-mode.sh` (GSO-REQ-091) : `deploy-site.yml --check`
  s'exécute (assertions + préflight) mais **n'applique rien** (la doublure ne
  produit aucun artefact) ; aucun document opérateur ne présente `--check`
  comme un déploiement. `docs/OPERATIONS.md` : section « Mode `--check` ».
- `tests/l10-multisite-isolation.sh` (GSO-REQ-142, porteur L10) : trois sites,
  déploiements entrelacés A→B→A sans fuite d'état, indépendance par hôte,
  `no_log` sous `-vv`, résolution **exclusivement** par `inventory_hostname`.
- `tests/l10-cleanup.sh` (GSO-REQ-148/149) : gardes statiques (`trap`,
  préfixe reconnaissable, aucun nettoyage non borné) + preuve dynamique
  (échantillon représentatif → zéro conteneur / réseau / verrou / temporaire
  résiduel).
- `tests/l10-ci-blocking.sh` (GSO-REQ-030/046/058/074/139/145/146/147/150) :
  aucun `continue-on-error`, porte de conformité, CI sans inventaire de
  production ni vault ni clé SSH, interpréteurs bornés, matrice 204/204.
- `Makefile` : `make matrix`, `make matrix-check`.
- Harmonisation : `gso-t03..t09` passent de `mktemp -d` nu à `gso_mktemp_dir`
  (préfixe reconnaissable). `run-all.sh` ramasse aussi `l10-*.sh`.

Aucun nouvel identifiant `GSO-T` (préflight §6 : L10 = consolidation, aucun
`GSO-T` supplémentaire). Preuves L10 non numérotées (`tests/l10-*.sh`).

### Ajouté — lot L9 (migration documentaire depuis l'ancien profil)

- `docs/MIGRATION.md` : procédure **manuelle**, **site par site** (GSO-REQ-167),
  depuis l'ancien profil `ansible-role-grav-site`
  (`inventories/production/group_vars/grav_servers/`) vers le schéma de
  `grav-sites-ops`. Couvre : précondition harnais vert (GSO-REQ-163) ;
  diagnostic de l'existant sans divulgation (GSO-REQ-162) ; **sauvegarde
  externe vérifiée du vault avant toute transformation** (GSO-REQ-070/160/161,
  contrat §20.3 — chemin hors dépôt, permissions restrictives, somme de
  contrôle avant/après, `ansible-vault view` sans afficher, conservation
  séparée, exclusion Git, arrêt si échec) ; **cartographie explicite** de
  chaque champ ancien → nouveau, indirections `{{ vault_* }}` résolues, secrets
  au format `name` + `content` (GSO-REQ-133/164) ; **champ non mappé →
  décision humaine documentée** ; protection des **six chemins structurants** ;
  création + vérification du nouveau vault sans export en clair (GSO-REQ-165/166) ;
  déploiement de validation **sans upgrade implicite** (GSO-REQ-168) ; critères
  de fin + **autonomie finale** — aucune lecture de l'ancien dépôt
  (GSO-REQ-170) ; rapport avec **un verdict daté par site** (GSO-REQ-171) ;
  **retour arrière organisationnel** distinct du rollback d'image L7,
  non destructif, sans script (GSO-REQ-172) ; ancien vault conservé, nettoyage
  = décision humaine séparée (GSO-REQ-169).
- **Aucun** playbook, script ou cible `make` de migration : l'exécution réelle
  est une décision humaine distincte de la construction (GSO-REQ-188).
- `tests/l9-migration-doc-guard.sh` (preuve **non numérotée** — le préflight
  n'attribue aucun `GSO-T` à L9) : vérifie la présence de **toutes** les
  étapes obligatoires dans `MIGRATION.md`, l'interdiction d'une migration
  globale, l'absence d'outil de migration, l'absence de lecture de l'ancien
  dépôt local (GSO-REQ-170), l'absence de recopie d'artefact du rôle
  (GSO-REQ-133) ; **réutilise `gso_validate.py registry` / `vault`** sur des
  fixtures synthétiques ancien → nouveau pour prouver que la **cible** de
  migration est conforme au contrat.
- `tests/fixtures/l9-old-profile/` (forme plate `grav_*`, avec un champ non
  mappé de démonstration) et `tests/fixtures/l9-migrated/` (registre indexé
  par `inventory_hostname`) — **entièrement synthétiques**.
- `.github/workflows/ci.yml` : job `static` étendu à `l9-migration-doc-guard`.

L9 **ne migre aucun site réel**, ne lit ni ne copie aucun vault opérationnel,
ne crée aucun inventaire de production, ne se connecte à aucune VM.

### Ajouté — lot L8 (cycle de vie documentaire : retrait, réactivation)

- `registry/retired-sites.yml` (racine `retired_grav_sites`) et
  `registry/reactivated-sites.yml` (racine `reactivated_sites`, historique
  **append-only**, chaque clé → liste d'événements) : fichiers
  **documentaires**, suivis par Git, **hors de `group_vars/`**, **jamais**
  chargés automatiquement par Ansible, **jamais** une source de déploiement,
  **sans secret** (contrat §7.7 ; GSO-REQ-028).
- `scripts/lib/gso_lifecycle.py` : validateur **strictement en lecture seule**
  (aucune écriture, aucun sous-processus, aucun `git`). Importe les primitives
  de `gso_validate.py` **sans le modifier** (chemin `deploy` intact). Vérifie :
  racines exactes, schéma fermé des fiches, dates ISO, absence de champ
  `status` sur une fiche retirée (§21.9), ordre chronologique dans l'état
  courant, et — quand un registre / vault est fourni — la **disjonction
  stricte** `grav_sites` ∩ `retired_grav_sites` = ∅ (GSO-REQ-052),
  `vault_grav_sites` ∩ `vault_retired_grav_sites` = ∅, secrets d'un projet
  retiré hors de `vault_grav_sites` (GSO-REQ-073), et qu'aucune clé réactivée
  ne subsiste dans `retired_grav_sites` (GSO-REQ-181).
- **Preuve append-only INTER-VERSION** (GSO-REQ-181) : `gso_lifecycle.py
  --history-before <ancienne> --reactivated <nouvelle>` impose que l'ancien
  historique de chaque clé soit un **préfixe exact** du nouveau (aucune
  suppression / modification / réécriture / insertion rétroactive ; seuls des
  ajouts en fin de liste et de nouvelles clés). `scripts/lifecycle-history-check.sh`
  — **seul** endroit qui touche à Git — parcourt les versions successives de
  `registry/reactivated-sites.yml` et vérifie **chaque transition** ; un
  dépôt Git **superficiel** le fait échouer explicitement (jamais un faux
  succès) ; le commit initial est exempté. Aucune écriture.
- `Makefile` : cible `make lint-lifecycle` (état courant **+** append-only
  inter-version sur tout l'historique).
- `docs/LIFECYCLE-SCHEMA.md` : schéma normatif des deux registres + règles de
  disjonction. `docs/OPERATIONS.md` : procédures **Git manuelles** de retrait
  (contrat §21.6) et de réactivation (§21.8), et ce que L8 ne fait jamais.
- Tests (fixtures synthétiques, sans Docker / réseau / connexion) :
  `tests/gso-t21-retrait-non-destructif.sh`, `tests/gso-t22-disjonction-registres.sh`
  (dont **9 cas append-only inter-version** : inchangé / ajout en fin /
  nouvelle clé acceptés ; suppression / modification / inversion / insertion /
  clé supprimée / remplacement refusés), `tests/l8-history-append-only.sh`
  (parcours de l'historique Git réel + refus d'un dépôt superficiel).
- `.github/workflows/ci.yml` : job `static` — `fetch-depth: 0`, étendu à
  `GSO-T21`, `GSO-T22`, `l8-history-append-only` et `make lint-lifecycle`.
- `tests/fixtures/l8-lifecycle-ok/` : arborescence synthétique (2 actifs,
  2 retirés, 2 réactivations) — jamais une donnée réelle.

L8 **ne crée aucun playbook**, aucun script mutant, aucune cible `make` de
transformation, aucun mécanisme de commit Git automatisé, aucune purge, aucune
suppression de donnée persistante ou de VM. Le retrait et la réactivation
restent des opérations **Git manuelles** vérifiées **après coup**.

### Ajouté — lot L7 (mise à jour, rollback, persistance)

- **Aucun** nouveau playbook, wrapper, cible Makefile ou intention
  `_gso_intent` : la mise à jour et le rollback sont **deux usages
  déclaratifs de `deploy-site.yml`** (contrat §13.1 — interface fermée ;
  §15.1 / §15.4). Le chemin `deploy` de L4 est **byte-identique**.
- `docs/OPERATIONS.md` : procédures normatives de mise à jour et de rollback
  (modifier le registre → diff Git → commit → `make check` → `make deploy` →
  `make check`) ; distinction **image ≠ contenu** (verbatim contrat §15.5) ;
  section persistance (GSO-REQ-040/075-079/113/176).
- `tests/l7-persistence-guard.sh` (statique, exécuté par la CI —
  GSO-REQ-102) : recherche dans les fichiers d'**exécution** (playbooks,
  scripts, Makefile, commentaires retirés) toute opération interdite —
  `docker compose down --volumes`, `docker volume rm` / `prune`, `rm -rf`
  d'un chemin persistant, `state: absent`, `rsync` / restauration de
  contenu, bloc `rescue`/`always` (rollback automatique — GSO-REQ-114),
  écriture de `.deployed_state.yml` / `.deployed_version` /
  `deployed_versions.log` (GSO-REQ-117), voie `-e` / `--extra-vars` /
  `--version` / `--digest` / `--image` (GSO-REQ-109), et tout fichier ou
  cible `update*` / `rollback*`.
- Tests (doublure du rôle, fixtures synthétiques, dépôt Git jetable, 100 %
  reproductibles — **aucun conteneur réel**) :
  - `tests/gso-t17-update-a-to-b.sh` : déclaration A puis B committées ;
    `deploy-site.yml` transmet **exactement** l'image / version / digest de
    B ; aucune valeur héritée de A ; digest transmis tel quel, jamais de
    référence hybride (GSO-REQ-110) ; `grav_base_directory` /
    `grav_container_name` et toutes les variables structurantes inchangées
    (seule la dimension image bouge — GSO-REQ-076) ; aucune surcharge CLI
    acceptée ; aucune opération destructive ; isolation du site non ciblé.
  - `tests/gso-t18-rollback-b-to-a.sh` : séquence observée **A → B → A**
    (puis A2) ; chaque passage transmet la référence **déclarée et
    committée** (jamais l'avant-dernière image, jamais un tag flottant) ;
    le rollback est une re-déclaration Git explicite (GSO-REQ-112) ; trois
    traces d'application distinctes conservées, aucune effacée ni réécrite ;
    rollback vers le **même digest** à version humaine différente resté
    explicite ; chemins persistants conservés ; aucune restauration de
    contenu (GSO-REQ-113) ; même sélecteur / verrou que `deploy` ;
    propagation d'erreur ; aucune modification automatique du registre
    (GSO-REQ-109/126).
- `.github/workflows/ci.yml` : `l7-persistence-guard` dans le job `static` ;
  `GSO-T17` / `GSO-T18` dans le job `translate` (doublure, reproductible).

### Ajouté — lot L6 (contrôle de dérive, lecture seule)

- `playbooks/check-site.yml` + `playbooks/check-all.yml` + séquence commune
  `playbooks/_shared/observe.yml` : comparaison des **trois niveaux d'état**
  (désiré / appliqué / réel) et **classification** de la dérive
  (GSO-REQ-118). **Strictement non mutant** : `gather_facts: false`
  (GSO-REQ-124), aucun `include_role`/`import_role` de `sepp67.grav_site`,
  collecte en lecture seule uniquement — `slurp` de `.deployed_state.yml`
  (jamais modifié — GSO-REQ-119), `docker inspect`, `uri` GET, `stat` de
  `.last_failure.log` (présence + horodatage, **jamais** le contenu —
  GSO-REQ-123). Aucune remédiation automatique, aucun appel à
  `deploy-site.yml` (GSO-REQ-090/122).
- `scripts/lib/gso_classify.py` : classificateur **pur** des 8 catégories du
  contrat §16.5 (`IN_SYNC`, `NOT_DEPLOYED`, `REFERENCE_DRIFT`, `CONFIG_DRIFT`,
  `STOPPED`, `UNHEALTHY`, `UNREACHABLE`, `UNKNOWN`). `STOPPED` est relatif à
  l'état **désiré** : `stopped` voulu + conteneur arrêté ⇒ `IN_SYNC`
  (GSO-REQ-121). Code de sortie toujours 0 (c'est le playbook qui décide).
- `scripts/lib/site-check.sh` + `scripts/check-site.sh` + `scripts/check-all.sh` :
  chemin opérateur de contrôle **sans verrou de mutation** (un contrôle ne
  bloque jamais un déploiement) ; `check-site` valide `SITE` par le sélecteur
  fermé L3 ; `check-all` vérifie d'abord la **cohérence déclarative** du parc
  **sans VM** (GSO-REQ-125). Aucune bascule possible vers une mutation
  (GSO-REQ-104).
- `Makefile` : cibles `make check SITE=` / `make check-all`.
- Tests (fausse CLI `docker` en lecture seule, 100 % reproductibles) :
  `tests/gso-t19-drift-classification.sh` (les 8 catégories ; trois niveaux
  distingués ; conteneur arrêté → `STOPPED` ; `stopped` désiré → jamais
  `STOPPED` ; fichier illisible / docker indisponible → `UNKNOWN` ; VM
  simulée injoignable → `UNREACHABLE` ; `.deployed_state.yml` inchangé ;
  aucune sous-commande `docker` mutante ; rôle jamais invoqué ; non-fuite ;
  codes stables), `tests/gso-t20-check-all-non-mutating.sh` (gardes statiques
  `check-site.yml`/`check-all.yml` sans `include_role` ; parcours du parc ;
  registre incohérent → échec avant parcours, sans VM ; verdict de parc ;
  non-mutation).
- `.github/workflows/ci.yml` : job `drift` (GSO-T19 + GSO-T20, fausse CLI
  `docker`, 100 % reproductible).
- Doublure de tests : helper `gso_fake_docker_into` (fausse CLI `docker`
  lecture seule qui **refuse** toute sous-commande mutante).

Codes de sortie du contrôle : le contrat (GSO-REQ-093) impose « code non nul
si l'intention n'est pas atteinte » sans taxonomie numérique ; convention
retenue **`0` = `IN_SYNC`**, `≠ 0` sinon, la **catégorie §16.5** (sans secret)
portant la distinction fine.

### Ajouté — lot L5 (redémarrage et arrêt d'un site)

- `playbooks/restart-site.yml` + `playbooks/stop-site.yml` : plays fins qui
  fixent `_gso_intent` (`restart` / `stop`) puis empruntent la séquence
  commune `playbooks/_shared/mutate.yml` (assertions `--limit` → préflight
  structurel → traduction fermée → **une seule** invocation de
  `sepp67.grav_site`). Chaque intention a un playbook **dédié**
  (GSO-REQ-081/082/087/088/089).
- `playbooks/_shared/translate.yml` : `grav_state` **dérivé de la seule
  intention** — `restart` → `restarted`, `stop` → `stopped`, `deploy` → état
  du registre ; `_gso_intent` contraint à `{deploy, restart, stop}` par
  assertion. L'opérateur ne fournit **jamais** `grav_state`.
- `scripts/lib/site-mutation.sh` : chemin opérateur partagé (playbook validé
  contre une liste fermée → sélecteur `validate-target.sh` → **verrou `flock`
  par site, identique à `deploy`** → `ansible-playbook --limit`). Codes du
  sélecteur / verrou (75) / playbook / rôle propagés sans masquage.
- `scripts/restart-site.sh`, `scripts/stop-site.sh` : wrappers fins n'acceptant
  que `SITE`. `scripts/deploy.sh` réécrit sur le même chemin partagé.
- `Makefile` : cibles `make restart SITE=` / `make stop SITE=`.
- Tests (doublure de rôle, 100 % reproductibles, **aucun conteneur**) :
  `tests/l5-restart-stop.sh` (intention → `grav_state`, 1 invocation, `restart`
  n'altère ni version ni digest, `stop` sans orchestration destructive, refus
  sans/avec argument surnuméraire/cible invalide/absente/retirée/incohérente
  sans invocation du rôle, verrou partagé, échec concurrent code 75,
  libération du verrou après succès et échec, non-fuite de secret, fixtures
  inchangées), `tests/l5-action-closed.sh` (garde-fou statique des intentions
  fermées). Preuves L5 **non numérotées** — le préflight ne prévoit aucun
  `GSO-Txx` dédié à L5.
- CI : job `translate` étendu à `l5-restart-stop` et `l5-action-closed`.

`restart` n'est **pas** un redéploiement ni une mise à jour (GSO-REQ-088).
`stop` n'entraîne **aucune** suppression de conteneur, volume, donnée
persistante ou fichier de déploiement (GSO-REQ-089). Aucune action implicite,
combinée ou globale ; `SITE` reste le seul argument opérateur.

### Ajouté — lot L4 (déploiement d'un site)

- `playbooks/deploy-site.yml` + `playbooks/_shared/translate.yml` : assertion
  `--limit` == hôte courant → préflight structurel (`gso_validate.py preflight`,
  `no_log`, GSO-REQ-204) → traduction exacte registre/vault → **une seule**
  invocation de `sepp67.grav_site` (GSO-REQ-015/018/061/087/092).
- `scripts/deploy.sh` : sélecteur fermé → **verrou `flock` par site**
  (GSO-REQ-096) → playbook. `make deploy SITE=`.
- `requirements.yml` : ajout de `community.docker` (dépendance de rôle,
  bornée `>=5.0.0,<6.0.0`) ; `make install-role` installe rôle + collection.
- Tests : `GSO-T13` (traduction + second contrôle de cible), `GSO-T14`
  (isolation des secrets, non-fuite, GSO-REQ-204), `GSO-T15` (**déploiement
  réel** d'un site + conteneur `grav-runtime` éphémère sur localhost, contrôle
  fonctionnel, destruction contrôlée), `GSO-T16` (deux sites, isolation sans
  double conteneur), `tests/l4-concurrency-lock.sh` (verrou).
- Doublure de rôle `tests/lib/spy-role/` + harnais `l4_tmptree`.
- `.ansible-lint` ; `ansible.cfg` : `unparsed_is_failed` retiré.
- CI : jobs `translate` (doublure) et `deploy-functional` (conteneur éphémère).

Traduction, verrou et une-seule-invocation prouvés sans donnée réelle
(doublures) ; GSO-T15 seul crée un conteneur, localhost, éphémère, synthétique.

**Correctif de clôture L4 — contrat d'exécution de GSO-T15.** `GSO-T15` est
retiré de la CI standard : il exige une image `grav-runtime` déjà présente
localement (aucun pull implicite, aucun identifiant GHCR — GSO-REQ-108) et
devient un **test d'acceptation local** (`make test-functional`). La CI
conserve `GSO-T13`/`T14`/`T16` + verrou (100 % reproductibles avec doublures)
et ajoute `l4-ci-functional-contract` (garde-fou : pas de pull, pas de
référence flottante, pas de secret de registre). `make test` reste la gate
locale complète (avec `GSO-T15`) ; `make test-reproducible` = sous-ensemble
CI. `GSO-T15` **échoue** (jamais un SKIP, jamais un succès) si une précondition
manque. Contrat détaillé + digest exact : `docs/TESTING.md`.

### Ajouté — lot L3 (sélecteur fermé + préflight lecture seule)

- `scripts/lib/gso_validate.py` : **implémentation unique** des règles de
  validation (registre, vault, sélecteur, préflight) — remplace
  `tests/lib/registry_lint.py` et `tests/lib/vault_lint.py` (logique promue,
  non dupliquée).
- `scripts/validate-target.sh` : sélecteur fermé — `SITE` ↦ `^[a-z][a-z0-9-]*$`,
  inventaire fixé à `inventories/production/hosts.yml` (non remplaçable), un
  seul hôte actif, cohérence registre/vault, refus des cibles retirées et
  globales (GSO-REQ-053, 056, 057, 083-086, 093-095, 107, 138).
- `scripts/preflight.sh` : préflight opérateur read-only, échoue fermé.
- Cibles `make validate SITE=` / `make preflight SITE=`.
- `docs/OPERATIONS.md`.
- `tests/gso-t08` … `tests/gso-t12` + 4 fixtures synthétiques de production
  isolées (`tests/fixtures/l3-*`).
- `GSO-T06`/`GSO-T07` repointés sur le validateur partagé (sens inchangé).
- CI étendue à `GSO-T08`–`GSO-T12`.

Correctif de clôture L3 : `--root` et `--action` **retirés** de l'interface
opérateur. La racine du dépôt et l'inventaire sont déterminés uniquement
depuis l'emplacement canonique de `gso_validate.py` (`realpath`), jamais
depuis le cwd, une option ou une variable d'environnement. L'injection d'une
racine synthétique n'existe plus que via `run_selector` / `run_preflight`
(fonctions internes appelées par le seul code de test). La liste fermée
`NORMATIVE_ACTIONS` est conservée pour L4.

Aucun playbook, aucun appel au rôle, aucun vault opérationnel, aucun
`inventories/production/` réel, aucune connexion : le dépôt reste non
opérationnel.

### Ajouté — lot L2 (modèle de vault)

- `inventories/example/group_vars/all/vault.yml.example` : modèle de vault en
  clair, entièrement synthétique — `vault_grav_sites` (2 entrées : bootstrap
  admin tri-state + `secrets` `name`/`content` pour alpha), `vault_retired_grav_sites: {}`.
- `.gitignore` : garde Git renforcée du vault ; ré-inclusion **unique et
  nommée** de `inventories/example/group_vars/all/vault.yml.example`
  (GSO-REQ-098).
- `docs/VAULT-SCHEMA.md` : schéma normatif du vault (bootstrap administrateur,
  `grav_secrets` `name` + `content`, forme `src` interdite, garde Git,
  disjonction actif/retiré).
- `tests/lib/vault_lint.py` : validateur statique du vault d'exemple, sans
  affichage de valeur.
- `tests/gso-t07-vault-example.sh` : GSO-T07 (correspondance, schéma admin,
  `grav_secrets`, rejet de `src`, non-fuite) + 4 cas négatifs générés.
- `GSO-T24` étendu : garde Git étroite du vault, confinement des marqueurs
  synthétiques.
- Cible `make lint-vault` ; `make test-static` et CI étendus à `GSO-T07`.

Toujours aucun vault opérationnel, aucun secret réel, aucun sélecteur, aucun
playbook, aucune capacité de déploiement.

### Ajouté — lot L1 (couche de données déclaratives)

- `inventories/example/hosts.yml` : deux hôtes fictifs dans `grav_servers`,
  adresses TEST-NET-1.
- `inventories/example/group_vars/all/grav_sites.yml` : registre `grav_sites`
  synthétique (2 entrées), chargé automatiquement par Ansible.
- `docs/REGISTRY-SCHEMA.md` : schéma normatif du registre (champs obligatoires
  et optionnels, unicité, sémantique de `state`, environnements).
- `tests/lib/registry_lint.py` : validateur statique de cohérence
  inventaire ↔ registre (correspondance totale, unicité, schéma, données
  synthétiques).
- `tests/gso-t05-example-inventory.sh`, `tests/gso-t06-registry-autoload.sh` +
  fixture négative `tests/fixtures/l1-broken/`.
- Cibles `make lint-registry` ; `make test-static` étendu ; CI étendue à
  `GSO-T05`/`GSO-T06`.

Aucun vault, aucun secret, aucun sélecteur, aucun appel au rôle : le dépôt
reste non opérationnel par défaut.

### Ajouté — lot L0 (harnais)

- `ansible.cfg` sans inventaire par défaut ; `-i` explicite obligatoire.
- `requirements.yml` épinglant `sepp67.grav_site` sur le tag `v2.0.0`.
- `.gitignore` couvrant vault, rôles installés, caches et sorties de diagnostic.
- `.yamllint` (configuration du harnais de tests).
- `Makefile` : cibles `help`, `install-role`, `lint`, `test`, `test-static`,
  `test-role`, `clean`.
- Batterie de tests `GSO-T01`, `GSO-T02`, `GSO-T03`, `GSO-T04`, `GSO-T23`,
  `GSO-T24` + lanceur `tests/run-all.sh`.
- CI statique (`.github/workflows/ci.yml`).
- Documentation : `README.md`, `docs/ARCHITECTURE.md`, `docs/VERSIONING.md`,
  `docs/GOVERNANCE.md`.
- Squelette de répertoires (`inventories/example`, `playbooks`, `registry`,
  `scripts`) — non peuplés.
- `docs/CONTRAT-ARCHITECTURAL.md` : copie exacte (à l'octet près) du contrat
  architectural `v0.5.0` approuvé, conservée dans l'historique (GSO-REQ-198) ;
  ordre de préséance établi dans `docs/ARCHITECTURE.md`.

Le dépôt reste **non opérationnel par défaut** : aucun inventaire de
production, aucun vault, aucun playbook.
