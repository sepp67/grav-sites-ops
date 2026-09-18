# Instructions locales — grav-sites-ops

Avant toute action, lire le fichier `../CLAUDE.md`.

Ce dépôt porte la configuration et l'orchestration des instances Grav. Il
consomme `ansible-role-grav-site`, qui reste le mécanisme atomique de
déploiement.

## Invariants locaux

- conserver une vue explicite des instances administrées ;
- séparer les variables communes des variables propres à chaque instance ;
- déclarer pour chaque site une référence d'image explicite par tag et/ou
  digest ;
- ne jamais utiliser une étiquette d'image flottante telle que `latest` ;
- invoquer le rôle atomique pour une instance ciblée ;
- exécuter le préflight avant toute mutation distante ;
- conserver les secrets uniquement dans des vaults effectivement chiffrés ;
- ne jamais afficher, documenter ou journaliser le contenu déchiffré d'un
  vault ;
- ne jamais intégrer le code d'un site ou reconstruire une image applicative ;
- ne pas réimplémenter les tâches du rôle ;
- ne pas gérer le reverse proxy public ou le TLS lorsque cette responsabilité
  appartient au dépôt d'infrastructure correspondant.

## Inventaires et ciblage

- toute commande de déploiement doit cibler explicitement l'instance attendue ;
- vérifier l'inventaire, le groupe et l'hôte effectifs avant une exécution ;
- ne jamais ajouter à Git le répertoire `inventories/production/` ni aucun de
  ses fichiers ;
- pour toute mise en index, cibler exclusivement les chemins autorisés et ne
  jamais utiliser `git add .` ou `git add -A` ;
- ne jamais déduire qu'un fichier ouvert dans l'IDE est autorisé à être lu ou
  modifié ;
- ne jamais généraliser une adresse IP, un nom d'hôte ou une variable de
  production dans la documentation publique ;
- signaler tout fichier de production non suivi ou toute divergence
  inattendue avant de poursuivre.

## Avant une modification

Consulter au minimum :

- `README.md` ;
- `Makefile` ;
- `requirements.yml` ;
- les playbooks concernés ;
- l'inventaire et les variables de l'instance ciblée, uniquement lorsque la
  tâche les autorise ;
- la documentation normative pertinente dans `docs/`.

## Contrôles spécifiques

- validation YAML ;
- installation ou résolution de la version déclarée du rôle ;
- affichage de l'inventaire effectif sans révéler de secret ;
- `ansible-playbook --syntax-check` ;
- préflight ciblé ;
- vérification de la référence d'image déclarée ;
- déploiement, healthcheck et vérification HTTP uniquement après autorisation ;
- vérification de l'état déployé et de sa traçabilité.
