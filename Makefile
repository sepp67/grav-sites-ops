# grav-sites-ops — points d'entree
#
# Lot L0 (harnais). Ce Makefile ne contient que les operations reellement
# disponibles et testees a ce stade : installation de la dependance et
# execution des tests. Les cibles d'exploitation (deploy, restart, stop,
# check) seront ajoutees par les lots ulterieurs, avec un inventaire
# fourni explicitement via -i (GSO-REQ-025, GSO-REQ-053).

SHELL := /bin/bash
ROLES_PATH := roles

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
test-static: ## Execute uniquement les tests statiques du lot L0
	bash tests/gso-t01-syntax.sh
	bash tests/gso-t02-ansible-lint.sh
	bash tests/gso-t04-role-pinned.sh
	bash tests/gso-t23-no-control-repository.sh
	bash tests/gso-t24-no-local-paths-secrets.sh

.PHONY: test-role
test-role: ## Verifie l'installation du role (acces reseau requis)
	bash tests/gso-t03-role-install.sh

.PHONY: clean
clean: ## Supprime les artefacts locaux non suivis (roles, caches)
	rm -rf $(ROLES_PATH) collections .ansible .ansible-lint-cache
	find . -name '*.retry' -delete
