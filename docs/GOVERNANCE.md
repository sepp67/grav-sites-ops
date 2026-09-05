# Gouvernance

## Le contrat fait foi

Toute implémentation de `grav-sites-ops` est conforme uniquement si elle
satisfait les exigences `GSO-REQ-*` du contrat architectural, dont la version
en vigueur (`v0.5.0`) est conservée dans
[`CONTRAT-ARCHITECTURAL.md`](CONTRAT-ARCHITECTURAL.md).

## Conservation des versions du contrat (GSO-REQ-198)

Chaque version approuvée du contrat DOIT être identifiable et conservée dans
l'historique du dépôt :

- `docs/CONTRAT-ARCHITECTURAL.md` contient **toujours** la dernière version
  approuvée, à l'octet près (aucune reformulation, aucun retrait de section).
- Le commit d'intégration référence la version, son statut et le condensé
  SHA-256 de la source approuvée ; l'égalité des condensés source / copie est
  vérifiée avant le commit.
- Les versions antérieures restent accessibles via l'historique Git de ce
  fichier (`git log --follow -- docs/CONTRAT-ARCHITECTURAL.md`). Une version
  n'est jamais écrasée sans qu'un commit distinct ne trace la transition.
- Une nouvelle version n'est intégrée qu'après approbation humaine explicite
  (gate distinct, GSO-REQ-199).

## Gates séparés

Les autorisations d'**audit**, de **construction**, d'**intégration**, de
**publication** et d'**exploitation** restent distinctes (GSO-REQ-199). Une
autorisation accordée pour un gate n'en implique aucun autre. En particulier :

- l'approbation du contrat n'autorise pas la construction ;
- l'autorisation de construction d'un lot n'autorise pas le lot suivant ;
- la construction locale n'autorise ni dépôt distant, ni `push`, ni release ;
- rien de ce qui précède n'autorise le peuplement de `inventories/production/`,
  la création d'un vault opérationnel ou une connexion à une VM.

## Amendement du contrat

- Une évolution qui modifie un invariant ou introduit une rupture
  architecturale DOIT être arbitrée et documentée **avant** toute modification
  de code (GSO-REQ-047, GSO-REQ-195).
- Une décision différée (contrat §23.1) NE DOIT PAS être implémentée avant
  arbitrage et amendement (GSO-REQ-193).
- Une implémentation conforme NE DOIT PAS contredire une décision actée
  (§23.2) sous prétexte de flexibilité technique (GSO-REQ-194).

## Traçabilité des écarts

Toute dérogation à une exigence normative DOIT être documentée, justifiée et
soumise à un arbitrage humain explicite (GSO-REQ-002). Les écarts constatés
pendant la construction sont consignés dans le rapport d'exécution du lot
concerné.

## Identifiants

Les identifiants `GSO-REQ-*` et `GSO-T*` sont immuables : un identifiant
publié n'est jamais réattribué (GSO-REQ-196). Une nouvelle obligation critique
indique toujours comment sa conformité est vérifiée (GSO-REQ-197).

## Bornage des mutations

Une tâche portant sur `grav-sites-ops` ne modifie jamais `ansible-role-grav-site`,
un dépôt applicatif, `grav-runtime` ou le `control-repository` (GSO-REQ-200),
et aucune opération Ansible ne modifie un dépôt distant ou un registre
d'images (GSO-REQ-108).
