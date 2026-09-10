#!/usr/bin/env python3
"""Génère (ou vérifie) `docs/COMPLIANCE-MATRIX.md` — les 204 exigences GSO-REQ.

Lot L10 (GSO-REQ-150). Read-only : lit le contrat vendu
(`docs/CONTRAT-ARCHITECTURAL.md`) pour les intitulés, applique la table de
correspondance lot ↔ exigence du préflight et une table de preuves/statuts
tenue à la main. N'écrit RIEN de lui-même : la sortie va sur stdout
(`make matrix` la redirige).

    gso_compliance.py            -> écrit la matrice complète sur stdout
    gso_compliance.py --check    -> compare à docs/COMPLIANCE-MATRIX.md,
                                    code ≠ 0 en cas d'écart
"""
from __future__ import annotations

import os
import re
import sys
from collections import Counter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
CONTRACT = os.path.join(ROOT, "docs", "CONTRAT-ARCHITECTURAL.md")
MATRIX = os.path.join(ROOT, "docs", "COMPLIANCE-MATRIX.md")

# --- correspondance lot ↔ exigence (préflight §5, recomptage final : 204) ---
_LOTS = {
    "L0": "001,002,004,009,014,025,031,032,034,043,045,047,059,060,067,099,103,108,127,129,130,131,132,134,135,151,152,153,155,156,157,193,194,195,196,197,198,199,200,201",
    "L1": "005,006,007,008,010,011,012,013,020,021,036,037,041,048,049,050,051,055,065,068,100,128,154",
    "L2": "022,023,024,042,061,062,069,071,098,203",
    "L3": "016,017,018,026,038,053,056,057,083,084,085,086,093,094,095,096,107,138",
    "L4": "003,015,019,035,054,063,064,066,072,081,082,087,091,092,097,101,105,106,111,204",
    "L5": "088,089",
    "L6": "090,104,118,119,120,121,122,123,124,125,126",
    "L7": "033,039,040,075,076,077,078,079,102,109,110,112,113,114,115,116,117",
    "L8": "027,028,029,044,052,073,173,174,175,176,177,178,179,180,181,182",
    "L9": "070,133,160,161,162,163,164,165,166,167,168,169,170,171,172",
    "L10": "030,046,058,074,080,136,137,139,140,141,142,143,144,145,146,147,148,149,150",
    "L11": "158,159,183,184,185,186,187,188,189,190,191,192,202",
}
LOT: dict[str, str] = {}
for _lot, _nums in _LOTS.items():
    for _n in _nums.split(","):
        LOT[f"{int(_n):03d}"] = _lot

# preuve principale + statut (T testé / S satisfait / D documenté / P partiel /
# N non démontré). Défaut : L11 -> N ; sinon -> S « couvert par le lot ».
ENTRY: dict[str, tuple[str, str]] = {
    "001": ("docs/GOVERNANCE.md (contrat approuvé avant construction)", "D"),
    "002": ("docs/GOVERNANCE.md + rapports d'exécution datés", "D"),
    "004": ("GSO-T01, GSO-T02, GSO-T23", "T"),
    "009": ("GSO-T23", "T"),
    "014": ("GSO-T04 + requirements.yml (tag épinglé)", "T"),
    "025": ("scripts set -euo pipefail ; gso_validate _finish → code ≠ 0", "S"),
    "031": ("GSO-T24 + .gitignore", "T"), "032": ("GSO-T24 + .gitignore", "T"),
    "034": ("docs/ARCHITECTURE.md (ordre de préséance)", "D"),
    "043": ("GSO-T24 (aucun secret suivi)", "T"),
    "045": ("ansible.cfg (aucun inventaire par défaut) + GSO-T08", "T"),
    "047": ("docs/GOVERNANCE.md (procédure d'amendement)", "D"),
    "059": ("docs/ARCHITECTURE.md", "D"), "060": ("README.md + docs/ARCHITECTURE.md", "D"),
    "067": ("docs/VAULT-SCHEMA.md", "D"),
    "099": ("GSO-T24 (aucun chemin de workstation)", "T"),
    "103": ("GSO-T04", "T"),
    "108": ("l4-ci-functional-contract + l10-ci-blocking", "T"),
    "127": (".gitignore + GSO-T24", "T"),
    "129": ("préflight §3 : playbooks/_shared factorise sans rôle d'orchestration ; revue", "S"),
    "130": ("gso_validate.py / gso_lifecycle.py strictement read-only", "S"),
    "131": ("CHANGELOG.md tenu à chaque lot", "S"),
    "132": ("GSO-T24 (catégories sensibles non suivies)", "T"),
    "134": ("docs/VERSIONING.md", "D"), "135": ("docs/VERSIONING.md", "D"),
    "151": ("docs/VERSIONING.md", "D"), "152": ("docs/VERSIONING.md", "D"),
    "153": ("requirements.yml (source unique de vérité) + GSO-T04", "T"),
    "155": ("docs/VERSIONING.md", "D"), "156": ("docs/VERSIONING.md", "D"),
    "157": ("CHANGELOG.md (versions du dépôt) + REGISTRY-SCHEMA.md (versions du parc)", "S"),
    "193": ("docs/GOVERNANCE.md", "D"), "194": ("docs/GOVERNANCE.md", "D"), "195": ("docs/GOVERNANCE.md", "D"),
    "196": ("docs/GOVERNANCE.md", "D"), "197": ("docs/GOVERNANCE.md", "D"),
    "198": ("docs/CONTRAT-ARCHITECTURAL.md — copie à l'octet près conservée", "S"),
    "199": ("gates d'autorisation humains (rapports 09–19)", "D"),
    "200": ("docs/GOVERNANCE.md", "D"), "201": ("docs/GOVERNANCE.md", "D"),
    "005": ("GSO-T05", "T"), "006": ("GSO-T05, GSO-T07", "T"),
    "007": ("REGISTRY-SCHEMA.md + GSO-T06", "S"), "008": ("GSO-T06 (jointure par inventory_hostname)", "T"),
    "010": ("GSO-T06", "T"), "011": ("GSO-T06", "T"), "012": ("GSO-T06", "T"), "013": ("GSO-T06", "T"),
    "020": ("GSO-T06, GSO-T13", "T"), "021": ("GSO-T06, GSO-T13", "T"),
    "036": ("GSO-T06 (fixture négative)", "T"), "037": ("GSO-T06", "T"),
    "041": ("requirements.yml (community.docker bornée) + GSO-T04", "T"),
    "048": ("GSO-T06", "T"), "049": ("GSO-T06", "T"), "050": ("GSO-T06", "T"), "051": ("GSO-T06", "T"),
    "055": ("GSO-T06", "T"), "065": ("gso_validate registry (bind_address IPv4) + GSO-T06", "T"),
    "068": ("GSO-T06 (unicité)", "T"), "100": ("REGISTRY-SCHEMA.md", "D"),
    "128": ("REGISTRY-SCHEMA.md + GSO-T06", "S"), "154": ("GSO-T06 (version obligatoire, jamais latest)", "T"),
    "022": ("GSO-T07", "T"), "023": (".gitignore + GSO-T24", "T"),
    "024": ("GSO-T14, GSO-T24, l10-multisite-isolation", "T"), "042": ("GSO-T14, GSO-T24", "T"),
    "061": ("GSO-T07, GSO-T13", "T"), "062": ("GSO-T07, GSO-T13 (tri-state)", "T"),
    "069": ("GSO-T24 (garde Git du vault)", "T"), "071": ("GSO-T13/T14 (aucune rotation simulée)", "T"),
    "098": ("GSO-T24 (ré-inclusion nommée unique)", "T"), "203": ("GSO-T07, GSO-T13 (name+content, jamais src)", "T"),
    "016": ("GSO-T13 (assertion --limit) + _shared/mutate.yml", "T"), "017": ("GSO-T10, GSO-T13", "T"),
    "018": ("l5-action-closed + GSO-T13", "T"), "026": ("GSO-T08..T12 (échoue fermé)", "T"),
    "038": ("GSO-T11, GSO-T12", "T"), "053": ("GSO-T08 (inventaire imposé)", "T"),
    "056": ("GSO-T11 (sur le validateur)", "T"), "057": ("GSO-T10, GSO-T13", "T"),
    "083": ("GSO-T09", "T"), "084": ("GSO-T10 (SITE littéral)", "T"),
    "085": ("GSO-T11 + GSO-T13 (préflight à deux niveaux)", "T"), "086": ("GSO-T11", "T"),
    "093": ("GSO-T11 (codes ≠ 0) + l5-restart-stop", "T"), "094": ("GSO-T10, GSO-T13", "T"),
    "095": ("GSO-T08..T12", "T"), "096": ("l4-concurrency-lock + l5-restart-stop", "T"),
    "107": ("GSO-T12 (aucun contact après refus)", "T"), "138": ("GSO-T09, GSO-T10, GSO-T11", "T"),
    "003": ("GSO-T15 (déploiement LAN local)", "T"), "015": ("GSO-T13 (traduction exacte)", "T"),
    "019": ("GSO-T20 + l7-persistence-guard (rôle non copié)", "T"), "035": ("GSO-T13, GSO-T16", "T"),
    "054": ("GSO-T13", "T"), "063": ("GSO-T13/T14 (par inventory_hostname)", "T"),
    "064": ("GSO-T15 (vrai rôle v2.0.0, chemin réel)", "T"), "066": ("GSO-T13", "T"),
    "072": ("GSO-T13 (aucune valeur globale)", "T"), "081": ("l5-action-closed (une intention par playbook)", "T"),
    "082": ("l5-action-closed + _shared/mutate.yml (jamais global)", "T"),
    "087": ("GSO-T13, GSO-T15 (une invocation)", "T"),
    "091": ("l10-check-mode (comportement, doublure) + docs/OPERATIONS.md — --check vs vrai rôle non exercé", "P"),
    "092": ("GSO-T14, l10-multisite-isolation (no_log sous -vv)", "T"),
    "097": ("deploy-site.yml become:false + GSO-T15", "S"), "101": ("GSO-T14 (no_log)", "T"),
    "105": ("l7-persistence-guard + docs/OPERATIONS.md (jamais push/tag)", "S"),
    "106": ("l7-persistence-guard", "S"), "111": ("GSO-T13 (force_pull non global)", "T"),
    "204": ("GSO-T07 + GSO-T14 + préflight structurel de deploy-site.yml", "T"),
    "088": ("l5-restart-stop (version/digest inchangés)", "T"),
    "089": ("l5-restart-stop + l5-action-closed (aucune suppression)", "T"),
    "090": ("GSO-T20 + l7-persistence-guard (aucun include_role)", "T"),
    "104": ("GSO-T20 (check-all ≠ mutation)", "T"), "118": ("GSO-T19", "T"),
    "119": ("GSO-T19, GSO-T20 (état du rôle en lecture)", "T"), "120": ("GSO-T19 (santé réelle)", "T"),
    "121": ("GSO-T19 (8 catégories, STOPPED relatif)", "T"), "122": ("GSO-T19, GSO-T20 (aucun appel deploy)", "T"),
    "123": ("GSO-T19 (rapport sans secret)", "T"), "124": ("GSO-T19/T20 (gather_facts:false)", "T"),
    "125": ("GSO-T20 (cohérence sans VM)", "T"),
    "126": ("l7-persistence-guard + gso_lifecycle read-only (aucun retour Git auto)", "T"),
    "033": ("l7-persistence-guard (aucune synchro implicite)", "T"), "039": ("GSO-T07, GSO-T24", "T"),
    "040": ("l7-persistence-guard + GSO-T17/T18", "T"),
    "075": ("GSO-T17/T18 (quatre ensembles) + l7-persistence-guard", "T"),
    "076": ("GSO-T18 + l7-persistence-guard", "T"), "077": ("l7-persistence-guard (aucune synchronisation de contenu)", "T"),
    "078": ("l7-persistence-guard (versant négatif) + docs — sauvegarde réelle hors périmètre", "P"),
    "079": ("l7-persistence-guard (aucune primitive de destruction de volume ou de répertoire)", "T"),
    "102": ("l7-persistence-guard (garde CI destructif)", "T"),
    "109": ("GSO-T13 + l7-persistence-guard (registre seul)", "T"),
    "110": ("GSO-T13 (digest transmis, jamais hybride)", "T"), "112": ("GSO-T18 (rollback traçable Git)", "T"),
    "113": ("GSO-T18 + l7-persistence-guard (pas de rollback des données)", "T"),
    "114": ("l7-persistence-guard (aucun rollback automatique)", "T"),
    "115": ("docs/OPERATIONS.md — mécanisme = requirements.yml séparé (L0)", "D"),
    "116": ("mécanisme = make check (L6, GSO-T19) — procédure documentée", "S"),
    "117": ("l7-persistence-guard + GSO-T17 (journal du rôle non réécrit)", "T"),
    "027": ("GSO-T21 (retrait non destructif)", "T"),
    "028": ("GSO-T21 + GSO-T24 (registre sans secret)", "T"),
    "029": ("GSO-T21 + l7-persistence-guard (aucun playbook destructif)", "T"),
    "044": ("GSO-T21 (archivage avant oubli, même changement Git)", "T"),
    "052": ("GSO-T22 (disjonction stricte)", "T"), "073": ("GSO-T22 (secrets retirés hors ensemble actif)", "T"),
    "173": ("docs/OPERATIONS.md — ajout en trois emplacements (structure L1/L2)", "D"),
    "174": ("docs/OPERATIONS.md — préconditions ; refus par GSO-T06 / préflight", "S"),
    "175": ("docs/OPERATIONS.md — mécanisme = sélecteur L3 (GSO-T09..T11)", "S"),
    "176": ("docs/OPERATIONS.md + MIGRATION.md §5 — contrôle de migration = L9", "D"),
    "177": ("docs/OPERATIONS.md — vault ≠ rotation Grav", "D"),
    "178": ("GSO-T21 (retrait cohérent, même changement Git)", "T"),
    "179": ("GSO-T21 (aucun appel d'hyperviseur)", "T"),
    "180": ("GSO-T22 (réactivation à identité constante)", "T"),
    "181": ("GSO-T22 (9 cas append-only) + l8-history-append-only", "T"),
    "182": ("GSO-T21 + l7-persistence-guard (aucune destruction définitive)", "T"),
    "070": ("MIGRATION.md §3 — preuve documentaire (non automatisable par contrat)", "D"),
    "133": ("l9-migration-doc-guard (fixtures ancien ≠ nouveau)", "T"),
    "160": ("MIGRATION.md §0/§12 — non-destruction ; exécution réelle à démontrer", "D"),
    "161": ("MIGRATION.md §3 — preuve documentaire (non automatisable par contrat)", "D"),
    "162": ("l9-migration-doc-guard (présence) ; non-divulgation réelle à démontrer", "D"),
    "163": ("l9-migration-doc-guard + harnais vert", "T"),
    "164": ("l9-migration-doc-guard (cartographie exhaustive + champ non mappé)", "T"),
    "165": ("MIGRATION.md §7 ; exécution réelle à démontrer", "D"),
    "166": ("l9-migration-doc-guard (cible synthétique valide contre gso_validate)", "T"),
    "167": ("MIGRATION.md §6 ; séquencement réel à démontrer", "D"),
    "168": ("MIGRATION.md §8 ; exécution réelle à démontrer", "D"),
    "169": ("MIGRATION.md §11 ; exécution réelle à démontrer", "D"),
    "170": ("l9-migration-doc-guard (aucune lecture de l'ancien dépôt) + GSO-T23", "T"),
    "171": ("MIGRATION.md §6/§10 — verdicts par site à produire lors d'une migration", "D"),
    "172": ("l9-migration-doc-guard (retour arrière non destructif, sans script)", "D"),
    "030": ("l10-ci-blocking", "T"), "046": ("l10-ci-blocking", "T"), "058": ("l10-ci-blocking", "T"),
    "074": ("l10-ci-blocking (GSO-T24 dans la CI)", "T"),
    "080": ("GSO-T17/T18 (scénario) + l7-persistence-guard (statique)", "T"),
    "136": ("docs/TEST-RESULTS.md (exécutions observées)", "T"),
    "137": ("cas négatifs : GSO-T09..T12, GSO-T22, l7/l8/l9 guards", "T"),
    "139": ("l10-ci-blocking (aucun test n'exige le vault de production)", "T"),
    "140": ("GSO-T03/T04 (même référence épinglée que l'installation documentée)", "T"),
    "141": ("GSO-T15 (localhost éphémère) + l4-ci-functional-contract", "T"),
    "142": ("l10-multisite-isolation + GSO-T16 + GSO-T14", "T"),
    "143": ("GSO-T17/T18 (pages/accounts/data/images séparés)", "T"),
    "144": ("GSO-T19/T20 + l7-persistence-guard (aucun fichier/conteneur modifié)", "T"),
    "145": ("l10-ci-blocking (job conformance ; aucun continue-on-error)", "T"),
    "146": ("l10-ci-blocking (python 3.12, ansible-core >=2.17,<2.19)", "T"),
    "147": ("docs/TEST-RESULTS.md + l10-ci-blocking (CI distante non observée)", "T"),
    "148": ("GSO-T21 + l10-cleanup (retrait simulé)", "T"),
    "149": ("l10-cleanup (zéro résidu) + GSO-T15 §10", "T"),
    "150": ("docs/COMPLIANCE-MATRIX.md + docs/TEST-RESULTS.md", "S"),
    # --- L11 (acceptation) : revues documentaires exécutées + 3 bloquées ---
    "158": ("docs/ACCEPTANCE.md §3 — commande de tag et SHA candidat préparés ; CI distante verte requise (non exécutée)", "N"),
    "159": ("l11-acceptance-guards (ci.yml sans déclencheur release/tag ; aucune étape de déploiement en CI)", "D"),
    "183": ("l11-acceptance-guards + GSO-T23 + REGISTRY-SCHEMA.md (aucune notion de publication dans le registre)", "D"),
    "184": ("audit-grav-sites-ops/01..08 antérieurs au premier commit de construction ; docs/GOVERNANCE.md", "D"),
    "185": ("l11-acceptance-guards (premier commit 4a4eab0 = README.md seul, aucune capacité de déploiement)", "D"),
    "186": ("revue de matrice — aucun TEST GAP : sélection GSO-T08..T12, secrets GSO-T07/T14/T24, persistance GSO-T17/T18, rôle GSO-T13/T15, non-contact GSO-T12/T23", "D"),
    "187": ("l11-acceptance-guards + docs/ACCEPTANCE.md §4 (gate de release conditionné à la CI bloquante — job conformance) ; observation différée à la CI distante", "D"),
    "188": ("conformité du dépôt établie sur fixtures (L9 + matrice) ; conformité opérationnelle par site réel différée (migration autorisée séparément)", "N"),
    "189": ("l11-acceptance-guards (21 cibles make documentees = 21 reelles ; exemples non executables signales)", "D"),
    "190": ("08-preflight-construction.md §5 (204 cartographiees) + docs/COMPLIANCE-MATRIX.md (make matrix-check)", "D"),
    "191": ("audit-grav-sites-ops/ n'a produit aucun commit ; chaque lot L0-L11 autorise separement avant modification", "D"),
    "192": ("l11-acceptance-guards (main ahead de origin/main jamais pousse ; aucune branche ni tag pousse ; aucune automatisation push/tag/release)", "N"),
    "202": ("contrat v0.5.0 §23.10 — approbation humaine explicite du 2026-09-05 ; README + docs/GOVERNANCE.md", "D"),
}

LABEL = {
    "T": "Satisfait et testé", "S": "Satisfait", "D": "Établi / documenté",
    "P": "Partiel", "N": "Non encore démontré (L11)",
}


def _titles() -> dict[str, str]:
    txt = open(CONTRACT, encoding="utf-8").read()
    return {m.group(1): m.group(2).strip()
            for m in re.finditer(r"\*\*GSO-REQ-(\d{3})\s*[—-]\s*([^.*]+?)\.\*\*", txt)}


def render() -> str:
    title = _titles()
    proof: dict[str, str] = {}
    status: dict[str, str] = {}
    for n, lot in LOT.items():
        if n in ENTRY:
            proof[n], status[n] = ENTRY[n]
        elif lot == "L11":
            proof[n], status[n] = ("lot L11 — acceptation & release, non démarré", "N")
        else:
            proof[n], status[n] = (f"couvert par le lot {lot}", "S")

    c = Counter(status.values())
    out: list[str] = []
    w = out.append
    w("# Matrice de conformité — 204 exigences `GSO-REQ`\n")
    w("Résumé normatif : contrat architectural `v0.5.0` (`docs/CONTRAT-ARCHITECTURAL.md`).")
    w("En cas de divergence, le contrat fait foi. Livré et tenu à jour par le **lot L10**")
    w("(GSO-REQ-150) ; les 13 exigences L11 sont évaluées par le **lot L11** (voir")
    w("[`ACCEPTANCE.md`](ACCEPTANCE.md)). Régénérable par `make matrix`, vérifiable par `make matrix-check`.\n")
    w("Cinq niveaux, **distincts** :\n")
    w("- **Satisfait et testé** — un `GSO-T01`–`GSO-T24` ou un garde-fou non numéroté")
    w("  (`l4-`…`l10-`) exerce l'exigence ; exécution consignée dans [`TEST-RESULTS.md`](TEST-RESULTS.md).")
    w("- **Satisfait** — mécanisme en place, couvert **structurellement ou indirectement**")
    w("  (p. ex. par `GSO-T01`/`GSO-T02`/`GSO-T06`), sans test dédié.")
    w("- **Établi / documenté** — preuve **documentaire** : soit le contrat la déclare non")
    w("  vérifiable par un test automatisé (GSO-REQ-070, 161), soit c'est une règle de")
    w("  gouvernance / de procédure.")
    w("- **Partiel** — une partie testée, une autre **différée** à une exécution réelle")
    w("  autorisée (GSO-REQ-091, 078).")
    w("- **Non encore démontré (L11)** — après la revue d'acceptation L11, il ne reste")
    w("  que ce qui exige une action **externe ou humaine non accordée** : un `push`, une")
    w("  CI distante verte, une migration réelle (GSO-REQ-158, 188, 192).\n")
    w("Les preuves issues d'un **lot antérieur** ou du **rôle** `sepp67.grav_site` sont")
    w("**attribuées à leur véritable mécanisme**, pas à L10 ni à L11.\n")
    w("---\n")
    w("## Synthèse\n")
    w("| Statut | Nombre |")
    w("|---|---|")
    for k in ("T", "S", "D", "P", "N"):
        w(f"| {LABEL[k]} | {c.get(k, 0)} |")
    w(f"| **Total** | **{sum(c.values())}** |\n")
    adressed = c["T"] + c["S"] + c["D"] + c["P"]
    w(f"**{adressed} / 204** exigences sont adressées par les lots L0–L11 (aucune en")
    w(f"échec). Les **{c['N']}** restantes — **GSO-REQ-158, 188, 192** — sont **non")
    w("démontrées** : elles exigent un `push`, une CI distante verte ou une migration")
    w("réelle, autorisations **distinctes non accordées**. La **construction locale est")
    w("acceptée** ; publication, release et migration restent **bloquées** — détail et")
    w("conditions dans [`ACCEPTANCE.md`](ACCEPTANCE.md) (contrat §22, GSO-REQ-150).\n")
    w("## Matrice détaillée (204 exigences)\n")
    w("| # | Lot | Intitulé | Preuve principale | Statut |")
    w("|---|---|---|---|---|")
    for n in sorted(LOT):
        w(f"| GSO-REQ-{n} | {LOT[n]} | {title[n].replace('|', '/')} | {proof[n]} | {LABEL[status[n]]} |")
    return "\n".join(out) + "\n"


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    text = render()
    if "--check" in argv:
        try:
            on_disk = open(MATRIX, encoding="utf-8").read()
        except OSError:
            print("FAIL  docs/COMPLIANCE-MATRIX.md absent", file=sys.stderr)
            return 1
        rows = on_disk.count("\n| GSO-REQ-")
        if rows != 204:
            print(f"FAIL  docs/COMPLIANCE-MATRIX.md : {rows} lignes d'exigence (attendu 204)", file=sys.stderr)
            return 1
        if on_disk.strip() != text.strip():
            print("FAIL  docs/COMPLIANCE-MATRIX.md n'est pas à jour — lancer `make matrix`", file=sys.stderr)
            return 1
        print("OK    docs/COMPLIANCE-MATRIX.md : 204 exigences, à jour")
        return 0
    sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
