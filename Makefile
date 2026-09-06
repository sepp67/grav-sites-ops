# grav-sites-ops — points d'entree
#
# Lots L0-L3. Ce Makefile expose l'installation de la dependance, les tests,
# et les controles LOCAUX en lecture seule (validate / preflight). Les cibles
# mutantes (deploy, restart, stop) seront ajoutees a partir du lot L4.
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
install-role: ## Installe sepp67.grav_site depuis requirements.yml dans ./roles
	ansible-galaxy role install -r requirements.yml -p $(ROLES_PATH) --force

.PHONY: lint
lint: ## yamllint + ansible-lint sur le depot
	yamllint -c .yamllint --strict .
	ansible-lint --nocolor --offline

.PHONY: test
test: ## Execute toute la batterie de tests disponible (GSO-T*)
	bash tests/run-all.sh

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

.PHONY: lint-registry
lint-registry: ## Valide le registre d'exemple (validateur statique L1)
	python3 scripts/lib/gso_validate.py registry --inventory inventories/example/hosts.yml --context example

.PHONY: lint-vault
lint-vault: ## Valide le modele de vault d'exemple (validateur statique L2)
	python3 scripts/lib/gso_validate.py vault --inventory inventories/example/hosts.yml

.PHONY: test-role
test-role: ## Verifie l'installation du role (acces reseau requis)
	bash tests/gso-t03-role-install.sh

.PHONY: clean
clean: ## Supprime les artefacts locaux non suivis (roles, caches)
	rm -rf $(ROLES_PATH) collections .ansible .ansible-lint-cache
	find . -name '*.retry' -delete
