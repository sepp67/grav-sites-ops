#!/usr/bin/env python3
"""Harnais de test — injecte une racine synthétique dans le sélecteur.

RÉSERVÉ AUX TESTS. L'interface opérateur (`scripts/validate-target.sh`,
`scripts/preflight.sh`) n'offre aucun moyen de substituer la racine : elle
appelle `gso_validate.py selector <SITE>` sans option. Ce harnais passe par
les fonctions internes `run_selector` / `run_preflight` prévues à cet effet.

Usage : selector_harness.py {selector|preflight} <SITE|""> <root>
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.realpath(__file__)), "..", "..", "scripts", "lib"))
import gso_validate  # noqa: E402

cmd, site, root = sys.argv[1], sys.argv[2], sys.argv[3]
fn = gso_validate.run_selector if cmd == "selector" else gso_validate.run_preflight
sys.exit(fn(site or None, root=root))
