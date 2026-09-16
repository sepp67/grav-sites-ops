#!/usr/bin/env python3
# grav-sites-ops — classification de dérive (lot L6).
#
# Fonction PURE : reçoit sur l'entrée standard un objet JSON décrivant, pour
# UN hôte, les trois niveaux d'état du contrat §16.1 (désiré / appliqué /
# réel) ; écrit sur la sortie standard un objet JSON `{category, reasons,
# references}` et termine TOUJOURS avec le code 0 — la classification n'est
# pas en soi un échec, c'est le playbook appelant qui décide du code de
# sortie (GSO-REQ-093).
#
# Ne lit aucun fichier, n'ouvre aucune connexion, n'écrit rien : toute la
# collecte (slurp de `.deployed_state.yml`, `docker inspect`, `uri`) est
# faite en amont par le playbook, en lecture seule, avec des modules
# génériques (GSO-REQ-090). Aucune valeur secrète n'entre ici (GSO-REQ-123).
#
# Catégories (contrat §16.5) :
#   IN_SYNC NOT_DEPLOYED REFERENCE_DRIFT CONFIG_DRIFT STOPPED UNHEALTHY
#   UNREACHABLE UNKNOWN
# `STOPPED` est relatif à l'état DÉSIRÉ (`grav_sites[host].state`) : un site
# voulu `stopped` et effectivement arrêté est `IN_SYNC`, jamais `STOPPED`
# (GSO-REQ-121).

from __future__ import annotations

import json
import sys

CATEGORIES = (
    "IN_SYNC",
    "NOT_DEPLOYED",
    "REFERENCE_DRIFT",
    "CONFIG_DRIFT",
    "STOPPED",
    "UNHEALTHY",
    "UNREACHABLE",
    "UNKNOWN",
)


def _desired_reference(desired: dict) -> str:
    image = str(desired.get("image", "")).strip()
    digest = str(desired.get("digest", "") or "").strip()
    version = str(desired.get("version", "")).strip()
    if not image:
        return ""
    if digest:
        return f"{image}@{digest}"
    return f"{image}:{version}" if version else image


def _norm_ref(ref: str) -> str:
    return str(ref or "").strip()


def _as_int(value) -> int | None:
    """Tolère '', None, 'null' -> None ; sinon un entier ou None."""
    if value is None:
        return None
    s = str(value).strip()
    if s == "" or s.lower() in ("none", "null"):
        return None
    try:
        return int(s)
    except (TypeError, ValueError):
        return None


def _as_bool(value) -> bool:
    return str(value).strip().lower() in ("true", "1", "yes")


def _clean(value):
    """'' et 'None'/'null' -> None (Jinja stringifie volontiers None)."""
    if value is None:
        return None
    s = str(value).strip()
    return None if s == "" or s.lower() in ("none", "null") else value


def classify(data: dict) -> dict:
    """Retourne {category, reasons, references} pour un hôte."""
    desired = data.get("desired") or {}
    applied = _clean(data.get("applied"))
    applied_error = _clean(data.get("applied_error"))
    real = data.get("real") or {}
    real_error = _clean(data.get("real_error"))

    reasons: list[str] = []
    desired_state = str(desired.get("state", "started") or "started").strip()
    want_stopped = desired_state == "stopped"

    desired_ref = _desired_reference(desired)
    applied_ref = _norm_ref((applied or {}).get("effective_reference")) if applied else ""
    real_ref = _norm_ref(_clean(real.get("container_image")))

    refs = {
        "desired": desired_ref,
        "applied": applied_ref or None,
        "real": real_ref or None,
    }

    def result(category: str) -> dict:
        assert category in CATEGORIES, category
        return {"category": category, "reasons": reasons, "references": refs}

    # 1. VM injoignable : aucune comparaison de l'état réel possible.
    if real_error == "unreachable":
        reasons.append("hôte injoignable — état réel indéterminable")
        return result("UNREACHABLE")

    # 2. Preuves insuffisantes ou incohérentes -> UNKNOWN.
    if applied_error in ("unreadable", "incoherent"):
        reasons.append(f".deployed_state.yml {applied_error}")
        return result("UNKNOWN")
    if real_error == "module_failure":
        # Échec d'exécution du module lui-même (Ansible rapporte
        # "MODULE FAILURE") — distinct d'un Docker réellement injoignable :
        # l'existence du conteneur est INCONNUE, jamais "absente" (audit
        # privilèges, 2026-09-16 ; précision sémantique 2026-09-16). Un
        # échec de `become` est une cause CONCRÈTE possible, mais pas la
        # seule cause de cette forme — la raison reste donc volontairement
        # générique. Reste UNKNOWN (taxonomie inchangée) ; seule la raison
        # est plus précise qu'un simple "conteneur absent".
        reasons.append("exécution du module impossible sur la cible")
        return result("UNKNOWN")
    if real_error in ("docker_unavailable", "ambiguous"):
        reasons.append(f"état réel indéterminable ({real_error})")
        return result("UNKNOWN")
    if not desired_ref:
        reasons.append("état désiré incomplet (image absente du registre)")
        return result("UNKNOWN")

    container_exists = _as_bool(real.get("container_exists"))
    running = _as_bool(real.get("running"))
    applied_absent = applied is None or applied_error == "absent"

    # 3. Rien de déployé : ni état appliqué, ni conteneur attendu.
    if applied_absent and not container_exists:
        if want_stopped:
            reasons.append("état désiré 'stopped' ; aucune instance déployée")
        else:
            reasons.append("aucun état appliqué et aucun conteneur")
        return result("NOT_DEPLOYED")

    # 4. Conteneur absent alors qu'un état appliqué existe -> forte dérive.
    if not container_exists:
        reasons.append("état appliqué présent mais conteneur attendu absent")
        return result("NOT_DEPLOYED")

    # 5. Cohérence de la référence (désiré vs appliqué vs réel).
    if applied_ref and applied_ref != desired_ref:
        reasons.append(f"référence appliquée {applied_ref!r} ≠ désirée {desired_ref!r}")
        return result("REFERENCE_DRIFT")
    if real_ref and not _refs_compatible(desired_ref, real_ref):
        reasons.append(f"image du conteneur {real_ref!r} ≠ référence désirée {desired_ref!r}")
        return result("REFERENCE_DRIFT")

    # 6. État marche/arrêt vs état DÉSIRÉ.
    if want_stopped:
        if running:
            reasons.append("conteneur en cours d'exécution alors que l'état désiré est 'stopped'")
            return result("CONFIG_DRIFT")
        reasons.append("état désiré 'stopped' ; conteneur arrêté ; références cohérentes")
        return result("IN_SYNC")

    if not running:
        reasons.append("conteneur attendu en cours d'exécution mais arrêté")
        return result("STOPPED")

    # 7. Paramètres structurants (port publié).
    want_port = _as_int(desired.get("http_port"))
    got_port = _as_int(real.get("published_port"))
    if want_port is not None and got_port is not None and want_port != got_port:
        reasons.append(f"port publié {got_port} ≠ port du registre {want_port}")
        return result("CONFIG_DRIFT")

    # 8. Santé réelle : la seule présence du conteneur ne suffit pas
    #    (GSO-REQ-120). Le healthcheck Docker fait autorité ; l'endpoint HTTP
    #    n'est qu'une corroboration (un `uri` qui n'a pas pu se connecter
    #    renvoie un statut négatif : ce n'est pas une preuve de mauvaise santé).
    health = _clean(real.get("health"))
    http_status = _as_int(real.get("http_status"))
    http_is_response = http_status is not None and 100 <= http_status <= 599

    if health == "unhealthy":
        reasons.append("healthcheck Docker négatif")
        return result("UNHEALTHY")
    if health == "healthy":
        reasons.append("désiré, appliqué et réel concordent ; healthcheck Docker positif")
        return result("IN_SYNC")
    if health == "starting":
        reasons.append("healthcheck Docker encore en cours ('starting')")
        return result("UNKNOWN")

    # Pas de healthcheck Docker : se rabattre sur l'endpoint HTTP s'il a répondu.
    if http_is_response and 200 <= http_status < 400:
        reasons.append(f"pas de healthcheck Docker ; endpoint HTTP répond {http_status}")
        return result("IN_SYNC")
    if http_is_response:
        reasons.append(f"endpoint HTTP local répond {http_status}")
        return result("UNHEALTHY")

    reasons.append("aucune preuve de santé (ni healthcheck Docker, ni réponse HTTP)")
    return result("UNKNOWN")


def _refs_compatible(desired_ref: str, real_ref: str) -> bool:
    """Le conteneur peut exposer image@sha256 là où le registre déclare
    image:version (le digest résolu par Docker). On considère compatible si
    l'un est préfixe logique de l'autre sur le composant image."""
    if desired_ref == real_ref:
        return True
    d_img = desired_ref.split("@", 1)[0].split(":", 1)[0]
    r_img = real_ref.split("@", 1)[0].split(":", 1)[0]
    if d_img != r_img:
        return False
    # image identique : si le registre épingle un digest, il doit correspondre.
    if "@" in desired_ref:
        return desired_ref.split("@", 1)[1] == real_ref.split("@", 1)[1] if "@" in real_ref else False
    # registre sans digest : image identique suffit (Docker a résolu un digest).
    return True


def main(argv: list[str] | None = None) -> int:
    raw = sys.stdin.read()
    try:
        data = json.loads(raw)
    except (ValueError, TypeError) as exc:
        json.dump(
            {"category": "UNKNOWN", "reasons": [f"entrée illisible : {exc}"], "references": {}},
            sys.stdout,
        )
        print()
        return 0
    out = classify(data)
    json.dump(out, sys.stdout, ensure_ascii=False)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
