**Plan d'amélioration de mana-engine — proposition du 12 septembre 2026**

Ce plan répond à l'[audit de la révision 79a66fe](audit-2026-09-12.md). Il couvre la fiabilité du code, la qualité des données et l'adéquation des modèles aux tâches. Les travaux ci-dessous sont proposés ; la création de ce document ne les met pas en œuvre.

L'objectif est de pouvoir expliquer chaque recommandation : ce qui relie les cartes, les conditions nécessaires, les éléments manquants, et l'intérêt pour le contexte demandé. Les scores servent au classement. Ils ne constituent pas, sans validation spécifique, une probabilité de réussite ou une mesure de puissance.

Je propose de conserver R comme moteur de référence et Plumber comme API, avec JavaScript pour l'interface. Cette décision utilise les composants déjà présents et évite de maintenir deux définitions de la synergie. Les fonctions de calcul doivent également rester utilisables sans démarrer l'API. Le choix pourra être réexaminé à partir de mesures, mais il fournit une direction concrète pour la première version.

**Ordre et dépendances**

| Lot | Résultat | Dépendances | Périmètre principal |
|---|---|---|---|
| 0 | Contrats métier, cas de référence et état initial reproductible | Aucune | Documentation, fixtures, CI |
| 1 | Livraison fiable et accès aux données maîtrisé | 0 pour les tests ; confinement immédiat si nécessaire | Frontend, API, déploiement |
| 2 | Données canoniques et inventaire corrects | 0 ; protections de 1 avant exposition | Stockage et normalisation |
| 3 | Un moteur testable, avec une seule implémentation par calcul | 0, 2 ; sources réconciliées de 1 | R, Plumber, adaptateurs frontend |
| 4 | Relations fonctionnelles explicables sur trois familles | 2, 3 | Formalisme et extraction |
| 5 | Combos de référence complets, avec conditions et manques | 2, 3 ; indépendant du détecteur de 4 | Spellbook et interface |
| 6 | Ponts et groupes construits sur des relations identifiées | 4, 5 | Recherche et explications |
| 7 | Recommandations de remplacements contextualisées | 2, 4, 5 ; 6 pour les groupes nouveaux | Decks, mana, objectif d'analyse |
| 8 | Qualité mesurée et extension contrôlée de la couverture | À chaque lot ; bilan après 7 | Évaluation, performances, livraison |

Les lots 4 et 5 peuvent avancer indépendamment une fois leur socle commun prêt. La validation commence au lot 0 et accompagne chaque changement ; le lot 8 organise son suivi et les décisions d'extension. Aucun délai ferme n'est proposé avant l'exécution des vérifications R et la réconciliation des sources distribuées.

**Lot 0 — Définir précisément les tâches et établir les références**

Travaux : écrire un contrat pour chacune des cinq tâches : recherche de cartes proches, détection de complémentarités, recherche de ponts, consultation de combos, amélioration d'un deck. Définir les entrées, les exclusions, le résultat attendu, les informations inconnues et les affirmations autorisées. Séparer l'absence d'une carte dans l'inventaire de son absence dans le deck ou dans la zone de jeu requise.

Le contexte d'analyse comprend le format, sa version de règles/légalité, le commandant s'il existe, l'identité autorisée, l'inventaire disponible, le périmètre de recherche, le plan recherché et, pour les mesures de jouabilité, un horizon de tours. Les champs indispensables à une tâche sont exigés pour cette tâche seulement. Sans contexte complet, l'application peut proposer une exploration générale en indiquant la portée de sa réponse.

Transformer les sondes [JavaScript](probes-js.cjs) et [R](probes-r.R) en cas de régression dans les suites applicatives. Les assertions des sondes décrivent les défauts actuels : les nouvelles attentes devront exprimer les comportements corrects. Installer/configurer un environnement R reproductible pour exécuter les huit scénarios encore non vérifiés. Conserver les défauts connus dans une liste explicite pendant leur correction ; ne pas les masquer en désactivant des tests sans suivi.

Constituer un premier jeu de référence, avec une cible de travail ajustable : environ 30 cartes décrites manuellement sur trois familles, 10 paires pertinentes et 10 contre-exemples par famille, 20 variantes de combos et 5 contextes de decks. Ce petit jeu est un instrument de conception, pas une preuve de performance générale. Pour chaque exemple : identités canoniques, données datées, relation attendue, prérequis et justification de l'annotation.

**Validation :** un exemple d'entrée/sortie par tâche ; chaque défaut prioritaire relié à un test et à un lot ; versions de dépendances et commandes de vérification documentées ; résultats R exécutés ou blocage technique précisément identifié. Livrables : contrats, fixtures versionnées et état initial des tests.

**Lot 1 — Réconcilier les sources et fiabiliser l'application livrée**

Faire l'inventaire des différences entre `inst/www` et `frontend/src`, y compris HTML, styles et assets. Réintégrer dans les sources les fonctions utiles de gestion SQLite et de cartes. Comparer les comportements ; copier aveuglément les fichiers reproduirait les défauts relevés. Construire d'abord dans un répertoire de travail distinct, puis vérifier les parcours avant de remplacer les assets distribués.

Définir `frontend/src` comme source de référence et `inst/www` comme résultat de build. Ajouter un lockfile, une installation reproductible, la vérification syntaxique et le build à la CI. Vérifier aussi le routage du serveur de développement vers l'API. Tester chargement, import, sélection de collection, ajout, suppression et conservation des préférences.

Remplacer les paramètres de chemins libres des routes exposées par des identifiants de sources résolus côté serveur. Les éventuelles fonctions R de lecture locale peuvent conserver leur rôle pour les appels locaux explicites. Prévoir un adaptateur de transition pour l'interface existante, sans laisser l'ancienne route contourner la nouvelle restriction.

Pour la première version personnelle, configurer une exposition limitée et des sources autorisées. Si l'usage distant ou partagé est retenu, appliquer authentification et droits de lecture/modification sur chaque collection avant de l'exposer. Vérifier les chemins après résolution des liens et définir clairement les répertoires autorisés. Ne pas enregistrer de données privées dans des messages d'erreur publics.

Corriger les retours HTTP : erreur d'entrée, ressource absente et erreur serveur doivent avoir des statuts cohérents avec leur corps JSON. Nettoyer les fichiers temporaires créés par l'application après succès comme après échec. Le générateur de configuration Nginx doit refléter le nombre de workers réellement configuré ; vérifier notamment les configurations à un et trois workers.

Dès ce lot, employer des formulations prudentes pour les résultats actuels : affinité thématique, groupe proposé, conditions non évaluées. Conserver les détails disponibles plutôt qu'un score présenté comme une garantie.

**Validation :** build isolé reproduisant les fonctions distribuées ; aucun parcours important perdu ; lecture hors des sources autorisées rejetée ; mutations soumises au contrôle d'accès retenu ; fichiers temporaires supprimés après traitement ; tests HTTP et navigateur des parcours critiques. Audit concerné : constats 1, 2, 15 et 16.

**Lot 2 — Séparer carte, impression, inventaire et faits de règles**

Adopter un schéma canonique qui distingue :

| Objet | Informations essentielles | Invariant |
|---|---|---|
| Carte de règles | Identifiant Oracle lorsqu'il existe, nom canonique, faces, texte canonique, valeur de mana, identité, légalité | La langue d'affichage ne change pas le contenu analysé |
| Impression | Identifiant Scryfall, édition, numéro, langue, finition et champs imprimés | Plusieurs impressions peuvent correspondre à une même carte de règles |
| Ligne d'inventaire | Collection, impression ou résolution provisoire, quantité, état et attributs physiques utiles | Le stock est indépendant des caractéristiques utilisées pour le scoring |
| Fait extrait | Capacité, paramètres, fragment source, méthode et version d'extraction | Chaque affirmation est traçable ; une absence de donnée reste explicite |
| Contexte | Format, commandant, pool autorisé, objectifs et contraintes | Les contraintes globales restent identiques pendant toute une recherche |

Prévoir des identifiants provisoires lorsque la résolution d'un import est incomplète. Éviter de fusionner irréversiblement des noms ambigus. Les faces conservent leurs modes d'utilisation : agréger leurs textes pour rechercher des candidats ne signifie pas que tous leurs effets sont disponibles en même temps.

Corriger la normalisation des couleurs par branches exclusives pour les codes et les noms. Préserver séparément couleur, identité et production de mana. Conserver la valeur de mana canonique et traiter explicitement les replis ; ne pas remplacer une valeur manquante par zéro. La légalité absente devient inconnue, avec un choix explicite de filtrage pour l'analyse demandée.

Définir trois opérations d'inventaire : ajout d'exemplaires, remplacement d'un état d'inventaire et fusion selon une politique documentée. L'ajout doit modifier atomiquement la quantité ; une clé d'idempotence évite de compter deux fois une même requête rejouée. Le dédoublonnage d'import ne doit pas supprimer les acquisitions nouvelles. Tester séparément les éditions, langues, finitions et états physiques différents.

Remplacer les insertions qui ignorent tous les conflits par un enrichissement contrôlé. Compléter les références provisoires sans écraser les données de meilleure qualité ou les choix explicites de l'utilisateur. Conserver provenance et date de la source. Ajouter les contraintes de base après nettoyage des données existantes et vérifier l'ordre des écritures dans les transactions.

Écrire une migration testée sur une copie de base, avec bilan des lignes, quantités, références non résolues et conflits. Placer les données modifiables dans un répertoire de données configurable, indépendant des fichiers installés du package. Préparer sauvegarde et restauration vérifiées avant toute migration effective d'un inventaire utilisé.

**Validation :** ajouter trois exemplaires à deux donne cinq ; rejouer la même requête ne donne pas huit ; une référence partielle reçoit ensuite son texte ; une ou deux lignes représentant le même stock produisent le même profil ; EN et FR donnent les mêmes faits ; faces et données inconnues sont préservées. Audit concerné : 5, 6, 7, 8, 9, 11, 14 et 15.

**Lot 3 — Donner une seule définition à chaque calcul**

Créer des modules R purs, organisés par responsabilité : validation du contexte, normalisation, caractéristiques, recherche de candidats, règles de compatibilité, combos, ponts et analyse de deck. Les appels réseau, l'accès SQL et le rendu restent dans des adaptateurs. Les fonctions publiques existantes sont conservées avec leur contrat ou dépréciées explicitement ; leur comportement ne change pas silencieusement sous le même nom.

Exposer progressivement des opérations d'analyse via Plumber. Noms proposés, à préciser dans le contrat : `/analysis/affinities`, `/analysis/synergies`, `/analysis/combos`, `/analysis/bridges` et `/analysis/deck`. Toutes utilisent le même schéma canonique et retournent la version du modèle et des données. L'interface affiche des résultats structurés et gère chargement, erreurs et réponses périmées.

Extraire les calculs JavaScript de `bootstrap` pour permettre leur vérification pendant la migration. Basculer une tâche à la fois vers le moteur de référence. Comparer les résultats sur des fixtures fixes : préserver les comportements utiles, et documenter les différences qui corrigent un défaut. Retirer ensuite l'ancienne implémentation du parcours concerné.

Pour l'affinité textuelle, conserver les caractéristiques brutes et utiliser une pondération IDF commune, figée et versionnée pour une exécution. Calculer une fois les vecteurs et les normes. Définir la sémantique des valeurs négatives, des valeurs manquantes et des vecteurs nuls ; rejeter les valeurs non finies. Départager les égalités par identifiant canonique.

Corriger les fonctions R de graphe : préciser le contrat du top-k, appliquer les exclusions au moment compatible avec ce contrat, supprimer la troncature arbitraire par ordre d'entrée, et rendre explicites les limites de recherche. Si la recherche est approximative, mesurer son rappel et retourner un indicateur de troncature. Séparer budget de candidats, voisins retenus, largeur de recherche et nombre de résultats affichés.

**Validation :** une tâche n'a qu'une implémentation de référence ; appels R directs et API donnent les mêmes résultats ; mêmes caractéristiques comparées sous la même pondération ; stabilité sous permutation ; scores finis ; tests de compatibilité de l'API. Audit concerné : 10, 12, 13, 15 et 16, ainsi que les propriétés de propagation détaillées dans l'audit.

**Lot 4 — Décrire des complémentarités fonctionnelles**

Commencer par trois familles : production de jetons/sacrifice/déclenchements de mort ; préparation du cimetière/réanimation ; copie de sorts/déclenchements de lancement ou de copie. Leur diversité permet de tester événements, ressources, types d'objets et restrictions de cible. Une famille n'est annoncée couverte qu'à l'intérieur d'un périmètre documenté.

Décrire manuellement les capacités du petit jeu initial afin de tester d'abord la représentation et les relations. Développer ensuite l'extracteur automatique contre ces descriptions. Cela permet de savoir si une erreur provient du texte mal interprété ou d'une relation mal définie.

Une capacité représente l'acteur concerné, le type d'objet, la zone, l'événement, les entrées requises, les sorties produites, les coûts, les restrictions et la fréquence d'usage. Conserver négations, « une autre », limitations par tour et obligations de cible. Une capacité détectée est liée à son fragment Oracle et à la règle d'extraction.

Une relation `A → B` indique une contribution précise : A fournit un objet ou un événement accepté par B, ou permet de satisfaire un de ses prérequis. Faire correspondre les types et conditions. Deux consommateurs de la même ressource ne deviennent pas complémentaires par leur simple similarité. Détecter aussi les conflits couverts par le modèle ; l'absence de conflit détecté n'est pas une preuve d'absence de conflit.

Générer des candidats depuis l'union de plusieurs voies : similarité textuelle, rôles complémentaires et références connues. Une relation fonctionnelle doit pouvoir être découverte même si les cartes n'ont aucune caractéristique textuelle commune. Mesurer le rappel de chaque voie avant d'affiner le classement.

Séparer l'affinité, la relation fonctionnelle, sa preuve textuelle et son statut de vérification. Éviter le bonus générique qui transforme tout « choix de couleur » en effet global. Utiliser d'abord un classement explicite fondé sur les relations établies et les conditions satisfaites, avec les composantes visibles ; ajuster les poids uniquement à partir d'exemples réservés à cet usage.

**Validation :** les relations annotées sont retrouvées ; les contre-exemples locaux/globaux, soi/adversaire, coûts/productions et restrictions de cible ne sont pas promus en relations certaines ; chaque relation affiche son explication ; les capacités non prises en charge donnent un résultat incomplet. Audit concerné : 4 et les limites du cosinus et de la symétrisation.

**Lot 5 — Préserver intégralement les combos connus**

Créer un adaptateur Spellbook conservant l'identifiant de variante, les composants et quantités, alternatives éventuelles, préconditions, étapes, résultats, provenance et date. Conserver la réponse brute ou une référence à un instantané pour pouvoir diagnostiquer une transformation. Les limites de requête et la pagination doivent être explicites : « aucune variante trouvée dans les résultats consultés » ne signifie pas « aucun combo n'existe ».

Représenter les composants obligatoires par une conjonction : tous doivent être présents selon la condition vérifiée. Une variante alternative constitue une autre possibilité complète. La limite du classement direct ou la limite d'affichage ne supprime jamais une pièce de la représentation métier.

Retourner séparément la correspondance avec une référence, la présence des composants dans l'inventaire, leur présence dans le deck, les préconditions de jeu évaluées et celles qui restent inconnues. Exemple de sortie correcte : « Référence connue ; une carte manque dans le deck ; conditions de jeu non évaluées ». La présence de toutes les cartes n'autorise pas à afficher « exécutable maintenant ».

Présenter les étapes originales avec leurs conditions ; ne pas les déduire d'un classement de cartes. Réserver une validation automatique de séquence aux opérations réellement couvertes par le modèle. Pour une boucle, vérifier la répétabilité et le bilan de ressources avant toute affirmation automatique de résultat illimité.

**Validation :** retirer chaque composant obligatoire d'une fixture rend le résultat incomplet ; diminuer le nombre de résultats directs ne change pas la composition ; aucune étape n'utilise une pièce omise ; source, quantités et préconditions sont conservées. Audit concerné : 3, 4 et 13. Ce lot fournit un premier résultat métier utile sans attendre un moteur général de règles.

**Lot 6 — Construire des ponts et groupes explicables**

Définir le pont demandé : une carte ou un petit ensemble qui contribue aux deux plans spécifiés. Les entrées comprennent deux seeds ou deux ensembles de besoins, le contexte, les conditions admises et la taille maximale du groupe. Une simple proximité aux deux seeds reste disponible comme mode d'exploration thématique, clairement identifié.

Construire le graphe à partir des relations fonctionnelles du lot 4 et conserver leurs directions. Les combos du lot 5 restent des relations sur des ensembles de composants. Une recherche bornée peut parcourir ces relations, mais le groupe candidat doit ensuite être contrôlé globalement : disponibilité conjointe, quantités, incompatibilités et prérequis communs. Des arêtes individuellement possibles ne garantissent pas une séquence globalement réalisable.

Commencer par une recherche bornée et déterministe sur petits ensembles : profondeur, taille et budget de recherche sont distincts. Conserver l'état et la provenance par chemin pour éviter les cycles d'explication. Retourner « recherche tronquée » lorsque le budget est atteint ; ne pas présenter l'absence de résultat comme une preuve d'impossibilité.

Classer d'abord selon des critères explicites : couverture des besoins des deux plans, préconditions non résolues, nombre de pièces, disponibilité et coût contextuel. Le nombre de routes redondantes ne doit pas, à lui seul, augmenter la pertinence. Un support entre dans le score et l'explication uniquement s'il appartient au groupe retenu. Le nombre de chaînes affichées n'affecte pas son contenu.

**Validation :** chaque lien possède une justification ; aucun parent cyclique ; pont et seeds présents dans le package attendu ; invariance au nombre d'explications affichées ; comparaison à une recherche exhaustive sur les petites fixtures ; comportement documenté lorsque le budget est atteint. Audit concerné : 12, 13 et formalisme de propagation.

**Lot 7 — Évaluer des remplacements dans un deck**

Commencer par diagnostiquer un deck selon le contexte : rôles présents et manquants, quantité de producteurs/consommateurs, composants de plans connus, contraintes de construction et qualité des métadonnées. Les ratios descriptifs peuvent être conservés avec des noms exacts. La concentration de tags devient un indicateur thématique, sans être présentée comme une qualité globale.

Pour la base de mana, employer les capacités de production et leurs restrictions, les coûts colorés, l'arrivée engagée et les conditions pertinentes dans le périmètre couvert. Définir le tour et les hypothèses de pioche utilisés. Une première estimation analytique peut couvrir les cas simples ; des simulations reproductibles peuvent traiter des scénarios plus riches, en exposant leurs hypothèses et leur variabilité. Une estimation de disponibilité du mana n'est pas une simulation complète de partie.

Formuler une recommandation comme un ajout accompagné d'un retrait lorsque la taille du deck est fixe. Pour le deck D, le contexte C, une carte ajoutée a et une carte retirée r, comparer U(D − r + a, C) à U(D, C). Définir U avant de le calibrer. Dans une première version, montrer plusieurs critères séparés plutôt qu'un total arbitraire : couverture d'un besoin, progression vers un plan, jouabilité estimée, coût, perte d'une fonction existante.

Appliquer les contraintes strictes avant le classement : format, identité du commandant, taille, limites d'exemplaires et périmètre d'inventaire choisi. Conserver les arbitrages entre objectifs ; une amélioration de la courbe peut retirer une interaction utile. L'utilisateur doit voir le bénéfice estimé et la contrepartie, ainsi que les critères non évalués.

Générer les candidats depuis les mécanismes des lots précédents puis recalculer les critères sur le deck modifié. Éviter de recommander uniquement les cartes les plus proches des cartes centrales : une fonction absente du deck peut être plus utile qu'un nouvel exemplaire fonctionnel d'un rôle déjà saturé.

**Validation :** aucun remplacement invalide dans les contextes couverts ; bilan avant/après vérifiable ; équivalence des inventaires représentés différemment ; cartes sans métadonnées signalées ; recommandations évaluées sur des decks qui n'ont pas servi à choisir les règles ou pondérations. Audit concerné : 8, 11, 14 et limite des scores d'amélioration.

**Lot 8 — Mesurer la qualité et décider des extensions**

Maintenir trois niveaux de vérification. Les tests unitaires couvrent les règles et invariants. Les tests intégrés couvrent ingestion, base, API et interface. L'évaluation métier couvre pertinence, erreurs sémantiques et résultats par famille. Une CI verte ne remplace pas cette dernière.

Séparer les données de conception, de réglage et d'évaluation. Regrouper les impressions d'une même carte par identité canonique pour éviter qu'une traduction ou une réimpression fuite d'un ensemble à l'autre. Réserver aussi des familles ou structures d'interaction lorsque l'objectif est d'évaluer une généralisation. Une absence de référence Spellbook ne constitue pas un exemple négatif certain.

Mesurer précision et rappel à k pour les candidats ; erreurs de rôles et de conditions pour les relations ; exactitude des composants et prérequis pour les combos ; validité et couverture pour les packages. Mesurer séparément l'abstention et la couverture afin qu'un système qui ne répond presque jamais ne paraisse pas meilleur par sa seule précision. Pour les decks, mesurer le gain selon les critères déclarés et distinguer avis annoté, estimation et résultat observé.

Comparer aux versions antérieures et à des approches simples : affinité seule, rôles seuls, références seules. Faire des ablations pour vérifier l'apport réel de chaque composante. Définir les seuils de pertinence après les premières mesures et les figer avant d'ouvrir le jeu d'évaluation réservé. Les invariants fonctionnels et les contre-exemples critiques doivent, eux, passer entièrement sur leurs fixtures.

Mesurer temps et mémoire sur plusieurs tailles de collections. Examiner les requêtes répétées, l'extraction et les comparaisons ; optimiser le poste dominant. Mettre en cache avec des clés comprenant version des données, du modèle et du contexte. Paginer les lectures et vérifier les écritures concurrentes SQLite. Une optimisation approximative doit annoncer son compromis de rappel.

**Validation :** rapport d'évaluation reproductible ; aucune régression critique connue dans le périmètre livré ; limites de couverture visibles ; build et migration testés ; objectif de performance fixé à partir des usages mesurés. Étendre ensuite une famille mécanique à la fois avec annotations et contre-exemples correspondants.

**Découpage recommandé des changements**

| Changement reviewable | Contenu | Condition avant intégration |
|---|---|---|
| 1 | Contrats et références de l'audit | Attentes métier revues, sondes R exécutées |
| 2 | Réconciliation frontend et build reproductible | Parcours distribués conservés |
| 3 | Sources autorisées, accès, erreurs HTTP et fichiers temporaires | Tests négatifs d'accès et tests d'échec |
| 4 | Schéma canonique et migration | Conservation du stock et restauration sur copie |
| 5 | Opérations d'inventaire et enrichissement | Quantités, idempotence et conflits vérifiés |
| 6 | Modules purs et API d'affinité commune | Parité utile, différences correctives documentées |
| 7 | Représentation et règles des trois familles | Explications et contre-exemples |
| 8 | Combos de référence complets | Préconditions et composants intacts |
| 9 | Ponts et packages | Recherche et provenance vérifiées |
| 10 | Diagnostic de deck et mana | Hypothèses et données inconnues explicites |
| 11 | Remplacements contextualisés | Validité et critères avant/après |
| 12 | Évaluation de version et optimisations ciblées | Résultats reproductibles et absence de régression critique |

Le premier jalon utilisable regroupe la livraison corrigée, l'inventaire fiable et les combos connus complets. Le deuxième ajoute les relations fonctionnelles et les ponts dans le périmètre couvert. Le troisième apporte les remplacements de deck évalués. Chaque jalon peut être livré et évalué séparément ; le calcul automatique de combos arbitraires reste une extension ultérieure dont le coût devra être estimé à partir de ces résultats.
