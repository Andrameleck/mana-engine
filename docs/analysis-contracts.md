# Contrats des tâches d'analyse

Ces contrats définissent ce que mana-engine peut conclure. Un score classe des résultats dans un contexte donné ; il ne mesure ni une probabilité de victoire, ni la puissance absolue d'une carte, ni l'exécutabilité immédiate d'une séquence.

## Contexte commun

Toute analyse reçoit un contexte versionné : format et date des règles, commandant éventuel, identité de couleur autorisée, deck, inventaire, périmètre de recherche et objectif. Chaque champ absent est retourné dans `unknown_fields`. Une contrainte connue est appliquée avant le classement. Une contrainte inconnue ne doit jamais être considérée comme satisfaite.

Les cartes sont identifiées par leur identité Oracle quand elle existe. L'impression et la ligne d'inventaire restent distinctes. Le texte Oracle canonique alimente l'analyse ; la langue choisie ne concerne que l'affichage.

Chaque réponse d'analyse contient au minimum `model_version`, `data_version`, `context`, `results`, `unknown_fields`, `warnings` et `truncated`.

## Affinités

**Entrée :** une carte de référence, un ensemble de candidats, le contexte et `k`.

**Sortie :** des candidats classés avec les composantes du score, les caractéristiques communes et les exclusions appliquées.

**Affirmation autorisée :** « ces cartes partagent les caractéristiques indiquées dans ce corpus et cette version du modèle ».

**Limites :** l'affinité est symétrique et ne prouve aucune complémentarité fonctionnelle. Une pondération IDF est calculée une seule fois sur le corpus commun. Les valeurs non finies et vecteurs invalides sont rejetés.

## Complémentarités

**Entrée :** une carte ou un besoin source, les candidats et le contexte.

**Sortie :** des relations dirigées `source -> cible`. Chaque relation nomme la ressource ou l'événement produit, le besoin satisfait, les types et zones concernés, le fragment Oracle source, la règle d'extraction et son statut de vérification.

**Affirmation autorisée :** « dans les conditions listées, la source contribue au besoin indiqué de la cible ».

**Limites :** partager un thème ou consommer la même ressource ne suffit pas. Les coûts, restrictions, négations, cibles et limites de fréquence sont conservés. Une capacité non couverte produit un résultat incomplet explicite.

## Combos de référence

**Entrée :** une ou plusieurs cartes, un instantané Spellbook et le contexte.

**Sortie :** les variantes complètes avec identifiant, composants et quantités, alternatives, préconditions, étapes, résultats, provenance et date. Le statut de chaque composant distingue sa présence dans le résultat consulté, l'inventaire et le deck.

**Affirmation autorisée :** « cette variante de référence est complète dans l'instantané consulté ; tels composants ou prérequis manquent ou restent inconnus ».

**Limites :** tous les composants obligatoires forment une conjonction. La présence des cartes ne prouve pas que la séquence est exécutable maintenant. Une pagination incomplète impose `truncated = true`.

## Ponts et groupes

**Entrée :** deux cartes ou ensembles de besoins, les relations admissibles, le contexte, une profondeur, une largeur et un budget de recherche distincts.

**Sortie :** des groupes contenant les deux entrées requises, le pont retenu, les chaînes dirigées, leur provenance, les conditions non résolues et l'indication de troncature.

**Affirmation autorisée :** « ce groupe relie les deux plans par les relations indiquées dans le périmètre recherché ».

**Limites :** chaque carte comptée dans le score appartient au groupe affiché. Les explications sont acycliques. L'absence de résultat dans une recherche tronquée ne prouve pas l'impossibilité.

## Analyse et remplacement de deck

**Entrée :** un deck, son contexte, un inventaire ou corpus candidat et un objectif déclaré.

**Sortie :** un diagnostic par critères, puis des couples `retrait + ajout`. Chaque proposition donne l'état avant et après pour la couverture du besoin, le plan, la jouabilité estimée, le coût et la fonction perdue.

**Affirmation autorisée :** « selon les critères et hypothèses affichés, ce remplacement améliore les composantes indiquées ».

**Limites :** légalité, identité de couleur, taille et limites d'exemplaires sont des filtres stricts. La concentration de mots-clés est un indicateur thématique, pas un score de synergie globale. Une recommandation sans retrait n'est valide que si le contexte autorise l'augmentation de taille.

## États et erreurs

- `verified` : relation ou référence contrôlée dans la version déclarée.
- `inferred` : résultat produit par une règle couverte, avec preuve affichée.
- `unknown` : donnée requise indisponible ou condition non évaluée.
- `invalid` : entrée contraire au schéma ou au contexte.

Une erreur d'entrée donne un statut HTTP 400, une ressource absente 404 et une erreur interne 500. Un corps `ok = false` ne doit pas être renvoyé avec un statut de succès.
