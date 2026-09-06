#!/usr/bin/env python3
"""Extrait les valeurs sensibles d'un vault d'exemple, une par ligne.

Sert aux tests de non-fuite (GSO-REQ-024, GSO-REQ-074) : la liste des
valeurs à surveiller est dérivée du fichier lui-même, jamais recopiée dans
le code de test. N'affiche que ce qui est demandé, sur stdout, à charge
pour l'appelant de ne pas le journaliser.

Usage : vault_values.py <chemin/vault.yml.example>
"""

from __future__ import annotations

import sys

try:
    import yaml
except ImportError:
    sys.exit(2)


def walk(node, out: set[str]) -> None:
    if isinstance(node, dict):
        for k, v in node.items():
            if k in ("admin_password", "admin_user", "admin_email", "content"):
                for line in str(v).splitlines():
                    line = line.strip()
                    if line and not line.startswith(("#", "//", "<?php")):
                        out.add(line)
            walk(v, out)
    elif isinstance(node, list):
        for item in node:
            walk(item, out)


def main() -> int:
    doc = yaml.safe_load(open(sys.argv[1], encoding="utf-8")) or {}
    values: set[str] = set()
    walk(doc, values)
    for v in sorted(values):
        print(v)
    return 0


if __name__ == "__main__":
    sys.exit(main())
