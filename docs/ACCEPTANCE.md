# Acceptation & release — `grav-sites-ops`

Résumé normatif : contrat architectural `v0.5.0`, **section 22** (critères
d'acceptation) et **§19.8** (préparation d'une release). En cas de divergence,
le contrat fait foi. Livré par le **lot L11** (acceptation), tenu à jour par le
**lot correctif post-publication**.

Ce document **consomme** la matrice des 204 exigences
([`COMPLIANCE-MATRIX.md`](COMPLIANCE-MATRIX.md)) et les résultats observés
([`TEST-RESULTS.md`](TEST-RESULTS.md)) pour statuer, **séparément**, sur :

1. l'**acceptation de la construction locale** — `ACCEPTED` (`main` = `d69a05a`) ;
2. la **publication** (`push` de `main`) — **effectuée** le 2026-09-10
   (autorisation humaine explicite) ; CI distante à ramener au vert ;
3. la **release** (tag + release GitHub) — **BLOCKED** ;
4. la **migration réelle** depuis l'ancien profil — **BLOCKED**.

> **État au 2026-09-10.** `main` = `d69a05a` a été **poussé** vers
> `sepp67/grav-sites-ops` (avance rapide, aucune réécriture). La CI distante a
> tourné une première fois — run `34513250088` : **jobs métier verts**, **une
> étape rouge** (`l11-acceptance-guards`, défaut de garde-fou corrigé depuis),
> **porte `conformance` correctement bloquée**. Le **tag** et la **release**
> restent des étapes **non franchies** (GSO-REQ-192) ; aucun tag n'existe.

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
| **GSO-REQ-187** | *Échec d'un garde-fou bloquant.* Toute non-conformité de sécurité DOIT bloquer une release. | Le mécanisme de blocage **existe et est désormais démontré à distance** : run `34513250088` — une étape rouge (`l11-acceptance-guards`) a fait échouer le job `static` → la **porte `conformance` n'a pas pu passer** (sautée, 0 s). Le gate de release (§4) est conditionné à un run global vert. | **Établi / documenté** *(mécanisme + preuve distante du blocage)* |

### 2.3 Push / CI distante — `push` autorisé effectué, CI observée

| Exigence | Texte (contrat) | Constat | Statut |
|---|---|---|---|
| **GSO-REQ-192** | *Publication séparée.* Le push de `main`, le tag et la release DOIVENT rester des étapes explicitement autorisées et vérifiées. | `main` = `d69a05a` **poussé le 2026-09-10** sur **autorisation humaine explicite** (consignée au rapport d'exécution) ; `push` en **avance rapide**, `origin/main` == `main`, **aucune réécriture** (`l11-acceptance-guards` : `left/right = 0/0`, `origin/main` ancêtre de `HEAD`) ; **aucun tag**, aucune branche de travail poussée ; aucun script / cible / workflow n'automatise `git push` / `git tag` / `gh release`. **Le tag et la release restent des étapes distinctes non franchies.** | **Établi / documenté** — la mécanique (avance rapide, pas d'automatisation) est **testée** ; l'**autorisation humaine** du `push` est consignée au rapport, non prouvable par un test seul |

### 2.4 Tag / release — rien créé, SHA final de release à venir

| Exigence | Texte (contrat) | Constat | Statut |
|---|---|---|---|
| **GSO-REQ-158** | *Tag sur SHA validé.* Un tag de release DOIT pointer exactement sur un commit dont la CI complète est verte. | **Aucun tag.** La CI distante a tourné (run `34513250088`) mais **n'est pas globalement verte**. Le SHA **de construction** accepté est `d69a05a` ; le SHA **final de release** sera **postérieur** (ajout de `LICENSE` + numéro de version + `CHANGELOG` daté → nouveau commit), et c'est **ce** SHA qui devra avoir un **run global CI vert** avant le tag. | **Non encore démontré** — bloqué : pas de SHA de release à CI verte |

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

## 3. Préparation d'une release (contrat §19.8)

**SHA de construction accepté :** `main` = `d69a05a` (poussé). **Ce n'est pas
le SHA de release** : les étapes 4 et 8 ci-dessous produiront un **nouveau
commit** (`LICENSE` + version + `CHANGELOG` daté), noté `<SHA_release>`.

| # | Étape §19.8 | État | Commande (à exécuter au moment voulu, sous autorisation) |
|---|---|---|---|
| 1 | figer le candidat de construction | **fait** | `d69a05a` = `git rev-parse main` |
| 2 | exécuter la matrice `GSO-T01`–`GSO-T24` | **fait** (§TEST-RESULTS) | `make test` |
| 3 | vérifier les exigences `GSO-REQ-*` | **fait** (matrice 204/204) | `make matrix-check` |
| 4 | choisir la licence + le n° de version + dater le `CHANGELOG` → **`<SHA_release>`** | **NON FAIT** — décisions humaines | (édition manuelle + commit) |
| 5 | faire valider la **CI distante sur `<SHA_release>`** → **run global vert** | **NON FAIT** — un premier run a eu lieu sur `d69a05a` (non vert) | *(après `push` de `<SHA_release>`)* |
| 6 | intégrer linéairement dans `main` | fait pour `d69a05a` ; à refaire pour `<SHA_release>` | `git merge --ff-only …` |
| 7 | revalider `main` | **fait** pour `d69a05a` | `make clean && make install-role && make test && make matrix-check` |
| 8 | créer et pousser le **tag annoté** sur `<SHA_release>` | **NON EXÉCUTÉ** — autorisation de release distincte | `git tag -a vX.Y.Z <SHA_release> -m "…" && git push origin vX.Y.Z` |
| 9 | publier la release | **NON EXÉCUTÉ** — autorisation de release distincte | `gh release create vX.Y.Z …` |

**Numéro de version :** non fixé. `v0.1.0` ou `v1.0.0` selon une décision
humaine ; ce document ne la choisit pas.

---

## 4. Verdicts séparés

| Domaine | Verdict | Conditions restantes (humaines / externes) |
|---|---|---|
| **Construction locale** | **`ACCEPTED`** | aucune — **202 / 204** exigences adressées (distribution recalculée mécaniquement : 138 T / 15 S / 47 D / 2 P / 2 N) ; les **2** restantes (GSO-REQ-158, 188) légitimement bloquées ci-dessous ; 24/24 tests normatifs verts, `GSO-T15` vert sans résidu, `make lint` 0 faute, matrice à jour. `main` = `d69a05a`, poussé. |
| **Publication** (`push` de `main`) | **effectuée** — CI à ramener au vert | `main` = `d69a05a` poussé le 2026-09-10 (autorisation humaine explicite, avance rapide, aucune réécriture). CI distante **observée** (run `34513250088`) : jobs métier verts, **run global non vert** (défaut de garde-fou corrigé). Reste : **pousser le correctif** → nouveau run **vert**. |
| **Release** (tag + release GitHub) | **`BLOCKED`** | 1) **fichier `LICENSE`** décidé et ajouté (décision humaine) ; 2) **numéro de version** décidé ; 3) `CHANGELOG` daté → **`<SHA_release>`** (nouveau commit) ; 4) **run CI global vert sur `<SHA_release>`** (GSO-REQ-158) ; 5) autorisation de **tag + release** distincte (GSO-REQ-192) |
| **Migration réelle** | **`BLOCKED`** | 1) autorisation opérationnelle **distincte** (GSO-REQ-188) ; 2) `inventories/production/` + vault opérationnel fournis hors dépôt ; 3) sauvegarde externe vérifiée du vault source ; 4) migration **site par site** avec preuves réelles ; 5) verdict daté par site (GSO-REQ-171) |

**Conclusion.** La **construction locale de `grav-sites-ops` est acceptée**
(`main` = `d69a05a`, poussé). La **CI distante doit être ramenée au vert** (un
correctif de garde-fou est prêt). La **release** et la **migration réelle**
restent **légitimement bloquées** : chacune attend une décision humaine ou une
condition externe précise, énumérée ci-dessus. Aucune de ces conditions n'est
transformée en preuve documentaire.
