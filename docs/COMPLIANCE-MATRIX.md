# Matrice de conformité — 204 exigences `GSO-REQ`

Résumé normatif : contrat architectural `v0.5.0` (`docs/CONTRAT-ARCHITECTURAL.md`).
En cas de divergence, le contrat fait foi. Livré et tenu à jour par le **lot L10**
(GSO-REQ-150) ; régénérable par `make matrix`, vérifiable par `make matrix-check`.

Cinq niveaux, **distincts** :

- **Satisfait et testé** — un `GSO-T01`–`GSO-T24` ou un garde-fou non numéroté
  (`l4-`…`l10-`) exerce l'exigence ; exécution consignée dans [`TEST-RESULTS.md`](TEST-RESULTS.md).
- **Satisfait** — mécanisme en place, couvert **structurellement ou indirectement**
  (p. ex. par `GSO-T01`/`GSO-T02`/`GSO-T06`), sans test dédié.
- **Établi / documenté** — preuve **documentaire** : soit le contrat la déclare non
  vérifiable par un test automatisé (GSO-REQ-070, 161), soit c'est une règle de
  gouvernance / de procédure.
- **Partiel** — une partie testée, une autre **différée** à une exécution réelle
  autorisée (GSO-REQ-091, 078).
- **Non encore démontré (L11)** — relève du lot **L11** (acceptation & release),
  **non démarré**.

Les preuves issues d'un **lot antérieur** ou du **rôle** `sepp67.grav_site` sont
**attribuées à leur véritable mécanisme**, pas à L10.

---

## Synthèse

| Statut | Nombre |
|---|---|
| Satisfait et testé | 138 |
| Satisfait | 15 |
| Établi / documenté | 36 |
| Partiel | 2 |
| Non encore démontré (L11) | 13 |
| **Total** | **204** |

**191 / 204** exigences sont adressées par les lots L0–L10 (aucune en
échec). Les **13** exigences L11 sont **non démontrées** : revue
d'acceptation §22, gates de release, préparation de tag — lot **non autorisé**.
La première release ne peut être préparée tant que ces exigences ne sont pas
traitées (contrat §18.16, GSO-REQ-150).

## Matrice détaillée (204 exigences)

| # | Lot | Intitulé | Preuve principale | Statut |
|---|---|---|---|---|
| GSO-REQ-001 | L0 | Contrat préalable | docs/GOVERNANCE.md (contrat approuvé avant construction) | Établi / documenté |
| GSO-REQ-002 | L0 | Traçabilité des écarts | docs/GOVERNANCE.md + rapports d'exécution datés | Établi / documenté |
| GSO-REQ-003 | L4 | Déploiement LAN autonome | GSO-T15 (déploiement LAN local) | Satisfait et testé |
| GSO-REQ-004 | L0 | Publication indépendante | GSO-T01, GSO-T02, GSO-T23 | Satisfait et testé |
| GSO-REQ-005 | L1 | Environnement unique | GSO-T05 | Satisfait et testé |
| GSO-REQ-006 | L1 | Exemple non opérationnel | GSO-T05, GSO-T07 | Satisfait et testé |
| GSO-REQ-007 | L1 | Une VM par projet | REGISTRY-SCHEMA.md + GSO-T06 | Satisfait |
| GSO-REQ-008 | L1 | Identifiant opérationnel unique | GSO-T06 (jointure par inventory_hostname) | Satisfait et testé |
| GSO-REQ-009 | L0 | Absence de dépendance croisée | GSO-T23 | Satisfait et testé |
| GSO-REQ-010 | L1 | Source de vérité applicative | GSO-T06 | Satisfait et testé |
| GSO-REQ-011 | L1 | Pas de seconde source pour le runtime | GSO-T06 | Satisfait et testé |
| GSO-REQ-012 | L1 | Chargement automatique | GSO-T06 | Satisfait et testé |
| GSO-REQ-013 | L1 | Correspondance totale | GSO-T06 | Satisfait et testé |
| GSO-REQ-014 | L0 | Dépendance épinglée | GSO-T04 + requirements.yml (tag épinglé) | Satisfait et testé |
| GSO-REQ-015 | L4 | Interface publique uniquement | GSO-T13 (traduction exacte) | Satisfait et testé |
| GSO-REQ-016 | L3 | Limite obligatoire | GSO-T13 (assertion --limit) + _shared/mutate.yml | Satisfait et testé |
| GSO-REQ-017 | L3 | Cible unique | GSO-T10, GSO-T13 | Satisfait et testé |
| GSO-REQ-018 | L3 | Pas de variable de sélection parallèle | l5-action-closed + GSO-T13 | Satisfait et testé |
| GSO-REQ-019 | L4 | Séparation orchestration/mécanisme | GSO-T20 + l7-persistence-guard (rôle non copié) | Satisfait et testé |
| GSO-REQ-020 | L1 | Pas de `latest` | GSO-T06, GSO-T13 | Satisfait et testé |
| GSO-REQ-021 | L1 | Référence explicite | GSO-T06, GSO-T13 | Satisfait et testé |
| GSO-REQ-022 | L2 | Vault unique | GSO-T07 | Satisfait et testé |
| GSO-REQ-023 | L2 | Aucun secret suivi | .gitignore + GSO-T24 | Satisfait et testé |
| GSO-REQ-024 | L2 | Absence de divulgation | GSO-T14, GSO-T24, l10-multisite-isolation | Satisfait et testé |
| GSO-REQ-025 | L0 | Commandes explicites | scripts set -euo pipefail ; gso_validate _finish → code ≠ 0 | Satisfait |
| GSO-REQ-026 | L3 | Échec sûr | GSO-T08..T12 (échoue fermé) | Satisfait et testé |
| GSO-REQ-027 | L8 | Retrait non destructif | GSO-T21 (retrait non destructif) | Satisfait et testé |
| GSO-REQ-028 | L8 | Registre des projets retirés | GSO-T21 + GSO-T24 (registre sans secret) | Satisfait et testé |
| GSO-REQ-029 | L8 | Absence de playbook destructif | GSO-T21 + l7-persistence-guard (aucun playbook destructif) | Satisfait et testé |
| GSO-REQ-030 | L10 | CI non opérationnelle | l10-ci-blocking | Satisfait et testé |
| GSO-REQ-031 | L0 | Images externes | GSO-T24 + .gitignore | Satisfait et testé |
| GSO-REQ-032 | L0 | VM préexistantes | GSO-T24 + .gitignore | Satisfait et testé |
| GSO-REQ-033 | L7 | Pas de synchronisation implicite | l7-persistence-guard (aucune synchro implicite) | Satisfait et testé |
| GSO-REQ-034 | L0 | Spécialisation Grav | docs/ARCHITECTURE.md (ordre de préséance) | Établi / documenté |
| GSO-REQ-035 | L4 | Composition | GSO-T13, GSO-T16 | Satisfait et testé |
| GSO-REQ-036 | L1 | Isolation d'exploitation | GSO-T06 (fixture négative) | Satisfait et testé |
| GSO-REQ-037 | L1 | Clé commune | GSO-T06 | Satisfait et testé |
| GSO-REQ-038 | L3 | Refus par défaut | GSO-T11, GSO-T12 | Satisfait et testé |
| GSO-REQ-039 | L7 | Pas de mélange | GSO-T07, GSO-T24 | Satisfait et testé |
| GSO-REQ-040 | L7 | Données préservées | l7-persistence-guard + GSO-T17/T18 | Satisfait et testé |
| GSO-REQ-041 | L1 | Références reproductibles | requirements.yml (community.docker bornée) + GSO-T04 | Satisfait et testé |
| GSO-REQ-042 | L2 | Secret hors historique | GSO-T14, GSO-T24 | Satisfait et testé |
| GSO-REQ-043 | L0 | Pas de couplage de publication | GSO-T24 (aucun secret suivi) | Satisfait et testé |
| GSO-REQ-044 | L8 | Archivage avant oubli | GSO-T21 (archivage avant oubli, même changement Git) | Satisfait et testé |
| GSO-REQ-045 | L0 | Frontière infrastructure | ansible.cfg (aucun inventaire par défaut) + GSO-T08 | Satisfait et testé |
| GSO-REQ-046 | L10 | Cloisonnement CI | l10-ci-blocking | Satisfait et testé |
| GSO-REQ-047 | L0 | Amendement préalable | docs/GOVERNANCE.md (procédure d'amendement) | Établi / documenté |
| GSO-REQ-048 | L1 | Schéma explicite | GSO-T06 | Satisfait et testé |
| GSO-REQ-049 | L1 | Valeurs scalaires sûres | GSO-T06 | Satisfait et testé |
| GSO-REQ-050 | L1 | Unicité du parc | GSO-T06 | Satisfait et testé |
| GSO-REQ-051 | L1 | États non destructifs | GSO-T06 | Satisfait et testé |
| GSO-REQ-052 | L8 | Registres disjoints | GSO-T22 (disjonction stricte) | Satisfait et testé |
| GSO-REQ-053 | L3 | Aucun inventaire opérationnel par défaut | GSO-T08 (inventaire imposé) | Satisfait et testé |
| GSO-REQ-054 | L4 | Groupe fermé | GSO-T13 | Satisfait et testé |
| GSO-REQ-055 | L1 | Indépendance du répertoire courant | GSO-T06 | Satisfait et testé |
| GSO-REQ-056 | L3 | Zéro cible interdit | GSO-T11 (sur le validateur) | Satisfait et testé |
| GSO-REQ-057 | L3 | Une seule cible | GSO-T10, GSO-T13 | Satisfait et testé |
| GSO-REQ-058 | L10 | Inventaire CI isolé | l10-ci-blocking | Satisfait et testé |
| GSO-REQ-059 | L0 | Installation reproductible | docs/ARCHITECTURE.md | Établi / documenté |
| GSO-REQ-060 | L0 | Mise à niveau isolée | README.md + docs/ARCHITECTURE.md | Établi / documenté |
| GSO-REQ-061 | L2 | Secrets par identifiant d'hôte | GSO-T07, GSO-T13 | Satisfait et testé |
| GSO-REQ-062 | L2 | Ensemble de bootstrap cohérent | GSO-T07, GSO-T13 (tri-state) | Satisfait et testé |
| GSO-REQ-063 | L4 | Sens unique de l'état | GSO-T13/T14 (par inventory_hostname) | Satisfait et testé |
| GSO-REQ-064 | L4 | Contrat vérifié | GSO-T15 (vrai rôle v2.0.0, chemin réel) | Satisfait et testé |
| GSO-REQ-065 | L1 | Endpoint LAN explicite | gso_validate registry (bind_address IPv4) + GSO-T06 | Satisfait et testé |
| GSO-REQ-066 | L4 | Santé indépendante d'Internet | GSO-T13 | Satisfait et testé |
| GSO-REQ-067 | L0 | Zéro transmission automatique | docs/VAULT-SCHEMA.md | Établi / documenté |
| GSO-REQ-068 | L1 | Exemples non opérationnels | GSO-T06 (unicité) | Satisfait et testé |
| GSO-REQ-069 | L2 | Vault local protégé | GSO-T24 (garde Git du vault) | Satisfait et testé |
| GSO-REQ-070 | L9 | Sauvegarde avant migration | MIGRATION.md §3 — preuve documentaire (non automatisable par contrat) | Établi / documenté |
| GSO-REQ-071 | L2 | Pas de rotation implicite | GSO-T13/T14 (aucune rotation simulée) | Satisfait et testé |
| GSO-REQ-072 | L4 | Bootstrap sûr | GSO-T13 (aucune valeur globale) | Satisfait et testé |
| GSO-REQ-073 | L8 | Secrets retirés hors ensemble actif | GSO-T22 (secrets retirés hors ensemble actif) | Satisfait et testé |
| GSO-REQ-074 | L10 | Test de non-fuite | l10-ci-blocking (GSO-T24 dans la CI) | Satisfait et testé |
| GSO-REQ-075 | L7 | Persistance prioritaire | GSO-T17/T18 (quatre ensembles) + l7-persistence-guard | Satisfait et testé |
| GSO-REQ-076 | L7 | Rollback limité à l'image | GSO-T18 + l7-persistence-guard | Satisfait et testé |
| GSO-REQ-077 | L7 | Pas de `rsync` implicite | l7-persistence-guard (aucune synchronisation de contenu) | Satisfait et testé |
| GSO-REQ-078 | L7 | Déploiement distinct de la sauvegarde | l7-persistence-guard (versant négatif) + docs — sauvegarde réelle hors périmètre | Partiel |
| GSO-REQ-079 | L7 | Absence de destruction automatisée | l7-persistence-guard (aucune primitive de destruction de volume ou de répertoire) | Satisfait et testé |
| GSO-REQ-080 | L10 | Couverture de persistance | GSO-T17/T18 (scénario) + l7-persistence-guard (statique) | Satisfait et testé |
| GSO-REQ-081 | L4 | Un playbook, une intention | l5-action-closed (une intention par playbook) | Satisfait et testé |
| GSO-REQ-082 | L4 | Pas de déploiement global implicite | l5-action-closed + _shared/mutate.yml (jamais global) | Satisfait et testé |
| GSO-REQ-083 | L3 | Site obligatoire | GSO-T09 | Satisfait et testé |
| GSO-REQ-084 | L3 | Site littéral | GSO-T10 (SITE littéral) | Satisfait et testé |
| GSO-REQ-085 | L3 | Préflight à deux niveaux | GSO-T11 + GSO-T13 (préflight à deux niveaux) | Satisfait et testé |
| GSO-REQ-086 | L3 | Cible inconnue en échec | GSO-T11 | Satisfait et testé |
| GSO-REQ-087 | L4 | Invocation unique | GSO-T13, GSO-T15 (une invocation) | Satisfait et testé |
| GSO-REQ-088 | L5 | Redémarrage sans changement de version | l5-restart-stop (version/digest inchangés) | Satisfait et testé |
| GSO-REQ-089 | L5 | Arrêt réversible | l5-restart-stop + l5-action-closed (aucune suppression) | Satisfait et testé |
| GSO-REQ-090 | L6 | Contrôle sans remédiation | GSO-T20 + l7-persistence-guard (aucun include_role) | Satisfait et testé |
| GSO-REQ-091 | L4 | Pas de faux succès en check mode | l10-check-mode (comportement, doublure) + docs/OPERATIONS.md — --check vs vrai rôle non exercé | Partiel |
| GSO-REQ-092 | L4 | Secret absent des commandes | GSO-T14, l10-multisite-isolation (no_log sous -vv) | Satisfait et testé |
| GSO-REQ-093 | L3 | Codes de sortie fiables | GSO-T11 (codes ≠ 0) + l5-restart-stop | Satisfait et testé |
| GSO-REQ-094 | L3 | Ambiguïté non mutante | GSO-T10, GSO-T13 | Satisfait et testé |
| GSO-REQ-095 | L3 | Validation locale prioritaire | GSO-T08..T12 | Satisfait et testé |
| GSO-REQ-096 | L3 | Une mutation à la fois | l4-concurrency-lock + l5-restart-stop | Satisfait et testé |
| GSO-REQ-097 | L4 | Privilèges minimaux | deploy-site.yml become:false + GSO-T15 | Satisfait |
| GSO-REQ-098 | L2 | Garde Git du vault | GSO-T24 (ré-inclusion nommée unique) | Satisfait et testé |
| GSO-REQ-099 | L0 | Portabilité du dépôt | GSO-T24 (aucun chemin de workstation) | Satisfait et testé |
| GSO-REQ-100 | L1 | Contrôle contextuel des IP | REGISTRY-SCHEMA.md | Établi / documenté |
| GSO-REQ-101 | L4 | Erreur utile sans fuite | GSO-T14 (no_log) | Satisfait et testé |
| GSO-REQ-102 | L7 | Garde destructif | l7-persistence-guard (garde CI destructif) | Satisfait et testé |
| GSO-REQ-103 | L0 | Dépendances vérifiables | GSO-T04 | Satisfait et testé |
| GSO-REQ-104 | L6 | Confirmation globale | GSO-T20 (check-all ≠ mutation) | Satisfait et testé |
| GSO-REQ-105 | L4 | État désiré traçable | l7-persistence-guard + docs/OPERATIONS.md (jamais push/tag) | Satisfait |
| GSO-REQ-106 | L4 | Échec non masqué | l7-persistence-guard | Satisfait |
| GSO-REQ-107 | L3 | Refus avant SSH | GSO-T12 (aucun contact après refus) | Satisfait et testé |
| GSO-REQ-108 | L0 | Exploitation distincte de la publication | l4-ci-functional-contract + l10-ci-blocking | Satisfait et testé |
| GSO-REQ-109 | L7 | Changement dans le registre | GSO-T13 + l7-persistence-guard (registre seul) | Satisfait et testé |
| GSO-REQ-110 | L7 | Digest jamais ignoré | GSO-T13 (digest transmis, jamais hybride) | Satisfait et testé |
| GSO-REQ-111 | L4 | Pull explicite | GSO-T13 (force_pull non global) | Satisfait et testé |
| GSO-REQ-112 | L7 | Rollback traçable | GSO-T18 (rollback traçable Git) | Satisfait et testé |
| GSO-REQ-113 | L7 | Pas de rollback des données | GSO-T18 + l7-persistence-guard (pas de rollback des données) | Satisfait et testé |
| GSO-REQ-114 | L7 | Pas d'enchaînement aveugle | l7-persistence-guard (aucun rollback automatique) | Satisfait et testé |
| GSO-REQ-115 | L7 | Une dimension par changement | docs/OPERATIONS.md — mécanisme = requirements.yml séparé (L0) | Établi / documenté |
| GSO-REQ-116 | L7 | Trois états vérifiés | mécanisme = make check (L6, GSO-T19) — procédure documentée | Satisfait |
| GSO-REQ-117 | L7 | Historique non réécrit | l7-persistence-guard + GSO-T17 (journal du rôle non réécrit) | Satisfait et testé |
| GSO-REQ-118 | L6 | États distincts | GSO-T19 | Satisfait et testé |
| GSO-REQ-119 | L6 | État du rôle en lecture seule | GSO-T19, GSO-T20 (état du rôle en lecture) | Satisfait et testé |
| GSO-REQ-120 | L6 | Santé réelle | GSO-T19 (santé réelle) | Satisfait et testé |
| GSO-REQ-121 | L6 | Dérive classifiée | GSO-T19 (8 catégories, STOPPED relatif) | Satisfait et testé |
| GSO-REQ-122 | L6 | Lecture séparée de l'action | GSO-T19, GSO-T20 (aucun appel deploy) | Satisfait et testé |
| GSO-REQ-123 | L6 | Rapport sans secret | GSO-T19 (rapport sans secret) | Satisfait et testé |
| GSO-REQ-124 | L6 | Pas de facts inutiles | GSO-T19/T20 (gather_facts:false) | Satisfait et testé |
| GSO-REQ-125 | L6 | Dérive déclarative | GSO-T20 (cohérence sans VM) | Satisfait et testé |
| GSO-REQ-126 | L6 | Git sous contrôle humain | l7-persistence-guard + gso_lifecycle read-only (aucun retour Git auto) | Satisfait et testé |
| GSO-REQ-127 | L0 | Racine lisible | .gitignore + GSO-T24 | Satisfait et testé |
| GSO-REQ-128 | L1 | Registre unique | REGISTRY-SCHEMA.md + GSO-T06 | Satisfait |
| GSO-REQ-129 | L0 | Pas de rôle de rôles | préflight §3 : playbooks/_shared factorise sans rôle d'orchestration ; revue | Satisfait |
| GSO-REQ-130 | L0 | Scripts bornés | gso_validate.py / gso_lifecycle.py strictement read-only | Satisfait |
| GSO-REQ-131 | L0 | Documentation cohérente | CHANGELOG.md tenu à chaque lot | Satisfait |
| GSO-REQ-132 | L0 | Ignorés testés | GSO-T24 (catégories sensibles non suivies) | Satisfait et testé |
| GSO-REQ-133 | L9 | Migration de données seulement | l9-migration-doc-guard (fixtures ancien ≠ nouveau) | Satisfait et testé |
| GSO-REQ-134 | L0 | Ajout sans code | docs/VERSIONING.md | Établi / documenté |
| GSO-REQ-135 | L0 | Dépôt Grav uniquement | docs/VERSIONING.md | Établi / documenté |
| GSO-REQ-136 | L10 | Preuve observée | docs/TEST-RESULTS.md (exécutions observées) | Satisfait et testé |
| GSO-REQ-137 | L10 | Garde-fous rejouables | cas négatifs : GSO-T09..T12, GSO-T22, l7/l8/l9 guards | Satisfait et testé |
| GSO-REQ-138 | L3 | Sélecteur fermé | GSO-T09, GSO-T10, GSO-T11 | Satisfait et testé |
| GSO-REQ-139 | L10 | Vault réel absent de CI | l10-ci-blocking (aucun test n'exige le vault de production) | Satisfait et testé |
| GSO-REQ-140 | L10 | Même chemin que l'opérateur | GSO-T03/T04 (même référence épinglée que l'installation documentée) | Satisfait et testé |
| GSO-REQ-141 | L10 | Réseau de test isolé | GSO-T15 (localhost éphémère) + l4-ci-functional-contract | Satisfait et testé |
| GSO-REQ-142 | L10 | Isolation des projets | l10-multisite-isolation + GSO-T16 + GSO-T14 | Satisfait et testé |
| GSO-REQ-143 | L10 | Persistance testée | GSO-T17/T18 (pages/accounts/data/images séparés) | Satisfait et testé |
| GSO-REQ-144 | L10 | Contrôle non mutant prouvé | GSO-T19/T20 + l7-persistence-guard (aucun fichier/conteneur modifié) | Satisfait et testé |
| GSO-REQ-145 | L10 | Jobs bloquants | l10-ci-blocking (job conformance ; aucun continue-on-error) | Satisfait et testé |
| GSO-REQ-146 | L10 | Outils reproductibles | l10-ci-blocking (python 3.12, ansible-core >=2.17,<2.19) | Satisfait et testé |
| GSO-REQ-147 | L10 | Pas de preuve inventée | docs/TEST-RESULTS.md + l10-ci-blocking (CI distante non observée) | Satisfait et testé |
| GSO-REQ-148 | L10 | Retrait simulé | GSO-T21 + l10-cleanup (retrait simulé) | Satisfait et testé |
| GSO-REQ-149 | L10 | Ressources éphémères | l10-cleanup (zéro résidu) + GSO-T15 §10 | Satisfait et testé |
| GSO-REQ-150 | L10 | Matrice complète | docs/COMPLIANCE-MATRIX.md + docs/TEST-RESULTS.md | Satisfait |
| GSO-REQ-151 | L0 | Versions séparées | docs/VERSIONING.md | Établi / documenté |
| GSO-REQ-152 | L0 | Release identifiable | docs/VERSIONING.md | Établi / documenté |
| GSO-REQ-153 | L0 | Une seule référence du rôle | requirements.yml (source unique de vérité) + GSO-T04 | Satisfait et testé |
| GSO-REQ-154 | L1 | Version humaine obligatoire | GSO-T06 (version obligatoire, jamais latest) | Satisfait et testé |
| GSO-REQ-155 | L0 | Runtime transitif | docs/VERSIONING.md | Établi / documenté |
| GSO-REQ-156 | L0 | Historique attribuable | docs/VERSIONING.md | Établi / documenté |
| GSO-REQ-157 | L0 | Changelog borné | CHANGELOG.md (versions du dépôt) + REGISTRY-SCHEMA.md (versions du parc) | Satisfait |
| GSO-REQ-158 | L11 | Tag sur SHA validé | lot L11 — acceptation & release, non démarré | Non encore démontré (L11) |
| GSO-REQ-159 | L11 | Release et exploitation séparées | lot L11 — acceptation & release, non démarré | Non encore démontré (L11) |
| GSO-REQ-160 | L9 | Source préservée | MIGRATION.md §0/§12 — non-destruction ; exécution réelle à démontrer | Établi / documenté |
| GSO-REQ-161 | L9 | Sauvegarde vérifiée | MIGRATION.md §3 — preuve documentaire (non automatisable par contrat) | Établi / documenté |
| GSO-REQ-162 | L9 | Cartographie sans divulgation | l9-migration-doc-guard (présence) ; non-divulgation réelle à démontrer | Établi / documenté |
| GSO-REQ-163 | L9 | Harnais avant données réelles | l9-migration-doc-guard + harnais vert | Satisfait et testé |
| GSO-REQ-164 | L9 | Traduction explicite | l9-migration-doc-guard (cartographie exhaustive + champ non mappé) | Satisfait et testé |
| GSO-REQ-165 | L9 | Pas de secret en clair sur disque | MIGRATION.md §7 ; exécution réelle à démontrer | Établi / documenté |
| GSO-REQ-166 | L9 | Destination vérifiée | l9-migration-doc-guard (cible synthétique valide contre gso_validate) | Satisfait et testé |
| GSO-REQ-167 | L9 | Une migration à la fois | MIGRATION.md §6 ; séquencement réel à démontrer | Établi / documenté |
| GSO-REQ-168 | L9 | Migration sans upgrade implicite | MIGRATION.md §8 ; exécution réelle à démontrer | Établi / documenté |
| GSO-REQ-169 | L9 | Nettoyage séparé | MIGRATION.md §11 ; exécution réelle à démontrer | Établi / documenté |
| GSO-REQ-170 | L9 | Autonomie finale | l9-migration-doc-guard (aucune lecture de l'ancien dépôt) + GSO-T23 | Satisfait et testé |
| GSO-REQ-171 | L9 | Preuves de migration | MIGRATION.md §6/§10 — verdicts par site à produire lors d'une migration | Établi / documenté |
| GSO-REQ-172 | L9 | Retour sans mutation applicative | l9-migration-doc-guard (retour arrière non destructif, sans script) | Établi / documenté |
| GSO-REQ-173 | L8 | Ajout en trois emplacements | docs/OPERATIONS.md — ajout en trois emplacements (structure L1/L2) | Établi / documenté |
| GSO-REQ-174 | L8 | Préconditions complètes | docs/OPERATIONS.md — préconditions ; refus par GSO-T06 / préflight | Satisfait |
| GSO-REQ-175 | L8 | Première cible unique | docs/OPERATIONS.md — mécanisme = sélecteur L3 (GSO-T09..T11) | Satisfait |
| GSO-REQ-176 | L8 | Chemins structurants protégés | docs/OPERATIONS.md + MIGRATION.md §5 — contrôle de migration = L9 | Établi / documenté |
| GSO-REQ-177 | L8 | Rotation explicitement opérée | docs/OPERATIONS.md — vault ≠ rotation Grav | Établi / documenté |
| GSO-REQ-178 | L8 | Retrait cohérent | GSO-T21 (retrait cohérent, même changement Git) | Satisfait et testé |
| GSO-REQ-179 | L8 | Hyperviseur hors orchestration | GSO-T21 (aucun appel d'hyperviseur) | Satisfait et testé |
| GSO-REQ-180 | L8 | Même identité à la réactivation | GSO-T22 (réactivation à identité constante) | Satisfait et testé |
| GSO-REQ-181 | L8 | Historique explicite | GSO-T22 (9 cas append-only) + l8-history-append-only | Satisfait et testé |
| GSO-REQ-182 | L8 | Destruction hors procédure | GSO-T21 + l7-persistence-guard (aucune destruction définitive) | Satisfait et testé |
| GSO-REQ-183 | L11 | Deux décisions humaines | lot L11 — acceptation & release, non démarré | Non encore démontré (L11) |
| GSO-REQ-184 | L11 | Audit avant construction | lot L11 — acceptation & release, non démarré | Non encore démontré (L11) |
| GSO-REQ-185 | L11 | Squelette non opérationnel par défaut | lot L11 — acceptation & release, non démarré | Non encore démontré (L11) |
| GSO-REQ-186 | L11 | Zéro test critique manquant | lot L11 — acceptation & release, non démarré | Non encore démontré (L11) |
| GSO-REQ-187 | L11 | Échec d'un garde-fou bloquant | lot L11 — acceptation & release, non démarré | Non encore démontré (L11) |
| GSO-REQ-188 | L11 | Migration distincte de la construction | lot L11 — acceptation & release, non démarré | Non encore démontré (L11) |
| GSO-REQ-189 | L11 | Documentation exécutable | lot L11 — acceptation & release, non démarré | Non encore démontré (L11) |
| GSO-REQ-190 | L11 | Matrice exhaustive | lot L11 — acceptation & release, non démarré | Non encore démontré (L11) |
| GSO-REQ-191 | L11 | Audit non exécutoire | lot L11 — acceptation & release, non démarré | Non encore démontré (L11) |
| GSO-REQ-192 | L11 | Publication séparée | lot L11 — acceptation & release, non démarré | Non encore démontré (L11) |
| GSO-REQ-193 | L0 | Différé non implicite | docs/GOVERNANCE.md | Établi / documenté |
| GSO-REQ-194 | L0 | Décisions protégées | docs/GOVERNANCE.md | Établi / documenté |
| GSO-REQ-195 | L0 | Amendement avant code | docs/GOVERNANCE.md | Établi / documenté |
| GSO-REQ-196 | L0 | Identifiants immuables | docs/GOVERNANCE.md | Établi / documenté |
| GSO-REQ-197 | L0 | Exigence prouvable | docs/GOVERNANCE.md | Établi / documenté |
| GSO-REQ-198 | L0 | Version du contrat | docs/CONTRAT-ARCHITECTURAL.md — copie à l'octet près conservée | Satisfait |
| GSO-REQ-199 | L0 | Autorisations distinctes | gates d'autorisation humains (rapports 09–19) | Établi / documenté |
| GSO-REQ-200 | L0 | Mutation bornée au dépôt | docs/GOVERNANCE.md | Établi / documenté |
| GSO-REQ-201 | L0 | Évolution fondée sur les faits | docs/GOVERNANCE.md | Établi / documenté |
| GSO-REQ-202 | L11 | Approbation explicite | lot L11 — acceptation & release, non démarré | Non encore démontré (L11) |
| GSO-REQ-203 | L2 | Secrets applicatifs par site | GSO-T07, GSO-T13 (name+content, jamais src) | Satisfait et testé |
| GSO-REQ-204 | L4 | Cohérence structurelle vérifiée avant déploiement | GSO-T07 + GSO-T14 + préflight structurel de deploy-site.yml | Satisfait et testé |
