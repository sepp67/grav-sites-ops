# Acceptation & release — `grav-sites-ops`

Résumé normatif : contrat architectural `v0.5.0`, **section 22** (critères
d'acceptation) et **§19.8** (préparation d'une release). En cas de divergence,
le contrat fait foi. Livré par le **lot L11** (acceptation).

Ce document **consomme** la matrice des 204 exigences
([`COMPLIANCE-MATRIX.md`](COMPLIANCE-MATRIX.md)) et les résultats observés
([`TEST-RESULTS.md`](TEST-RESULTS.md)) pour statuer, **séparément**, sur :

1. l'**acceptation de la construction locale** ;
2. la **publication** (dépôt distant + `push`) ;
3. la **release** (tag + release GitHub) ;
4. la **migration réelle** depuis l'ancien profil.

> **Rien n'est franchi ici.** L11 est une revue d'acceptation locale
> (GSO-REQ-191 : un audit / préflight ne modifie aucun dépôt sans autorisation
> séparée). Les commandes de publication, de tag et de release sont
> **préparées** mais **non exécutées** (GSO-REQ-192).

---

## 1. Revue des critères d'acceptation (contrat §22)

| §22 | Critère | Constat | Verdict |
|---|---|---|---|
| 22.1 | Acceptation du contrat — sections 1-23 complètes, exigences numérotées sans doublon, pas de contradiction | `docs/CONTRAT-ARCHITECTURAL.md` = copie byte-identique du `v0.5.0` approuvé (SHA-256 vérifié en L0) ; audit de cohérence interne `01-…` réalisé | **COMPLIANT** |
| 22.2 | Acceptation du squelette — arborescence normative, aucun profil réel ni vault, exemple parsable, rôle installable, lint/syntaxe/gardes verts, aucun accès production par défaut | `GSO-T01`/`T02`/`T03`/`T05` verts ; `inventories/production/` absent ; `**/vault.yml` git-ignoré ; `make validate`/`deploy` échouent sans `inventories/production/` | **COMPLIANT** |
| 22.3 | Acceptation fonctionnelle — `GSO-T01`–`GSO-T24` exécutés, consignés, réussis, statique vs fonctionnel distingués | 24/24 verts (`TEST-RESULTS.md` §2-§3) ; `GSO-T15` = seul fonctionnel, hors CI | **COMPLIANT** |
| 22.4 | Acceptation de sécurité — vault absent de Git/CI, aucun secret en log, aucun chemin local, aucune opération destructive, refus cible absente/globale/multiple/inconnue, aucune dépendance `control-repository`, aucun accès production depuis la CI | `GSO-T07`/`T08`/`T09`/`T10`/`T11`/`T12`/`T14`/`T23`/`T24`, `l7-persistence-guard`, `l10-ci-blocking`, `l10-multisite-isolation` — tous verts | **COMPLIANT** |
| 22.5 | Acceptation de la migration — vault source sauvegardé, nouveau vault chiffré/ignoré/sauvegardé, chaque site migré séparément, trois états concordants, quatre volumes préservés, aucun recours à l'ancien profil | **Aucune migration réelle n'a eu lieu.** Cadre documentaire vérifié (`docs/MIGRATION.md`, `l9-migration-doc-guard`, rapport L9 révision 3 : 5 testées / 10 établies) | **DOCUMENTATION ONLY** — opérationnel différé (GSO-REQ-188) |
| 22.6 | Acceptation documentaire — README + docs permettent d'installer, comprendre les frontières, ajouter un site, exécuter chaque opération, mettre à jour / rollbacker, retirer / réactiver, interpréter une dérive, retrouver le guide de migration | `README.md`, `docs/OPERATIONS.md`, `docs/ARCHITECTURE.md`, `docs/REGISTRY-SCHEMA.md`, `docs/VAULT-SCHEMA.md`, `docs/LIFECYCLE-SCHEMA.md`, `docs/MIGRATION.md`, `docs/TESTING.md` présents et cohérents | **COMPLIANT** |
| 22.7 | Statuts de préflight explicites, chaque exigence : statut + preuve + lot de correction si besoin | `08-preflight-construction.md` §5 : 204/204 cartographiées ; `COMPLIANCE-MATRIX.md` : 204 lignes, 5 niveaux | **COMPLIANT** |
| 22.8 | Gate de construction formulé explicitement | Voir §2 ci-dessous | **READY FOR IMPLEMENTATION APPROVAL** *(déjà donné, lot par lot)* |
| 22.9 | Gate de release — SHA final CI complète verte, changelog prêt, matrices sans écart critique | Voir §4 ci-dessous | **BLOCKED — voir §4** |

---

## 2. Évaluation des 13 exigences portées par L11

Relevé textuel du contrat `v0.5.0` §22-§23 et §19.8. Classées selon ce qu'elles
**demandent réellement**.

### 2.1 Revues / contrôles documentaires — exécutés et consignés

| Exigence | Texte (contrat) | Constat L11 | Statut |
|---|---|---|---|
| **GSO-REQ-159** | *Release et exploitation séparées.* Aucun événement Git de release NE DOIT déclencher une mutation des VM de production. | Aucun workflow, hook, script ou cible ne réagit à un tag / une release ; `ci.yml` `on:` = `push` / `pull_request` / `workflow_dispatch` uniquement, jamais `release:` ; aucune étape de déploiement dans la CI. Vérifié par `l11-acceptance-guards`. | **Établi / documenté** |
| **GSO-REQ-183** | *Deux décisions humaines.* Le cycle de vie local d'un site et son exposition publique DOIVENT rester deux décisions opérationnelles distinctes. | Aucune notion de domaine / publication dans le registre (`REGISTRY-SCHEMA.md`) ; `docs/OPERATIONS.md` rappelle que la publication relève du `control-repository`, séparément ; `GSO-T23` (aucune dépendance) ; §10.4 GSO-REQ-067 déjà testé. | **Établi / documenté** |
| **GSO-REQ-184** | *Audit avant construction.* La création réelle du dépôt DOIT être précédée d'un audit décisionnel et d'un préflight de conformité fondés sur ce contrat. | `audit-grav-sites-ops/` : `01`…`07` (audit de cohérence, préflight décisionnel, arbitrages, corrections du contrat) puis `08-preflight-construction.md` (préflight de construction, verdict `BUILD PREFLIGHT APPROVED`) — **antérieurs** au premier commit de construction. | **Établi / documenté** |
| **GSO-REQ-185** | *Squelette non opérationnel par défaut.* Le premier commit du dépôt NE DOIT contenir aucune cible réelle ou capacité implicite de déploiement. | Premier commit `4a4eab0` (« first commit ») = `README.md`, **1 ligne**. Aucun playbook, script, inventaire, Makefile. Vérifié par `l11-acceptance-guards` (`git show <root>`). | **Établi / documenté** |
| **GSO-REQ-186** | *Zéro test critique manquant.* Aucun `TEST GAP` ne peut subsister pour la sélection, les secrets, la persistance, la consommation du rôle et l'absence de contact réel. | Sélection : `GSO-T08`–`T12` ; secrets : `GSO-T07`/`T14`/`T24` + `l10-multisite-isolation` ; persistance : `GSO-T17`/`T18` + `l7-persistence-guard` ; consommation du rôle : `GSO-T03`/`T04`/`T13`/`T15` (1 `include_role`) ; absence de contact réel : `GSO-T12`/`T23` + `l10-ci-blocking`. **Aucun `TEST GAP`** dans la matrice. | **Établi / documenté** |
| **GSO-REQ-189** | *Documentation exécutable.* Les commandes documentées DOIVENT être testées ou explicitement signalées comme exemples non exécutés. | Les **21** cibles `make` documentées dans `README.md` correspondent **exactement** aux 21 cibles réelles du `Makefile`, toutes couvertes par `make test` ; les invocations `scripts/*.sh` sont celles des tests. Les exemples non exécutables (`inventories/production/…`, adresses LAN) sont **signalés comme tels**. Vérifié par `l11-acceptance-guards`. | **Établi / documenté** |
| **GSO-REQ-190** | *Matrice exhaustive.* Le préflight DOIT cartographier chaque `GSO-REQ-*` sans omission. | `08-preflight-construction.md` §5 : L0 40 + L1 23 + L2 10 + L3 18 + L4 20 + L5 2 + L6 11 + L7 17 + L8 16 + L9 15 + L10 19 + L11 13 = **204**, chacune une fois. `COMPLIANCE-MATRIX.md` : **204** lignes `GSO-REQ-`, `make matrix-check` vert. | **Établi / documenté** |
| **GSO-REQ-191** | *Audit non exécutoire.* Un audit ou préflight NE DOIT modifier aucun dépôt sans autorisation séparée. | Les documents `audit-grav-sites-ops/01`…`08` n'ont produit aucun commit dans `6-grav-sites-ops` ; chaque lot L0–L11 a reçu une **autorisation humaine distincte** avant modification ; L11 lui-même ne franchit ni publication, ni tag, ni migration. | **Établi / documenté** |
| **GSO-REQ-202** | *Approbation explicite.* Le contrat complet DOIT recevoir une approbation humaine avant de servir de base exécutoire à la création de `grav-sites-ops`. | Contrat `v0.5.0` §23.10 : « approbation humaine explicite le **2026-09-05** », statut « normatif, approuvé ». `README.md` et `docs/GOVERNANCE.md` le référencent comme source normative. | **Établi / documenté** |

### 2.2 Gate exigeant une autorisation humaine — le gate existe, l'étape protégée n'est pas franchie

| Exigence | Texte (contrat) | Constat L11 | Statut |
|---|---|---|---|
| **GSO-REQ-187** | *Échec d'un garde-fou bloquant.* Toute non-conformité de sécurité DOIT bloquer une release. | Le mécanisme de blocage **existe** : CI en jobs bloquants (job `conformance` `needs:` tous les jobs, aucun `continue-on-error` — `l10-ci-blocking`) ; le présent gate de release (§4) est **conditionné** à la matrice sans écart critique et au SHA CI-vert. Une non-conformité de sécurité rend un job rouge → `conformance` rouge → SHA non éligible. **Non observé en pratique** tant que la CI n'a pas tourné à distance. | **Établi / documenté** *(mécanisme)* — observation différée à la première CI distante |

### 2.3 Push / CI distante — constaté « non exécuté », blocage maintenu

| Exigence | Texte (contrat) | Constat L11 | Statut |
|---|---|---|---|
| **GSO-REQ-192** | *Publication séparée.* Le push de `main`, le tag et la release DOIVENT rester des étapes explicitement autorisées et vérifiées. | Un `remote origin` (`git@github.com:sepp67/grav-sites-ops.git`) existe et ne contient que le **commit initial** `4a4eab0` (`README.md`, 1 ligne) ; `main` local est **66 commits ahead** de `origin/main`, **jamais poussé** ; aucune branche de construction poussée ; aucun tag ; aucun script / cible / workflow n'exécute `git push`, `git tag` ou `gh release`. La séparation est **structurelle**. Le franchissement exige l'autorisation de **premier `push`** puis de **release** — **distinctes**. | **Non encore démontré** — bloqué : `push` de `main` non autorisé |

### 2.4 Tag / release — commande et SHA préparés, rien créé

| Exigence | Texte (contrat) | Constat L11 | Statut |
|---|---|---|---|
| **GSO-REQ-158** | *Tag sur SHA validé.* Un tag de release DOIT pointer exactement sur un commit dont la CI complète est verte. | SHA candidat **préparé** (§3) ; la commande de tag est **rédigée mais non exécutée**. La condition « CI complète verte sur ce SHA » **ne peut pas être satisfaite localement** : elle exige l'exécution distante de la CI après `push` (non autorisé). | **Non encore démontré** — bloqué : SHA non encore validé par une CI distante |

### 2.5 Migration réelle — non exécutée, autorisation opérationnelle distincte

| Exigence | Texte (contrat) | Constat L11 | Statut |
|---|---|---|---|
| **GSO-REQ-188** | *Migration distincte de la construction.* La conformité du dépôt PEUT être établie avec des données fictives avant la migration ; la conformité opérationnelle exige ensuite des preuves propres aux sites réels. | **Première moitié satisfaite** : la conformité du dépôt est établie avec des fixtures synthétiques (L9 + toute la matrice). **Seconde moitié différée** : aucune preuve propre à un site réel n'existe (aucun site migré). Décision humaine propre (préflight §7.3, §2.3). | **Non encore démontré** — opérationnel, hors périmètre de construction |

### 2.6 Décision de licence — décision humaine bloquante, aucune licence choisie

Non couverte par un `GSO-REQ-*` mais **résidu ouvert du lot L0** (`README.md` :
« Licence — Non encore fixée » ; rapport L0 §6.2). `docs/ACCEPTANCE.md` la
**signale** comme `DECISION REQUIRED` : une release publique nécessite un
fichier `LICENSE`. **L11 ne choisit aucune licence** (ce serait un choix
implicite). Reste à trancher par une décision humaine avant publication.

---

## 3. Préparation documentaire d'une release (contrat §19.8) — NON EXÉCUTÉE

**SHA candidat :** `HEAD` de `main` après intégration de L11 (à consigner dans
le rapport d'exécution L11 — noté ici `<SHA_L11>`).

Séquence §19.8, **aucune étape exécutée** :

| # | Étape §19.8 | État | Commande préparée (non exécutée) |
|---|---|---|---|
| 1 | figer le candidat | fait localement | `<SHA_L11>` = `git rev-parse main` |
| 2 | exécuter la matrice `GSO-T01`–`GSO-T24` | **fait** (§TEST-RESULTS) | `make test` |
| 3 | vérifier les exigences `GSO-REQ-*` | **fait** (matrice 204/204) | `make matrix-check` |
| 4 | dater le changelog | à faire au moment de la release | (édition manuelle de `CHANGELOG.md`) |
| 5 | faire valider la CI sur le SHA final | **IMPOSSIBLE localement** — exige la CI distante | *(après `push`, autorisation distincte)* |
| 6 | intégrer linéairement dans `main` | fait (fast-forward, 0 merge) | `git merge --ff-only construction/lot-11` |
| 7 | revalider `main` | **fait** depuis `main` | `make clean && make install-role && make test && make matrix-check` |
| 8 | créer et pousser le tag annoté | **NON EXÉCUTÉ** — autorisation de release distincte | `git tag -a vX.Y.Z <SHA_L11> -m "…" && git push origin vX.Y.Z` |
| 9 | publier la release | **NON EXÉCUTÉ** — autorisation de release distincte | `gh release create vX.Y.Z …` |

**Numéro de version :** non fixé. La première version stable serait `v0.1.0`
ou `v1.0.0` selon une décision humaine ; ce document ne la choisit pas.

---

## 4. Verdicts séparés

| Domaine | Verdict | Conditions restantes (humaines / externes) |
|---|---|---|
| **Construction locale** | **`ACCEPTED`** | aucune — **201 / 204** exigences adressées (191 par L0-L10 + **10** revues d'acceptation L11), les **3** restantes (GSO-REQ-158, 188, 192) légitimement bloquées ci-dessous ; 24/24 tests normatifs verts, `GSO-T15` vert sans résidu, `make lint` 0 faute, matrice à jour |
| **Publication** (`push` de `main`) | **`BLOCKED`** | le dépôt distant `sepp67/grav-sites-ops` existe déjà (commit initial seul). Restent : 1) autorisation de **premier `push`** de `main` / d'une branche de construction ; 2) exécution et observation de la **CI distante** (GSO-REQ-147) |
| **Release** (tag + release GitHub) | **`BLOCKED`** | 1) publication débloquée (ci-dessus) ; 2) **CI complète verte** sur le SHA final (GSO-REQ-158) ; 3) `CHANGELOG` daté ; 4) **fichier `LICENSE`** décidé et ajouté (décision humaine) ; 5) numéro de version décidé ; 6) autorisation de **release** distincte (GSO-REQ-192) |
| **Migration réelle** | **`BLOCKED`** | 1) autorisation opérationnelle **distincte** (GSO-REQ-188) ; 2) `inventories/production/` + vault opérationnel fournis hors dépôt ; 3) sauvegarde externe vérifiée du vault source ; 4) migration **site par site** avec preuves réelles ; 5) verdict daté par site (GSO-REQ-171) |

**Conclusion.** La **construction locale de `grav-sites-ops` est acceptée**. La
**publication**, la **release** et la **migration réelle** restent
**légitimement bloquées** : chacune attend une décision humaine ou une
condition externe précise, énumérée ci-dessus. Aucune de ces conditions n'est
transformée en preuve documentaire ; elles sont maintenues comme conditions
ouvertes.
