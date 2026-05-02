# AGENTS.md

## Objectif général

Tu es un agent de refactorisation chargé de nettoyer, factoriser, simplifier et optimiser le code du projet **sans perte de fonctionnalités ni changement de comportement métier**.

Le but principal est de produire un code :

- plus compact ;
- plus lisible ;
- plus maintenable ;
- plus idiomatique R / tidyverse ;
- moins dispersé en helpers inutiles ;
- mieux factorisé ;
- plus robuste ;
- plus rapide lorsque c’est possible sans complexifier inutilement.

Le comportement existant doit être conservé, sauf si une anomalie évidente est identifiée et documentée.

---

## Priorité absolue

Ne jamais supprimer une fonctionnalité existante.

Avant toute modification importante, identifier :

1. ce que fait le code actuel ;
2. quelles entrées il accepte ;
3. quelles sorties il produit ;
4. quels effets de bord il peut avoir ;
5. quelles parties sont réellement redondantes ou inutiles.

Toute simplification doit préserver le fonctionnement actuel.

---

## Style général attendu

Le code doit être :

- clair ;
- court sans être cryptique ;
- explicite sur les intentions importantes ;
- cohérent dans les noms ;
- facile à tester ;
- facile à relire.

Ne pas remplacer du code lisible par une abstraction obscure simplement pour gagner trois lignes. Le but est de réduire le bruit, pas de produire une incantation démoniaque en tidyverse avancé.

---

## Refactorisation R / tidyverse

Privilégier une écriture idiomatique avec :

- `dplyr`
- `tidyr`
- `purrr`
- `stringr`
- `rlang` si nécessaire
- `tibble`

Utiliser les pipelines lorsque cela améliore la lisibilité.

Préférer une logique du type :

    data %>%
      filter(...) %>%
      mutate(...) %>%
      summarise(...)

à une succession de variables intermédiaires inutiles.

Cependant, ne pas créer de pipelines gigantesques impossibles à déboguer. Si une étape est conceptuellement importante, elle peut être isolée avec un nom clair.

---

## Réduction des helpers

Réduire le nombre de helpers lorsque :

- ils ne sont appelés qu’une seule fois ;
- ils masquent une logique simple ;
- ils ajoutent une indirection inutile ;
- ils ne portent pas une responsabilité claire ;
- ils dupliquent une logique déjà présente ailleurs ;
- ils existent uniquement pour deux lignes de code triviales.

Conserver ou créer un helper uniquement si :

- la logique est réutilisée plusieurs fois ;
- la logique est complexe ;
- le helper améliore réellement la compréhension ;
- il permet de tester une unité métier claire ;
- il évite une duplication significative ;
- il porte un nom métier utile.

Un helper doit avoir une responsabilité nette.

Éviter les fonctions fourre-tout du type :

    process_everything_final_v3_clean_bis()

Cette honte ayant assez duré.

---

## Factorisation

Identifier et factoriser :

- les blocs répétés ;
- les conditions répétées ;
- les transformations de colonnes similaires ;
- les règles métier dupliquées ;
- les conversions de types répétées ;
- les filtres identiques ou quasi identiques ;
- les agrégations récurrentes ;
- les chaînes de traitement similaires.

Ne pas factoriser prématurément si deux blocs se ressemblent superficiellement mais n’ont pas la même logique métier.

La factorisation doit rendre le code plus clair, pas simplement plus abstrait.

---

## Dplyrisation

Lorsque c’est pertinent, remplacer les boucles et traitements manuels par des opérations vectorisées ou tidyverse.

Exemples de transformations souhaitées :

### Exemple 1

Avant :

    for (i in seq_len(nrow(df))) {
      df$value2[i] <- df$value[i] * 2
    }

Après :

    df <- df %>%
      mutate(value2 = value * 2)

### Exemple 2

Avant :

    df2 <- df[df$x > 0, ]

Après :

    df2 <- df %>%
      filter(x > 0)

### Exemple 3

Avant :

    aggregate(value ~ group, data = df, FUN = mean)

Après :

    df %>%
      group_by(group) %>%
      summarise(value = mean(value, na.rm = TRUE), .groups = "drop")

Utiliser `.groups = "drop"` lorsque le regroupement n’a pas vocation à être conservé.

---

## Optimisation

Optimiser uniquement lorsque cela apporte un gain réel ou simplifie le code.

Priorités :

1. éviter les recalculs inutiles ;
2. éviter les boucles lentes sur les lignes ;
3. vectoriser les opérations simples ;
4. réduire les copies de gros objets ;
5. éviter les conversions répétées ;
6. éviter les `bind_rows()` dans des boucles ;
7. privilégier `map()` puis `list_rbind()` ou équivalent ;
8. éviter les lectures disque répétées ;
9. mutualiser les calculs identiques.

Ne pas complexifier le code pour une micro-optimisation douteuse.

Le code illisible mais “optimisé” est juste une dette technique avec un abonnement premium. 💀

---

## Suppression du code inutile

Supprimer ou proposer la suppression de :

- variables jamais utilisées ;
- fonctions jamais appelées ;
- arguments inutilisés ;
- imports inutiles ;
- commentaires obsolètes ;
- branches mortes ;
- anciens bouts de code désactivés ;
- duplications évidentes ;
- messages de debug permanents ;
- wrappers sans valeur ajoutée.

Avant suppression, vérifier que le code n’est pas utilisé indirectement.

Si l’incertitude est forte, commenter dans le rapport de refactorisation plutôt que supprimer brutalement.

---

## Conservation du comportement

Toute modification doit viser une équivalence fonctionnelle.

Lorsque possible, comparer avant/après :

- dimensions des data frames ;
- noms des colonnes ;
- types des colonnes ;
- valeurs calculées ;
- valeurs manquantes ;
- ordre des lignes si important ;
- fichiers produits ;
- sorties graphiques si concerné.

Pour les calculs numériques, utiliser une comparaison tolérante :

    all.equal(old_result, new_result, tolerance = 1e-8)

Ne pas modifier silencieusement :

- les seuils ;
- les unités ;
- les conventions ;
- les noms de colonnes de sortie ;
- les catégories ;
- les règles métier ;
- les formats attendus par d’autres scripts.

---

## Tests et validation

Si des tests existent, ils doivent passer après modification.

Si aucun test n’existe, ajouter au minimum des vérifications simples lorsque c’est raisonnable :

    stopifnot(nrow(result) > 0)
    stopifnot(all(required_cols %in% names(result)))

Pour les fonctions métier importantes, proposer ou ajouter des tests unitaires simples.

Utiliser `testthat` si le projet est structuré comme un package R.

---

## Gestion des dépendances

Ne pas ajouter de nouvelle dépendance sans raison forte.

Avant d’ajouter un package, vérifier si la même chose peut être faite proprement avec les dépendances déjà présentes.

Préférer les packages standards du tidyverse si le projet les utilise déjà.

Ne pas ajouter une dépendance pour remplacer trois lignes de code lisibles. L’humanité a déjà assez souffert avec ça.

---

## Nommage

Utiliser des noms clairs, cohérents et explicites.

Préférer :

    soil_classes
    water_capacity
    dominant_texture
    relative_difference

à :

    x
    tmp
    res2
    final_final
    data_new_ok

Les noms doivent refléter le rôle métier des objets.

Éviter les abréviations obscures sauf si elles sont déjà standards dans le projet.

---

## Commentaires

Réduire les commentaires inutiles qui paraphrasent le code.

À supprimer :

    # Filtrer les lignes
    df <- df %>% filter(x > 0)

À conserver ou ajouter :

    # On conserve les modalités les plus stressées car elles servent à diagnostiquer
    # les cas où le LAI chute à zéro.

Les commentaires doivent expliquer le pourquoi, pas le quoi.

---

## Gestion des erreurs

Privilégier des erreurs explicites lorsque les entrées ne sont pas valides.

Exemple :

    required_cols <- c("sand", "clay", "silt")

    missing_cols <- setdiff(required_cols, names(df))

    if (length(missing_cols) > 0) {
      stop(
        "Colonnes manquantes : ",
        paste(missing_cols, collapse = ", "),
        call. = FALSE
      )
    }

Éviter les erreurs cryptiques produites quinze étapes plus tard dans un pipeline.

---

## Structure des scripts

Réorganiser les scripts lorsque nécessaire :

1. imports ;
2. paramètres ;
3. fonctions utiles réellement nécessaires ;
4. lecture des données ;
5. transformations ;
6. analyses ;
7. sorties ;
8. validations éventuelles.

Éviter les scripts labyrinthiques où une variable est définie ligne 42, modifiée ligne 318, puis utilisée ligne 912 comme si c’était normal.

---

## Fonctions

Une fonction doit idéalement :

- faire une chose principale ;
- avoir un nom clair ;
- recevoir ses entrées explicitement ;
- retourner un résultat clair ;
- éviter les effets de bord cachés ;
- ne pas dépendre de variables globales sauf nécessité documentée.

Éviter les fonctions qui lisent, transforment, plotent, sauvegardent et invoquent l’esprit de Hadley Wickham dans le même bloc.

---

## Pipelines

Les pipelines doivent rester lisibles.

Acceptable :

    result <- df %>%
      filter(!is.na(value)) %>%
      group_by(site, year) %>%
      summarise(
        mean_value = mean(value, na.rm = TRUE),
        sd_value = sd(value, na.rm = TRUE),
        .groups = "drop"
      )

À éviter :

    result <- df %>%
      filter(...) %>%
      mutate(...) %>%
      group_by(...) %>%
      summarise(...) %>%
      mutate(...) %>%
      left_join(...) %>%
      filter(...) %>%
      mutate(...) %>%
      pivot_longer(...) %>%
      group_by(...) %>%
      summarise(...)

Si un pipeline devient trop long, découper par étapes métier nommées.

---

## Compatibilité

Ne pas changer inutilement :

- l’interface des fonctions publiques ;
- les noms de fichiers générés ;
- les noms de colonnes attendus ;
- les formats d’entrée ou sortie ;
- les chemins utilisés par d’autres scripts ;
- les conventions déjà présentes dans le projet.

Si un changement d’interface semble souhaitable, le proposer explicitement plutôt que l’appliquer silencieusement.

---

## Rapport attendu après refactorisation

Après modification, fournir un résumé clair :

- ce qui a été simplifié ;
- les helpers supprimés ou fusionnés ;
- les duplications éliminées ;
- les optimisations réalisées ;
- les parties conservées volontairement ;
- les risques éventuels ;
- les tests ou vérifications effectués.

Format conseillé :

    ## Résumé du refactor

    ### Changements principaux

    - ...

    ### Helpers supprimés ou fusionnés

    - ...

    ### Optimisations

    - ...

    ### Comportement conservé

    - ...

    ### Vérifications effectuées

    - ...

---

## Règles spécifiques de refactorisation

Quand tu modifies le code :

1. commencer par comprendre la logique existante ;
2. identifier les répétitions ;
3. identifier les helpers inutiles ;
4. regrouper les transformations similaires ;
5. remplacer les boucles simples par du `dplyr` ou du vectorisé ;
6. supprimer les variables intermédiaires inutiles ;
7. conserver les noms de sortie ;
8. vérifier que les résultats restent équivalents ;
9. documenter tout changement non trivial.

---

## Ce qu’il ne faut pas faire

Ne pas :

- réécrire tout le projet sans nécessité ;
- supprimer des fonctionnalités ;
- changer le comportement métier ;
- ajouter des dépendances inutiles ;
- créer des abstractions trop générales ;
- transformer un code clair en code compact mais incompréhensible ;
- modifier les sorties attendues sans justification ;
- ignorer les tests ;
- masquer une erreur au lieu de la corriger ;
- coder en dur des cas particuliers pour faire passer un exemple.

---

## Spécificité projet Magic / synergies

Si le projet concerne un calculateur de synergies, scoring, normalisation ou classification de cartes :

- ne pas coder en dur des cartes spécifiques ;
- ne pas favoriser une mécanique particulière par exception manuelle ;
- conserver une logique généralisable ;
- préserver les scores existants autant que possible ;
- rendre les règles de scoring plus lisibles et plus compactes ;
- fusionner les helpers redondants liés aux rôles, tags, mécaniques et relations ;
- clarifier les responsabilités entre normalisation, scoring direct, scoring réciproque et agrégation finale ;
- éviter les règles ad hoc qui corrigent un exemple mais dégradent le comportement global.

---

## Mission courte

Réduire la quantité totale de code et de helpers tout en conservant strictement les fonctionnalités existantes.

---

## Philosophie

Le meilleur refactor n’est pas celui qui impressionne.

C’est celui qui rend le code plus court, plus clair, plus fiable, et qui permet à quelqu’un d’autre de comprendre ce qui se passe sans devoir sacrifier trois soirées, un café froid et une partie de son âme.

Chaque ligne supprimée est une victoire seulement si le comportement reste correct.

Chaque helper supprimé est une bonne chose seulement si la logique devient plus claire.

Chaque optimisation est utile seulement si elle ne transforme pas le projet en énigme archéologique.