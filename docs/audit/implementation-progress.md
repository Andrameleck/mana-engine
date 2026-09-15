**Progression du plan d'amélioration**

Dernière mise à jour : 12 septembre 2026.

| Lot | État | Éléments réalisés | Suite |
|---|---|---|---|
| 0 — contrats et références | En cours | Audit, plan, sondes JavaScript converties en régressions, tests R ajoutés | Construire et annoter le jeu métier de référence |
| 1 — livraison et accès | En cours | Confinement des chemins serveur, nettoyage des fichiers temporaires créés par l'application, contrôles JavaScript en CI | Réconcilier entièrement `frontend/src` et `inst/www`, puis tester le build et les routes HTTP |
| 2 — données et inventaire | En cours | Ajout répété transformé en incrément de quantité ; enrichissement des références incomplètes ; langue canonique, faces et couleurs corrigées dans Strategy | Migration de schéma, provenance, identités Oracle et opérations explicites d'inventaire |
| 3 — moteur unique | En cours | Stabilité numérique du cosinus ; sélection des candidats, top-k, amortissement et contraintes globales corrigés en R | Exposer l'analyse R par API et retirer progressivement le calcul dupliqué du frontend |
| 4 — relations fonctionnelles | Amorçé | Faux positif générique de sélection de couleur retiré | Représentation typée et trois familles initiales |
| 5 — combos complets | Amorçé | Une variante ayant un composant absent n'est plus réduite à un faux combo partiel | Conserver prérequis, étapes, résultats, quantités et statut des pièces |
| 6 — ponts et groupes | Amorçé | Supports absents retirés du score et de l'explication ; packages R incluant seeds et pont ; parents stabilisés par première profondeur | Relations fonctionnelles et validation globale du groupe |
| 7 — remplacements de deck | À faire | — | Contexte, contraintes et comparaison avant/après |
| 8 — évaluation | En cours | Sondes déterministes exécutées sous Node ; tests R et CI ajoutés | Exécuter R localement ou en CI, ajouter évaluation métier et mesures de performance |

Les constats non corrigés restent documentés dans l'audit. Le score de deck, la pondération IDF entre corpus, l'évaluation de la base de mana et les recommandations hors identité de couleur restent notamment à reprendre. Ce fichier suit l'implémentation ; il ne vaut pas preuve que les tests non exécutés sont valides.

## Moteur fonctionnel 0.1.0

Le premier jalon du nouveau moteur est implanté en R. Il comprend un contexte explicite, la logique vrai/faux/inconnu, des capacités et faits structurés, un extracteur déterministe limité aux trois familles initiales, des relations dirigées, un classement sans compensation des contraintes strictes et des groupes de trois cartes construits sur deux relations prouvées. Les routes expérimentales `/analysis/v1/synergies` et `/analysis/v1/groups` exposent ces résultats.

Les variantes Spellbook ne sont plus limitées à quatre partenaires dans le calcul JavaScript. La suite `testthat`, les sondes R et JavaScript, le build Vite et `R CMD check --no-manual --no-build-vignettes` ont été exécutés localement avec succès. Le modèle fonctionnel reste expérimental : l'extracteur ne couvre volontairement qu'un petit sous-ensemble des formulations Oracle ; les textes non reconnus restent inconnus.

## Intégration multi-dépôts

Le dépôt `mana-engine-web` consomme maintenant les deux routes fonctionnelles comme couche de preuve complémentaire du classement historique. Le Synergy Lab affiche séparément les relations et les chaînes fonctionnelles, avec leurs statuts `verified`, `inferred` ou `unknown`. L'absence temporaire de l'API expérimentale ne masque pas les anciens résultats.

Le proxy générique de `mana-engine-infra` couvre déjà `/analysis/v1/*`; aucune nouvelle route nginx n'est nécessaire.
