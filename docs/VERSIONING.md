# Versionnement

Trois niveaux de version sont **distincts** et ne doivent jamais être
confondus (GSO-REQ-151).

| Niveau | Où il vit | Qui le fait évoluer |
|---|---|---|
| Version de l'orchestrateur `grav-sites-ops` | tag Git annoté + entrée `CHANGELOG.md` | une release de ce dépôt (gate séparé) |
| Version du rôle `sepp67.grav_site` | `requirements.yml` **uniquement** | montée de version du rôle, dans un commit dédié |
| Version de chaque image applicative | registre `grav_sites` (par site) | changement déclaratif dans le registre |

Règles :

- `requirements.yml` est l'unique source de vérité de la version du rôle
  (GSO-REQ-153). Aucun autre fichier fonctionnel ne la redéclare.
- La version de `grav-runtime` est **transitive** (portée par l'image
  applicative) et n'apparaît pas dans le schéma `grav_sites` (GSO-REQ-155).
- Une montée de version du rôle est isolée dans un commit distinct des
  changements de versions applicatives (GSO-REQ-060).
- `CHANGELOG.md` versionne le dépôt, pas le parc : il n'est pas une seconde
  source de vérité des versions actives (GSO-REQ-157).
- Toute version publiée possède un tag Git annoté et une entrée `CHANGELOG.md`
  correspondante (GSO-REQ-152). La publication est un gate distinct de
  l'exploitation.
- Chaque version approuvée du **contrat architectural** est identifiable et
  conservée dans l'historique (GSO-REQ-198) — la version en vigueur est
  `v0.5.0`.
