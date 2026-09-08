#!/usr/bin/env python3
"""Validation du CYCLE DE VIE d'un projet — registres retiré et réactivé.

Lot L8. Fichier de validation **strictement en lecture seule** (GSO-REQ-026,
095, 107) : ne charge rien dans Ansible, ne modifie aucun fichier, ne contacte
aucune machine, n'ouvre aucun vault chiffré. Échoue fermé : tout écart → code
non nul.

Il vérifie exclusivement des fichiers DOCUMENTAIRES, passés en argument par
chemin explicite (jamais déduits du cwd) :

    gso_lifecycle.py \
        --retired      registry/retired-sites.yml \
        --reactivated  registry/reactivated-sites.yml \
        [--registry    <grav_sites.yml>]   (active la disjonction registre)
        [--vault       <vault.yml>]        (active la disjonction vault)

Les primitives partagées (`Reporter`, `load_yaml`, `SITE_RE`, `is_doc_addr`)
sont importées de `gso_validate.py`, qui n'est PAS modifié par ce lot.

Aucun outil livré à l'opérateur n'applique une transformation de cycle de vie :
le retrait et la réactivation restent des opérations Git manuelles, guidées par
`docs/OPERATIONS.md` et vérifiées APRÈS COUP par ce validateur (préflight §5.1).
"""

from __future__ import annotations

import argparse
import datetime as _dt
import os
import re
import sys

_HERE = os.path.dirname(os.path.realpath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

from gso_validate import Reporter, SITE_RE, is_doc_addr, load_yaml  # noqa: E402

# --------------------------------------------------------------------------- #
# Schéma normatif (contrat v0.5.0 §7.7)
# --------------------------------------------------------------------------- #
RETIRED_ROOT = "retired_grav_sites"
REACTIVATED_ROOT = "reactivated_sites"

RETIRED_MANDATORY = (
    "project_name", "retired_at", "former_inventory_host", "former_ansible_host",
    "former_base_directory", "container_name", "last_deployment", "preservation",
    "reason",
)
RETIRED_ALLOWED = set(RETIRED_MANDATORY)

LAST_DEPLOYMENT_MANDATORY = ("image", "version", "digest")
LAST_DEPLOYMENT_ALLOWED = set(LAST_DEPLOYMENT_MANDATORY)

PRESERVATION_MANDATORY = (
    "vm_status", "vm_preserved", "persistent_data_preserved",
    "secrets_archived_in_vault",
)
PRESERVATION_ALLOWED = set(PRESERVATION_MANDATORY)
VM_STATUS_VALUES = {"stopped", "running", "unknown"}

REACT_EVENT_MANDATORY = ("reactivated_at", "project_name", "former_inventory_host",
                         "previous_retirement")
REACT_EVENT_ALLOWED = set(REACT_EVENT_MANDATORY)
PREV_RETIREMENT_MANDATORY = ("retired_at", "reason")
# `previous_retirement` PEUT porter une copie complète de la dernière fiche
# retirée (contrat §7.7) : on tolère tout champ valide d'une fiche retirée.
PREV_RETIREMENT_ALLOWED = set(PREV_RETIREMENT_MANDATORY) | RETIRED_ALLOWED

_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
# Indices de secret : une clé qui n'aurait rien à faire dans un fichier
# documentaire non secret (GSO-REQ-028, GSO-REQ-073, §7.7). N'est retenue
# comme violation que si sa VALEUR est une chaîne non vide (un vrai secret) —
# un simple drapeau booléen du schéma (`secrets_archived_in_vault: true`)
# n'est pas un secret.
_SECRETISH_KEY_RE = re.compile(
    r"(?i)(password|passwd|token|api[_-]?key|private[_-]?key|"
    r"credential|bearer|admin_pass|(^|_)secret(s)?($|_))"
)
# Champs du schéma qui contiennent un mot-clé mais NE sont pas des secrets.
_SECRETISH_KEY_ALLOW = {"secrets_archived_in_vault"}
# Chemins locaux réels interdits dans un fichier documentaire (cohérent
# GSO-T24). Motif assemblé à l'exécution pour que ce fichier ne se signale
# pas lui-même à GSO-T24.
_LOCAL_PATH_RE = re.compile(
    "(^|[\"'\\s=:])(/" + "ho" + "me/|/" + "Us" + "ers/|/" + "ro" + "ot/)"
)


def _is_date(value) -> bool:
    if not isinstance(value, str) or not _DATE_RE.match(value):
        return False
    try:
        _dt.date.fromisoformat(value)
        return True
    except ValueError:
        return False


def _walk_strings(node):
    if isinstance(node, dict):
        for k, v in node.items():
            yield ("key", str(k))
            yield from _walk_strings(v)
    elif isinstance(node, (list, tuple)):
        for v in node:
            yield from _walk_strings(v)
    elif isinstance(node, str):
        yield ("value", node)


def _walk_kv(node):
    if isinstance(node, dict):
        for k, v in node.items():
            yield (str(k), v)
            yield from _walk_kv(v)
    elif isinstance(node, (list, tuple)):
        for v in node:
            yield from _walk_kv(v)


def _scan_no_secret_no_local(label: str, doc, r: Reporter) -> None:
    secretish = sorted({
        k for k, v in _walk_kv(doc)
        if k not in _SECRETISH_KEY_ALLOW
        and _SECRETISH_KEY_RE.search(k)
        and isinstance(v, str) and v.strip() != ""
    })
    r.check(not secretish, f"{label} : aucune valeur à connotation secrète",
            f"{label} : champ(s) interdit(s) (secret) : {secretish}")
    local = sorted({s for _, s in _walk_strings(doc) if _LOCAL_PATH_RE.search(s)})
    r.check(not local, f"{label} : aucun chemin local réel",
            f"{label} : chemin local réel interdit : {local}")


def _check_closed_root(label: str, doc, root: str, r: Reporter) -> dict | None:
    if not isinstance(doc, dict):
        r.fail(f"{label} : le document doit être un dictionnaire")
        return None
    extra = sorted(set(doc) - {root})
    r.check(not extra, f"{label} : dictionnaire racine exactement {{{root}}}",
            f"{label} : clé(s) racine inconnue(s) : {extra} (attendu {root} seul)")
    body = doc.get(root)
    if body is None:
        body = {}
    if not isinstance(body, dict):
        r.fail(f"{label} : `{root}` doit être un dictionnaire")
        return None
    return body


# --------------------------------------------------------------------------- #
# retired-sites.yml
# --------------------------------------------------------------------------- #
def validate_retired(path: str, r: Reporter) -> dict:
    label = "retired-sites"
    doc = load_yaml(path)
    _scan_no_secret_no_local(label, doc, r)
    body = _check_closed_root(label, doc, RETIRED_ROOT, r)
    if body is None:
        return {}

    for key, entry in body.items():
        pfx = f"{label}[{key}]"
        r.check(bool(SITE_RE.match(str(key))), f"{pfx} : clé conforme ^[a-z][a-z0-9-]*$",
                f"{pfx} : clé non conforme")
        if not isinstance(entry, dict):
            r.fail(f"{pfx} : la fiche doit être un dictionnaire")
            continue
        missing = [f for f in RETIRED_MANDATORY if f not in entry]
        r.check(not missing, f"{pfx} : champs obligatoires présents",
                f"{pfx} : champs manquants : {missing}")
        unknown = sorted(set(entry) - RETIRED_ALLOWED)
        r.check(not unknown, f"{pfx} : aucun champ inconnu",
                f"{pfx} : champ(s) inconnu(s) : {unknown}")
        r.check("status" not in entry and str(entry.get("status", "")) != "reactivated",
                f"{pfx} : aucune fiche retirée ne porte de statut `reactivated` (§21.9)",
                f"{pfx} : statut interdit sur une fiche retirée")

        if "retired_at" in entry:
            r.check(_is_date(entry["retired_at"]), f"{pfx} : retired_at est une date ISO (YYYY-MM-DD)",
                    f"{pfx} : retired_at invalide : {entry.get('retired_at')!r}")
        if "former_ansible_host" in entry:
            r.check(is_doc_addr(str(entry["former_ansible_host"])),
                    f"{pfx} : former_ansible_host est une adresse de documentation",
                    f"{pfx} : former_ansible_host doit être une adresse TEST-NET / privée")
        if "former_base_directory" in entry:
            r.check(str(entry["former_base_directory"]).startswith("/"),
                    f"{pfx} : former_base_directory est un chemin absolu",
                    f"{pfx} : former_base_directory doit être absolu")

        ld = entry.get("last_deployment")
        if isinstance(ld, dict):
            r.check(not (set(ld) - LAST_DEPLOYMENT_ALLOWED),
                    f"{pfx}.last_deployment : champs conformes",
                    f"{pfx}.last_deployment : champ(s) inconnu(s) : {sorted(set(ld) - LAST_DEPLOYMENT_ALLOWED)}")
            r.check(all(f in ld for f in LAST_DEPLOYMENT_MANDATORY),
                    f"{pfx}.last_deployment : image / version / digest présents",
                    f"{pfx}.last_deployment : image / version / digest manquants")
            r.check("latest" not in str(ld.get("version", "")) and "latest" not in str(ld.get("image", "")),
                    f"{pfx}.last_deployment : aucune référence `latest`",
                    f"{pfx}.last_deployment : référence `latest` interdite")
        elif ld is not None:
            r.fail(f"{pfx}.last_deployment : doit être un dictionnaire")

        pr = entry.get("preservation")
        if isinstance(pr, dict):
            r.check(not (set(pr) - PRESERVATION_ALLOWED),
                    f"{pfx}.preservation : champs conformes",
                    f"{pfx}.preservation : champ(s) inconnu(s) : {sorted(set(pr) - PRESERVATION_ALLOWED)}")
            r.check(all(f in pr for f in PRESERVATION_MANDATORY),
                    f"{pfx}.preservation : quatre champs présents",
                    f"{pfx}.preservation : champ(s) manquant(s)")
            r.check(str(pr.get("vm_status")) in VM_STATUS_VALUES,
                    f"{pfx}.preservation.vm_status ∈ {sorted(VM_STATUS_VALUES)}",
                    f"{pfx}.preservation.vm_status invalide : {pr.get('vm_status')!r}")
            for b in ("vm_preserved", "persistent_data_preserved", "secrets_archived_in_vault"):
                r.check(isinstance(pr.get(b), bool),
                        f"{pfx}.preservation.{b} est un booléen",
                        f"{pfx}.preservation.{b} doit être true/false")
        elif pr is not None:
            r.fail(f"{pfx}.preservation : doit être un dictionnaire")

    r.ok(f"{label} : {len(body)} projet(s) actuellement retiré(s)")
    return body


# --------------------------------------------------------------------------- #
# reactivated-sites.yml
# --------------------------------------------------------------------------- #
def validate_reactivated(path: str, r: Reporter) -> dict:
    label = "reactivated-sites"
    doc = load_yaml(path)
    _scan_no_secret_no_local(label, doc, r)
    body = _check_closed_root(label, doc, REACTIVATED_ROOT, r)
    if body is None:
        return {}

    for key, events in body.items():
        pfx = f"{label}[{key}]"
        r.check(bool(SITE_RE.match(str(key))), f"{pfx} : clé conforme",
                f"{pfx} : clé non conforme")
        if not isinstance(events, list) or not events:
            r.fail(f"{pfx} : la valeur doit être une LISTE non vide d'événements")
            continue
        r.ok(f"{pfx} : {len(events)} événement(s) de réactivation (liste)")
        dates: list[str] = []
        for i, ev in enumerate(events):
            epx = f"{pfx}[{i}]"
            if not isinstance(ev, dict):
                r.fail(f"{epx} : l'événement doit être un dictionnaire")
                continue
            missing = [f for f in REACT_EVENT_MANDATORY if f not in ev]
            r.check(not missing, f"{epx} : champs obligatoires présents",
                    f"{epx} : champs manquants : {missing}")
            unknown = sorted(set(ev) - REACT_EVENT_ALLOWED)
            r.check(not unknown, f"{epx} : aucun champ inconnu",
                    f"{epx} : champ(s) inconnu(s) : {unknown}")
            r.check(_is_date(ev.get("reactivated_at")),
                    f"{epx} : reactivated_at est une date ISO",
                    f"{epx} : reactivated_at invalide : {ev.get('reactivated_at')!r}")
            if _is_date(ev.get("reactivated_at")):
                dates.append(ev["reactivated_at"])
            prv = ev.get("previous_retirement")
            if isinstance(prv, dict):
                r.check(all(f in prv for f in PREV_RETIREMENT_MANDATORY),
                        f"{epx}.previous_retirement : retired_at + reason présents",
                        f"{epx}.previous_retirement : retired_at / reason manquants")
                r.check(not (set(prv) - PREV_RETIREMENT_ALLOWED),
                        f"{epx}.previous_retirement : aucun champ inconnu",
                        f"{epx}.previous_retirement : champ(s) inconnu(s) : {sorted(set(prv) - PREV_RETIREMENT_ALLOWED)}")
                r.check(_is_date(prv.get("retired_at")),
                        f"{epx}.previous_retirement.retired_at est une date ISO",
                        f"{epx}.previous_retirement.retired_at invalide")
                if _is_date(prv.get("retired_at")) and _is_date(ev.get("reactivated_at")):
                    r.check(prv["retired_at"] <= ev["reactivated_at"],
                            f"{epx} : on réactive APRÈS avoir retiré (retired_at ≤ reactivated_at)",
                            f"{epx} : reactivated_at ({ev['reactivated_at']}) antérieur au retrait ({prv['retired_at']})")
            elif prv is not None:
                r.fail(f"{epx}.previous_retirement : doit être un dictionnaire")
        r.check(dates == sorted(dates),
                f"{pfx} : événements en ordre chronologique (dans l'état courant)",
                f"{pfx} : événements dans le désordre — l'historique a-t-il été réécrit ?")
    return body


# --------------------------------------------------------------------------- #
# Append-only INTER-VERSION de reactivated-sites.yml (GSO-REQ-181)
# --------------------------------------------------------------------------- #
# `validate_reactivated` ne voit qu'un seul fichier : elle vérifie le schéma et
# l'ordre chronologique de l'état COURANT, mais ne peut pas détecter la
# suppression, la modification, la réécriture ou l'insertion rétroactive d'un
# événement ancien. Cette fonction compare DEUX états (`before` -> `after`) et
# impose que l'historique de chaque clé préexistante soit un PRÉFIXE EXACT du
# nouvel historique — seul l'ajout d'événements EN FIN de liste, et l'ajout de
# nouvelles clés, sont autorisés. Purement en lecture : aucune écriture.
def validate_append_only(before_path: str, after_path: str, r: Reporter) -> None:
    label = "append-only"
    b_doc = load_yaml(before_path) or {}
    a_doc = load_yaml(after_path) or {}
    b = b_doc.get(REACTIVATED_ROOT) or {}
    a = a_doc.get(REACTIVATED_ROOT) or {}
    if not isinstance(b, dict) or not isinstance(a, dict):
        r.fail(f"{label} : racine `{REACTIVATED_ROOT}` absente ou non-dictionnaire dans un des deux états")
        return

    for key, b_events in b.items():
        kx = f"{label}[{key}]"
        if key not in a:
            r.fail(f"{kx} : clé historique SUPPRIMÉE dans la nouvelle version")
            continue
        a_events = a[key]
        if not isinstance(b_events, list) or not isinstance(a_events, list):
            r.fail(f"{kx} : la valeur doit être une liste dans les deux états")
            continue
        if len(a_events) < len(b_events):
            r.fail(f"{kx} : historique TRONQUÉ ({len(b_events)} -> {len(a_events)} événement(s))")
            continue
        prefix_ok = a_events[: len(b_events)] == b_events
        r.check(prefix_ok,
                f"{kx} : l'ancien historique est un préfixe EXACT du nouveau ({len(b_events)} -> {len(a_events)})",
                f"{kx} : un événement antérieur a été supprimé, modifié, réordonné ou inséré "
                f"(l'ancien historique n'est plus un préfixe exact)")
        if prefix_ok and len(a_events) > len(b_events):
            tail = a_events[len(b_events):]
            last = None
            for ev in b_events:
                if isinstance(ev, dict) and _is_date(ev.get("reactivated_at")):
                    last = ev["reactivated_at"]
            ok_chrono = True
            for ev in tail:
                d = ev.get("reactivated_at") if isinstance(ev, dict) else None
                if _is_date(d) and _is_date(last) and d < last:
                    ok_chrono = False
                if _is_date(d):
                    last = d
            r.check(ok_chrono,
                    f"{kx} : les {len(tail)} nouvel(s) événement(s) sont postérieurs au dernier existant",
                    f"{kx} : un nouvel événement est antérieur au dernier événement déjà enregistré")

    new_keys = sorted(set(a) - set(b))
    if new_keys:
        r.ok(f"{label} : nouvelle(s) clé(s) autorisée(s) : {new_keys}")
    r.ok(f"{label} : {len(b)} historique(s) comparé(s) — seuls des ajouts en fin de liste sont admis")


# --------------------------------------------------------------------------- #
# Disjonction (contrat §7.4, §7.7 ; GSO-REQ-052, GSO-REQ-073, §21.9)
# --------------------------------------------------------------------------- #
def validate_disjonction(retired: dict, reactivated: dict,
                         registry_path: str | None, vault_path: str | None,
                         r: Reporter) -> None:
    retired_keys = set(retired)
    react_keys = set(reactivated)

    # GSO-REQ-181 / §21.9 : une clé à la fois retirée ET présente dans
    # l'historique de réactivation n'est légitime QUE si son retrait courant
    # est postérieur à sa dernière réactivation (elle a été retirée à
    # nouveau). Sinon, une clé « réactivée » subsiste indûment dans
    # retired_grav_sites.
    for k in retired_keys & react_keys:
        cur = retired[k].get("retired_at") if isinstance(retired[k], dict) else None
        last_react = max(
            (ev.get("reactivated_at") for ev in reactivated[k]
             if isinstance(ev, dict) and _is_date(ev.get("reactivated_at"))),
            default=None,
        )
        if _is_date(cur) and last_react:
            r.check(cur >= last_react,
                    f"§21.9 : `{k}` retiré ({cur}) après sa dernière réactivation ({last_react})",
                    f"GSO-REQ-181 : `{k}` réactivé le {last_react} subsiste dans retired_grav_sites (retired_at {cur})")

    if registry_path:
        rdoc = load_yaml(registry_path) or {}
        active = set((rdoc.get("grav_sites") or {}))
        overlap = active & retired_keys
        r.check(not overlap,
                "disjonction : aucune clé simultanément active et retirée (GSO-REQ-052)",
                f"disjonction : clé(s) à la fois dans grav_sites et retired_grav_sites : {sorted(overlap)}")
        # une clé réactivée actuellement active NE DOIT PAS être retirée
        for k in react_keys & active:
            r.check(k not in retired_keys,
                    f"disjonction : clé réactivée `{k}` active et absente de retired_grav_sites (§21.9)",
                    f"disjonction : clé réactivée `{k}` à la fois active et retirée")
    else:
        r.note("registre actif non fourni — disjonction registre non vérifiée ici")

    if vault_path:
        vdoc = load_yaml(vault_path) or {}
        v_active = set((vdoc.get("vault_grav_sites") or {}))
        v_retired = set((vdoc.get("vault_retired_grav_sites") or {}))
        overlap = v_active & v_retired
        r.check(not overlap,
                "disjonction vault : aucune clé dans vault_grav_sites ET vault_retired_grav_sites",
                f"disjonction vault : clé(s) en double : {sorted(overlap)}")
        # un projet retiré NE DOIT PAS garder d'entrée dans vault_grav_sites (GSO-REQ-073)
        stuck = retired_keys & v_active
        r.check(not stuck,
                "GSO-REQ-073 : aucun projet retiré ne conserve d'entrée dans vault_grav_sites",
                f"GSO-REQ-073 : projet(s) retiré(s) encore dans vault_grav_sites : {sorted(stuck)}")
        # un projet retiré avec secrets_archived_in_vault: true DOIT être dans vault_retired_grav_sites
        for k, entry in retired.items():
            if isinstance(entry, dict) and (entry.get("preservation") or {}).get("secrets_archived_in_vault") is True:
                r.check(k in v_retired,
                        f"disjonction vault : `{k}` retiré et ses secrets archivés dans vault_retired_grav_sites",
                        f"disjonction vault : `{k}` déclaré `secrets_archived_in_vault: true` mais absent de vault_retired_grav_sites")
        if registry_path:
            rdoc = load_yaml(registry_path) or {}
            active = set((rdoc.get("grav_sites") or {}))
            leak = active & v_retired
            r.check(not leak,
                    "disjonction vault : aucun site actif présent dans vault_retired_grav_sites",
                    f"disjonction vault : site(s) actif(s) dans vault_retired_grav_sites : {sorted(leak)}")
    else:
        r.note("vault non fourni — disjonction vault non vérifiée ici")


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def _finish(r: Reporter, label: str) -> int:
    print("----")
    if r.errors:
        print(f"{label} : {len(r.errors)} erreur(s) sur {r.checks} contrôles")
        return 1
    print(f"{label} : {r.checks} contrôles OK")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="gso_lifecycle", description=__doc__)
    ap.add_argument("--retired", default=None,
                    help="registry/retired-sites.yml — état courant")
    ap.add_argument("--reactivated", default=None,
                    help="registry/reactivated-sites.yml — état courant (= 'after' pour --history-before)")
    ap.add_argument("--registry", default=None, help="grav_sites.yml — active la disjonction registre")
    ap.add_argument("--vault", default=None, help="vault.yml — active la disjonction vault")
    ap.add_argument("--history-before", default=None, dest="history_before",
                    help="version ANTÉRIEURE de reactivated-sites.yml — active la comparaison "
                         "append-only inter-version (avec --reactivated comme version 'after')")
    args = ap.parse_args(argv)

    r = Reporter()
    to_check: list[tuple[str, str]] = []
    if args.retired is not None:
        to_check.append(("retired-sites", args.retired))
    if args.reactivated is not None:
        to_check.append(("reactivated-sites", args.reactivated))
    if args.history_before is not None:
        to_check.append(("history-before", args.history_before))
    if not to_check:
        ap.error("aucune opération : fournir --retired/--reactivated et/ou --history-before")
    if args.history_before is not None and args.reactivated is None:
        ap.error("--history-before exige --reactivated (la version 'after')")
    for lbl, p in to_check:
        if not os.path.isfile(p):
            r.fail(f"{lbl} : fichier absent : {p}")
    if r.errors:
        return _finish(r, "lifecycle")

    retired = validate_retired(args.retired, r) if args.retired is not None else {}
    reactivated = validate_reactivated(args.reactivated, r) if args.reactivated is not None else {}
    if args.retired is not None and args.reactivated is not None:
        validate_disjonction(retired, reactivated, args.registry, args.vault, r)
    if args.history_before is not None:
        validate_append_only(args.history_before, args.reactivated, r)
    return _finish(r, "lifecycle")


if __name__ == "__main__":
    sys.exit(main())
