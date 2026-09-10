# grav-sites-ops — points d'entree
#
# Lots L0-L8. Installation des dependances, tests, controles locaux en
# lecture seule (validate / preflight), mutations d'UN site (deploy,
# restart, stop), controle de derive LECTURE SEULE (check, check-all) et
# validation du cycle de vie documentaire (lint-lifecycle).
# La mise a jour et le rollback (L7) sont des usages DECLARATIFS de
# `make deploy` (modifier grav_sites.yml -> committer -> check -> deploy) :
# aucune cible make update / make rollback.
# Le retrait et la reactivation (L8) sont des operations Git MANUELLES,
# documentees (docs/OPERATIONS.md) et verifiees APRES COUP par
# `make lint-lifecycle` : aucun playbook, aucun outil de transformation.
#
# SITE est transmis tel quel au selecteur, entre guillemets, sans
# reinterpretation shell (GSO-REQ-084). L'inventaire est fixe par le depot
# (GSO-REQ-053) : aucune option d'inventaire n'est acceptee.

SHELL := /bin/bash
ROLES_PATH := roles
SITE ?=

.DEFAULT_GOAL := help

.PHONY: help
help: ## Affiche cette aide
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "} {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

.PHONY: install-role
install-role: ## Installe sepp67.grav_site + community.docker depuis requirements.yml
	ansible-galaxy install -r requirements.yml --force

.PHONY: lint
lint: ## yamllint + ansible-lint sur le depot
	yamllint -c .yamllint --strict .
	ansible-lint --nocolor --offline

.PHONY: test
test: ## Gate locale COMPLETE : batterie reproductible + GSO-T15 (Docker+role+image requis — docs/TESTING.md)
	bash tests/run-all.sh --functional

.PHONY: test-reproducible
test-reproducible: ## Sous-ensemble 100 % reproductible (identique a la CI ; sans GSO-T15)
	bash tests/run-all.sh

.PHONY: test-functional
test-functional: ## GSO-T15 seul : deploiement fonctionnel + conteneur ephemere local
	bash tests/gso-t15-real-deploy.sh

.PHONY: test-static
test-static: ## Execute les tests statiques (hors acces reseau)
	bash tests/gso-t01-syntax.sh
	bash tests/gso-t02-ansible-lint.sh
	bash tests/gso-t04-role-pinned.sh
	bash tests/gso-t05-example-inventory.sh
	bash tests/gso-t06-registry-autoload.sh
	bash tests/gso-t07-vault-example.sh
	bash tests/gso-t08-selector-fixed-inventory.sh
	bash tests/gso-t09-selector-requires-site.sh
	bash tests/gso-t10-selector-refuses-global-and-multiple.sh
	bash tests/gso-t11-selector-closed.sh
	bash tests/gso-t12-selector-no-remote-contact.sh
	bash tests/gso-t23-no-control-repository.sh
	bash tests/gso-t24-no-local-paths-secrets.sh

.PHONY: validate
validate: ## Selecteur ferme : valide SITE contre l'inventaire impose (lecture seule)
	bash scripts/validate-target.sh "$(SITE)"

.PHONY: preflight
preflight: ## Preflight operateur : selecteur + coherence registre/vault (lecture seule)
	bash scripts/preflight.sh "$(SITE)"

.PHONY: deploy
deploy: ## Deploie/actualise UN site : selecteur -> verrou -> deploy-site.yml -> role
	bash scripts/deploy.sh "$(SITE)"

.PHONY: restart
restart: ## Redemarre UN site sans changer sa reference desiree (GSO-REQ-088)
	bash scripts/restart-site.sh "$(SITE)"

.PHONY: stop
stop: ## Arrete le conteneur d'UN site, sans rien supprimer ni retirer du parc (GSO-REQ-089)
	bash scripts/stop-site.sh "$(SITE)"

.PHONY: check
check: ## Controle de derive d'UN site (lecture seule) : desire vs applique vs reel (GSO-REQ-118)
	bash scripts/check-site.sh "$(SITE)"

.PHONY: check-all
check-all: ## Controle de derive de TOUT le parc actif (lecture seule, non mutant)
	bash scripts/check-all.sh

.PHONY: lint-registry
lint-registry: ## Valide le registre d'exemple (validateur statique L1)
	python3 scripts/lib/gso_validate.py registry --inventory inventories/example/hosts.yml --context example

.PHONY: lint-vault
lint-vault: ## Valide le modele de vault d'exemple (validateur statique L2)
	python3 scripts/lib/gso_validate.py vault --inventory inventories/example/hosts.yml

.PHONY: lint-lifecycle
lint-lifecycle: ## Valide les registres retire / reactive suivis + append-only inter-version (lecture seule, L8)
	python3 scripts/lib/gso_lifecycle.py \
	  --retired registry/retired-sites.yml \
	  --reactivated registry/reactivated-sites.yml
	bash scripts/lifecycle-history-check.sh

.PHONY: test-role
test-role: ## Verifie l'installation du role (acces reseau requis)
	bash tests/gso-t03-role-install.sh

.PHONY: matrix
matrix: ## Regenere docs/COMPLIANCE-MATRIX.md (matrice des 204 exigences, L10)
	python3 scripts/lib/gso_compliance.py > docs/COMPLIANCE-MATRIX.md
	@echo "docs/COMPLIANCE-MATRIX.md regenere."

.PHONY: matrix-check
matrix-check: ## Verifie que docs/COMPLIANCE-MATRIX.md est a jour (204 lignes, aucune exigence oubliee)
	python3 scripts/lib/gso_compliance.py --check

.PHONY: clean
clean: ## Supprime les artefacts locaux non suivis (roles, caches)
	rm -rf $(ROLES_PATH) collections .ansible .ansible-lint-cache
	find . -name '*.retry' -delete
	find . -type d -name '__pycache__' -exec rm -rf {} +
