**Méthode proposée pour les synergies fonctionnelles de mana-engine**

Document de conception du 12 septembre 2026. Statut : proposition détaillée à implémenter et à évaluer. Les formules ci-dessous définissent des modèles de travail ; elles ne constituent pas des résultats de performance. Ce document approfondit les lots 3 à 8 du [plan d'amélioration](audit/plan-amelioration.md) et précise les [contrats d'analyse](analysis-contracts.md).

L'objectif est de proposer une interaction utile pour un besoin déclaré et d'expliquer ce qui la rend possible, ce qu'elle apporte et ce qui lui manque. La nouveauté, la puissance, la popularité et la confiance dans l'interprétation sont des propriétés différentes.

**1. Point de départ et décisions de conception**

Dans `frontend/src/main.js`, `strategySimilarity` calcule actuellement :

\[
S_{actuel}(A,B)=\operatorname{clamp}_{[0,1]}(0{,}5T+0{,}4R+0{,}1C+B_{combo}).
\]

`T` est un cosinus de caractéristiques, `R` un score issu des heuristiques sémantiques, `C` une compatibilité de couleurs et `B_combo` un bonus de connaissance. Cette formule produit un classement heuristique. Elle mélange proximité, relation et contexte ; sa saturation à 1 peut aussi masquer les différences entre composantes.

La proposition antérieure `0,40F + 0,20K + 0,15X + 0,15J + 0,10T - P` n'est pas retenue comme spécification : ses coefficients n'ont pas été calibrés et une condition indispensable ne doit pas devenir un bonus compensable par d'autres qualités. Additionner les directions et un bonus de boucle peut également compter plusieurs fois le même mécanisme.

Les décisions proposées sont les suivantes :

| Décision | Conséquence |
|---|---|
| R devient l'implémentation de référence | Les appels R et l'API utilisent les mêmes fonctions pures |
| Les capacités sont décrites explicitement | Le moteur relie productions, événements et besoins |
| La validité précède le classement | Une impossibilité connue bloque la conclusion concernée |
| Les inconnues restent explicites | Pas de conversion implicite de « inconnu » vers « vrai » |
| Le score reste décomposé | Bénéfice, coût, conditions et preuve restent inspectables |
| Le graphe sert à découvrir des candidats | La validation conjointe décide de ce qu'on peut affirmer |
| Les explications sont construites depuis les preuves | Le classement des cartes ne devient pas un ordre de jeu |

Le moteur JavaScript et le graphe R actuels servent de références de comparaison pendant la migration. Les fonctions publiques existantes ne changent pas silencieusement de signification.

**2. Définir ce qu'est une proposition intéressante**

Trois demandes doivent être supportées en premier : trouver des partenaires pour une carte ; compléter un plan avec les cartes disponibles ; relier deux besoins. L'amélioration complète d'un deck vient ensuite.

Pour chaque demande, l'utilisateur choisit un objectif principal : alimenter une ressource, exploiter un événement, compléter une séquence, ajouter une alternative à une pièce fragile ou limiter le coût de mise en place. « Exploration générale » constitue un mode distinct lorsque l'objectif est absent.

Une proposition intéressante satisfait simultanément quatre exigences : une contribution fonctionnelle identifiable ; des hypothèses compatibles ; un bénéfice pour l'objectif ; une explication vérifiable. Une interaction peut être exacte mais peu utile au deck. Une carte très populaire peut être peu pertinente pour le besoin sélectionné.

Le résultat distingue : `affinity` pour une proximité descriptive, `functional_relation` pour une contribution dirigée, `reference_combo` pour une variante documentée et `validated_sequence` pour une séquence contrôlée dans un modèle et un état précis. Ces catégories peuvent coexister sur un même résultat ; elles ne forment pas une échelle automatique de puissance.

**3. Contexte, légalité et disponibilité**

Représenter séparément le contexte de construction du deck et l'état de jeu. Le premier contient le format, sa version, le commandant éventuel, les règles de construction, le deck, l'inventaire, le périmètre de recherche et les préférences. Le second contient les zones, les objets disponibles, les ressources, le tour, la priorité et les hypothèses nécessaires à une séquence.

Ne pas déduire une identité Commander autorisée de l'union des couleurs des cartes actuellement dans le deck. Cette union peut inclure une carte invalide ou omettre une couleur pourtant autorisée par le commandant. Le filtre actuel fondé sur les couleurs du deck est une approximation d'exploration à remplacer par le contexte explicite. Hors Commander, conserver les couleurs d'un deck peut être une préférence ; ce n'est pas universellement une obligation de construction.

La présence d'une carte dans la collection, dans le deck, dans la main et sur le champ de bataille correspond à quatre informations différentes. Les quantités requises sont vérifiées au niveau pertinent. Une collection possédant une seule impression n'autorise pas deux exemplaires simultanés si l'analyse impose le stock disponible.

Pour les prédicats, employer la logique à trois valeurs `true`, `false`, `unknown`. Une conjonction est fausse si une condition est fausse, vraie si toutes sont vraies, inconnue dans les autres cas. Une absence de métadonnée ne suffit pas à conclure à une absence de capacité.

| Mode | Comportement proposé |
|---|---|
| Explorer | Afficher les relations plausibles avec leurs conditions, même si le contexte de jeu manque |
| Construire un deck | Appliquer les contraintes connues ; isoler les candidats dont une contrainte indispensable reste inconnue |
| Vérifier une séquence | Exiger un état initial et n'autoriser une conclusion positive que pour les opérations couvertes |

Les règles de référence sont versionnées à partir des [Comprehensive Rules de Wizards](https://magic.wizards.com/en/rules). Le document consulté annonce une prise d'effet au 7 août 2026 ; sa date interne doit être conservée avec l'empreinte du fichier, indépendamment du nom de téléchargement. [Texte consulté](https://media.wizards.com/2026/downloads/MagicCompRules%2020260819.txt).

**4. Schéma des données canoniques**

Créer les objets suivants sans transformer immédiatement l'inventaire existant. Une couche d'adaptation peut fournir ces objets à partir des tables actuelles et d'un cache d'enrichissement.

| Objet | Champs principaux | Invariant |
|---|---|---|
| Carte de règles | Identifiant canonique, texte canonique, faces, disposition, identité, légalité | La traduction et l'impression ne modifient pas les faits analysés |
| Face ou mode | Identifiant, condition de disponibilité, caractéristiques, capacités | Des modes exclusifs ne sont pas supposés simultanés |
| Impression | Identifiant Scryfall, carte canonique, édition, langue, finition | Une impression ne définit pas à elle seule le rôle fonctionnel |
| Stock | Identifiant d'inventaire, impression ou résolution provisoire, quantité | La quantité ne multiplie pas le nombre de capacités d'une carte |
| Capacité | Source, genre, préconditions, coûts, résultats, restrictions, fréquence | Chaque fait conserve sa provenance et sa portée |
| Référence de combo | Variante, composants, quantités, alternatives, conditions, étapes | Aucun composant n'est supprimé par le classement ou l'affichage |
| Instantané | Source, date de collecte, version, empreinte du contenu | Une exécution peut être reproduite hors réseau |

Lorsque l'identité Oracle est absente, conserver un identifiant provisoire et un statut de résolution. Éviter de fusionner les noms ambigus. La clé de règles de construction et les éventuelles exceptions de noms sont distinctes de la simple déduplication Oracle.

Les tableaux de couleurs vides et les données absentes doivent rester distinguables. La couleur, l'identité de couleur et la production de mana sont trois champs distincts. Une couleur potentiellement produite ne décrit pas ses restrictions d'utilisation.

Le texte agrégé des faces reste utile pour chercher des candidats, mais la validation prend en compte la face et le mode disponibles. Tout champ canonique retenu par l'adaptateur Scryfall devra être vérifié contre son schéma au moment de l'implémentation ; la page de documentation des cartes a renvoyé HTTP 403 lors de cette préparation.

**5. Vocabulaire des capacités : objets, ressources, événements et conditions**

Ne pas utiliser un simple sac de mots-clés comme représentation de référence. Une capacité est un opérateur conditionnel décrit par :

\[
o=(source,mode,variables,preconditions,costs,effects,limits,evidence).
\]

Les variables désignent notamment les objets concernés. Elles portent des contraintes de type, zone, contrôleur, propriétaire et distinction entre objets. Les coûts et effets sont ordonnés lorsqu'ils le nécessitent. Un coût payé n'est pas confondu avec le résultat obtenu à la résolution.

| Catégorie | Exemples de représentation |
|---|---|
| Objet | Créature, carte de créature, jeton de créature, sort sur la pile |
| Ressource consommable | Mana par couleur et restriction, points de vie, carte en main, objet sacrifiable |
| État requis | Source dégagée, mode disponible, objet au cimetière, permission d'activation |
| Événement | Objet créé, sort lancé, sort copié, objet déplacé entre zones |
| Relation entre objets | Une autre créature, objet contrôlé par soi, cible distincte |
| Fréquence | Usage unique, une fois par tour, usage répété si les coûts sont payables |
| Temporalité | Coût, mise en pile, résolution, déclenchement différé, durée de l'effet |

Les événements sont des occurrences, pas un stock consommé par les déclencheurs. Plusieurs capacités peuvent observer le même événement. En revanche, un objet consommé par un coût ne peut pas payer un deuxième coût sans transition intermédiaire qui le rend disponible.

Une capacité synthétique « payer un mana et sacrifier une créature pour piocher » doit décrire le mana et le sacrifice, la créature contrôlée en jeu, l'activation et la pioche à la résolution. Elle ne devient pas un simple opérateur gratuit `créature -> carte`.

Pour le premier prototype, les faits manuels sont prioritaires. Chaque capacité comporte `text_hash`, `source_span`, `extractor_version`, `rule_id`, `annotation_status` et `unsupported_fragments`. Les exemples synthétiques servent à tester le schéma, sans être présentés comme des cartes réelles.

**6. Trois familles initiales et leurs contre-exemples**

| Famille | Relations recherchées | Contre-exemples obligatoires |
|---|---|---|
| Jetons, sacrifice, mort | Production d'objets acceptés par un coût ; événements exploités par un déclencheur | Jeton non-créature ; sacrifice limité à une autre créature ; restriction aux non-jetons ; événement remplacé |
| Cimetière, réanimation | Mise au cimetière d'une carte admissible ; retour dans une zone utile ; bénéfice du retour | Mauvais propriétaire ; mauvaise zone ; type ou valeur de mana interdits ; retour en main confondu avec retour en jeu |
| Lancement et copie de sorts | Lancement alimentant un déclencheur ; copie alimentant un déclencheur de copie | Copie assimilée au lancement ; capacité copiée confondue avec sort copié ; restriction au premier événement du tour |

Les distinctions entre jetons, déclenchements et copies sont contrôlées contre les sections 111, 603 et 707 des [règles consultées](https://media.wizards.com/2026/downloads/MagicCompRules%2020260819.txt). Une copie de sort n'est pas nécessairement lancée : l'opérateur doit décrire ce que l'instruction fait effectivement.

La couverture annoncée est définie par les constructions textuelles reconnues à l'intérieur de ces familles. « Famille sacrifice couverte » ne veut pas dire que toute carte contenant le mot sacrifice est comprise.

**7. Extraction des faits en deux étapes**

Première étape : annoter manuellement des capacités représentatives, puis vérifier que le modèle retrouve les relations attendues à partir de ces annotations. Si cette étape échoue, améliorer la représentation ou le raisonnement avant l'extracteur.

Deuxième étape : construire un extracteur déterministe sur le périmètre retenu. Il segmente les capacités en conservant la structure, identifie coûts et effets, lie les pronoms et objets dans les constructions couvertes, préserve les négations et restrictions, puis produit des opérateurs typés. Les règles d'extraction doivent être versionnées et associées aux fragments reconnus.

Un fragment de texte de rappel doit être identifié comme tel ; l'extracteur ne le compte pas une deuxième fois s'il a déjà développé le mot-clé correspondant. Un mot-clé connu est développé depuis un dictionnaire versionné. Les clauses incomprises sont conservées avec leur portée : une restriction inconnue attachée à un effet empêche de certifier cet effet.

Une carte partiellement comprise peut fournir une relation connue, mais toute affirmation de validité globale doit tenir compte des fragments non analysés pouvant l'affecter. L'absence de règle d'extraction n'est pas un exemple négatif.

Un modèle de langage peut ultérieurement proposer des annotations hors ligne. Ses sorties restent des hypothèses structurées à valider ; elles n'entrent pas directement dans les faits certifiés ni dans une probabilité de réussite.

**8. Correspondance entre productions et besoins**

Construire des correspondances au niveau des capacités. Pour une sortie `p` de A et un besoin `q` de B, chercher une affectation commune des variables telle que types, zones, acteurs et restrictions soient compatibles. La correspondance peut être impossible, conditionnelle ou établie sous les hypothèses affichées.

Il faut distinguer deux vérifications : compatibilité structurelle des capacités et possibilité d'exécution dans l'état fourni. Un producteur de jetons peut correspondre structurellement à un moteur de sacrifice alors qu'aucun jeton n'est encore en jeu.

Chaque relation retourne :

```text
source_card, source_ability, target_card, target_ability
relation_type, supplied_object_or_event, variable_bindings
satisfied_conditions, unsatisfied_conditions, unknown_conditions
evidence, covered_rules, conflicts, interpretation_status
```

Les préconditions d'une capacité sont une conjonction. Fournir une créature ne satisfait pas automatiquement un coût de mana, une condition de dégagement ou une restriction de timing. Les alternatives sont modélisées par des branches complètes ; on ne mélange pas les parties favorables de branches mutuellement exclusives.

`A -> B` et `B -> A` sont stockées séparément. Une relation entrante dans une carte ne peut pas être déduite de la relation inverse. Les rôles de protection, réduction de coût et récupération nécessitent leurs propres règles ; ils ne sont pas automatiquement assimilés à une production de ressources.

**9. Rechercher les candidats sans dépendre du cosinus**

Créer plusieurs index : types d'objets produits ; événements émis ; besoins et événements acceptés ; rôles de préparation ou récupération couverts ; appartenance à des variantes de référence ; caractéristiques textuelles.

Pour une carte A, former l'union :

\[
Cand(A)=Cand_{productions}(A)\cup Cand_{besoins}(A)\cup Cand_{references}(A)\cup Cand_{texte}(A).
\]

La voie textuelle sert d'appui à la découverte. L'absence de mots communs n'élimine pas une relation fonctionnelle. Un candidat trouvé uniquement par le texte reste une affinité jusqu'à l'établissement d'une relation.

Appliquer d'abord les exclusions et contraintes de construction connues, puis analyser les candidats. Conserver séparément les exclusions du contexte et les incompatibilités sémantiques afin de diagnostiquer la perte d'un résultat.

S'il faut plafonner les recherches, allouer des budgets visibles par voie et retourner les voies tronquées. Éviter un plafond basé sur l'ordre des lignes du fichier. Les égalités sont départagées par identifiant canonique.

Pour l'affinité, conserver les caractéristiques brutes et utiliser la même pondération IDF pour toutes les cartes comparées dans une exécution. Une version de corpus fait partie de la clé du cache. Un vecteur nul produit une affinité nulle avec un indicateur de données insuffisantes ; des valeurs non finies sont rejetées.

**10. Représenter les groupes par capacités et dépendances**

Utiliser un graphe biparti ou un hypergraphe : des nœuds représentent objets, événements et conditions ; des opérateurs représentent les capacités. Une projection carte-vers-carte sert à la navigation et à l'affichage, mais ne remplace pas les dépendances détaillées.

Une hyperarête signifie qu'un ensemble de conditions est requis conjointement. Un combo à plusieurs pièces reste une variante complète, même si l'interface ne montre d'abord qu'un résumé.

Pour un groupe P, stocker les cartes et quantités, les capacités utilisées, les dépendances, les éventuelles étapes, les coûts d'entrée, les hypothèses et les conditions non résolues. Les rôles attribués à une même carte peuvent être simultanés ou alternatifs ; cette distinction doit être conservée.

Une carte supplémentaire n'améliore le résultat que si elle fournit une contribution distincte ou une alternative pertinente. Deux chemins de découverte décrivant la même relation ne comptent pas comme deux bénéfices.

La déduplication des groupes porte sur les identités, quantités, mécanisme et conditions. Deux variantes utilisant les mêmes cartes avec des conditions différentes ne sont pas fusionnées uniquement parce que leurs noms correspondent.

**11. Recherche bornée et validation conjointe**

Commencer par une recherche exhaustive sur de petites fixtures. Elle fournit un oracle de comparaison pour la future recherche bornée. Sur les collections plus grandes, utiliser une expansion guidée par les besoins non satisfaits.

```text
initialiser un état de recherche avec les cartes et besoins demandés
tant que la frontière n'est pas vide et que le budget permet une expansion :
    choisir un besoin non satisfait selon une règle déterministe
    chercher les capacités compatibles et leurs prérequis
    créer les branches correspondant aux alternatives
    rejeter les branches contradictoires dans le modèle couvert
    conserver les branches incomplètes avec leurs conditions
    valider conjointement les groupes candidats complets
    mémoriser les états et leur provenance
classer les groupes valides et présenter les groupes conditionnels à part
retourner les budgets atteints et la couverture de la recherche
```

Les paramètres sont distincts : taille maximale du groupe, nombre d'étapes, candidats par voie, largeur de la frontière, nombre d'états explorés et nombre de résultats affichés. Une valeur initiale telle que cinq cartes ou trois étapes est un paramètre de prototype à mesurer, pas une propriété du modèle.

La clé d'un état inclut les objets, modes, quantités, ressources, limites d'usage consommées et contraintes temporelles pertinentes. Un unique tableau global de parents par carte n'est pas une représentation suffisante des différentes branches.

Pour un pont, préciser le contrat : une carte commune contribuant aux deux besoins, ou un petit ensemble qui les couvre conjointement. Dans les deux cas, tous les éléments requis doivent appartenir au package retourné. Modifier le nombre d'explications affichées ne change pas le package.

Si le budget est épuisé, la conclusion est « aucun autre résultat trouvé dans ce budget ». `search_truncated` et `data_truncated` sont deux indicateurs distincts. Un arrêt par budget de nombre d'états est reproductible ; un arrêt par délai peut produire des différences et doit être signalé.

**12. Répétabilité : ajouter un modèle de transitions seulement où il est nécessaire**

Une relation compatible et un cycle du graphe ne prouvent pas une boucle de jeu. Pour les séquences couvertes, définir un état abstrait `x` et une transition partielle `T_o` correspondant à chaque opérateur :

\[
x_{t+1}=T_o(x_t),\qquad T_o(x_t)\text{ défini seulement si les préconditions sont satisfaites.}
\]

La vérification suit l'ordre des coûts et résolutions, les changements de zones, le contrôle, les cibles, les modes et les limites d'usage pertinentes. Les choix adverses ou informations cachées sont des hypothèses ou branches, jamais des réussites supposées.

Un état abstrait omet des détails : il peut donc admettre des chemins impossibles dans le jeu complet. Toute conclusion positive précise les règles représentées et les hypothèses. Une action non prise en charge donne `unknown`, sans saut automatique vers son résultat.

Le bilan de ressources `r_final - r_initial` est un vecteur : mana de chaque catégorie, cartes, objets, vie et utilisations disponibles. Additionner directement une carte, un mana et un point de vie n'a pas de sens sans fonction d'utilité déclarée.

Pour affirmer une répétabilité non bornée dans le modèle, il faut un invariant I et une séquence sigma tels que, pour tout état atteignable de I, la séquence soit exécutable et ramène dans I tout en produisant le résultat annoncé. Vérifier notamment coûts d'amorçage, absence d'épuisement caché, restauration des permissions et limites d'usage. Un retour apparent aux mêmes cartes peut masquer la consommation de la bibliothèque ou d'une ressource finie.

Le premier moteur peut se limiter à « séquence exécutable une fois sous ces hypothèses » ou « répétabilité non évaluée ». Il n'a pas besoin de certifier les boucles arbitraires pour fournir des synergies intéressantes.

**13. Calcul de pertinence sans coefficients arbitraires au départ**

Le classement s'effectue après la vérification des contraintes. Un résultat impossible dans le contexte n'obtient pas simplement un score plus faible : il est exclu de la catégorie concernée, avec une raison consultable. Un résultat conditionnel garde ce statut même si son intérêt potentiel est élevé.

Définir un ensemble fini de besoins explicites B pour la demande : par exemple produire un objet sacrifiable, disposer d'un moyen de le sacrifier et exploiter l'événement. Les besoins sont des prédicats canoniques dédupliqués, afin que le découpage artificiel d'une condition n'augmente pas son poids.

Pour chaque besoin b et groupe P, calculer `s_b(P,C)` dans {vrai, faux, inconnu}, au niveau de contexte annoncé. Avec des poids d'objectif positifs `w_b`, définir une couverture attestée et une couverture potentielle :

\[
Cov_{att}(P,C)=\frac{\sum_{b\in B}w_b\mathbf{1}[s_b=vrai]}{\sum_{b\in B}w_b},
\quad
Cov_{pot}(P,C)=\frac{\sum_{b\in B}w_b\mathbf{1}[s_b\ne faux]}{\sum_{b\in B}w_b}.
\]

Ces indicateurs appartiennent à [0,1] lorsque B n'est pas vide. Si B est vide, retourner « non applicable ». L'intervalle obtenu décrit des informations manquantes ; ce n'est pas un intervalle de probabilité et sa borne haute ne garantit pas que les conditions inconnues puissent être satisfaites conjointement. Un besoin indispensable faux bloque toujours la réalisation, même si la moyenne reste élevée.

Décrire également la contribution marginale d'une carte a :

\[
Gain_{couverture}(a\mid D,C)=Cov_{att}(D\cup\{a\},C)-Cov_{att}(D,C).
\]

Cette mesure sert à comparer une contribution à des besoins fixes. Elle ne mesure pas toute l'utilité d'un deck et ne suffit pas à juger une redondance : une deuxième solution à un besoin déjà couvert peut améliorer la disponibilité ou la résistance à une suppression.

Retourner initialement un vecteur de critères : couverture attestée, couverture potentielle, conditions indispensables non résolues, cartes supplémentaires, ressources d'amorçage, contribution marginale et robustesse évaluée. Les coûts restent détaillés par ressource.

Ordre de classement initial proposé :

1. Séparer résultats établis sous hypothèses et résultats conditionnels.
2. Dans chaque catégorie, favoriser la couverture du besoin principal.
3. Départager selon les autres objectifs explicitement demandés.
4. Appliquer les préférences déclarées de nombre de pièces et de coût.
5. Diversifier les mécanismes présentés, puis départager les égalités par identifiant.

Quand plusieurs critères s'opposent, conserver les solutions non dominées : P domine Q si P est au moins aussi bon sur chaque critère comparable et meilleur sur au moins un. Les résultats comportant des valeurs inconnues non comparables ne reçoivent pas une dominance inventée.

Après constitution d'annotations suffisantes, une somme pondérée peut devenir un modèle expérimental : `S_w = somme(w_j * z_j)`, avec `z_j` normalisés par une transformation versionnée, `w_j >= 0` et `somme(w_j) = 1`. Les poids sont réglés sur les préférences annotées du jeu de réglage. Les contraintes strictes restent hors de cette somme. Tester la sensibilité des rangs aux poids et éviter de recalculer les échelles sur les seuls candidats affichés.

La confiance d'extraction, la présence dans Spellbook, la popularité et la pertinence restent séparées. Aucun pourcentage de confiance n'est affiché avant calibration sur des exemples indépendants. Un bonus de nouveauté ou une diversification ne peut pas promouvoir une interaction invalide.

**14. Combos Spellbook : préserver les variantes et leurs conditions**

L'adaptateur R actuel transmet la réponse et les liens de pagination. Le frontend conserve encore une limite `.slice(0, 4)` dans `computeSpellbookSynergyGroups` et construit des chaînes depuis l'ordre des partenaires. Le chantier doit supprimer cette troncature métier et utiliser les étapes de la référence, sans convertir un ordre de classement en séquence.

Le [projet officiel Commander Spellbook](https://github.com/SpaceCowMedia/commander-spellbook-backend) expose ses données via une API REST. L'implémentation de l'adaptateur s'appuiera sur un schéma ou un client officiel figé, puis sur des réponses enregistrées pour les tests.

Pour chaque variante, conserver l'identifiant, les composants et quantités, les alternatives exprimées, les conditions, étapes, résultats, provenance et instantané brut. Un composant absent de la collection reste représenté avec son statut de manque ; la variante peut être proposée comme piste à compléter. Si l'utilisateur demande uniquement les combos réalisables avec son stock, appliquer ce filtre sans modifier la variante.

Pour chaque composant, comparer la quantité requise à la quantité du deck et de l'inventaire. La pagination, une indisponibilité réseau et une réponse vide complète sont trois situations distinctes. Une référence retrouvée ne certifie pas la légalité du deck ni l'état de jeu.

Validation minimale : retirer successivement chacun des composants ; tester une variante de plus de cinq cartes ; tester deux exemplaires obligatoires ; tester des alternatives ; réduire le nombre de résultats directs et vérifier que la variante reste intacte ; distinguer deux variantes ayant les mêmes cartes mais des conditions différentes.

**15. Amélioration du deck et estimation de jouabilité**

Construire d'abord un diagnostic : besoins couverts, besoins manquants, nombre de solutions par rôle, séquences accessibles sous hypothèses, dépendance à des pièces uniques, métadonnées inconnues. La concentration de tags reçoit un libellé descriptif et ne devient pas une mesure globale de qualité.

Générer les ajouts depuis les besoins manquants et les mécanismes fonctionnels. Générer les retraits depuis les rôles substituables, les contraintes et les préférences. Protéger les cartes imposées par le contexte. Pour une taille de deck fixe :

\[
D'=D-\{r\}+\{a\},\qquad \Delta\mathbf U=\mathbf U(D',C)-\mathbf U(D,C).
\]

`D` est un multiensemble et `U` un vecteur de critères définis. Vérifier la validité de D et de D' ; si D est invalide, distinguer une réparation de construction d'une amélioration stratégique. Recalculer les besoins perdus autant que les besoins gagnés. Les recommandations ne deviennent pas automatiquement positives parce que la carte ajoutée ressemble aux cartes centrales.

Pour les cas simples, la probabilité de voir au moins un exemplaire d'une catégorie après n cartes tirées sans remise peut être calculée par :

\[
Pr(X\ge1)=1-\frac{\binom{N-K}{n}}{\binom{N}{n}},
\]

avec N cartes dans la bibliothèque initiale modélisée, K cartes admissibles, `0 <= K <= N` et `0 <= n <= N`. Employer une implémentation numérique stable, traiter `n > N-K` comme une probabilité de 1 et documenter les cartes exclues de la bibliothèque. Cette formule ne couvre ni mulligan, ni tutorisation, ni disponibilité effective de mana.

Pour plusieurs pièces requises, ne pas multiplier des probabilités marginales comme si elles étaient indépendantes. Utiliser un dénombrement conjoint sur les cas simples ou une simulation reproductible pour les scénarios plus riches. Fixer alors horizon, règles de pioche, mulligan, politique de jeu, restrictions des sources et graine aléatoire. Comparer avant et après sur les mêmes scénarios de tirage lorsque possible, et publier l'incertitude de simulation.

Définir précisément la robustesse évaluée : par exemple, couverture restante après le retrait de chaque pièce non imposée, ou nombre de solutions alternatives admissibles. Cela n'est pas une estimation de résistance à toutes les interactions adverses.

**16. Explication produite par le moteur**

Chaque résultat affiche le bénéfice recherché, les relations qui le justifient, les coûts d'entrée, les conditions satisfaites, les manques, les inconnues et la portée de la vérification. Le frontend rend ces données sans recalculer un autre score.

Exemple synthétique :

```text
Proposition : Générateur A + Sacrificateur B + Déclencheur C
Objectif : convertir des créatures disponibles en pioche

A produit le type de créature accepté par B.
B permet de sacrifier cette créature ; C observe l'événement compatible.
Coût supplémentaire : un mana pour activer B.
Condition : C doit être présent au moment pertinent.
Stock : A et B disponibles ; C absent de la collection sélectionnée.
Statut : relations établies sur les annotations ; état de jeu non fourni.
Répétabilité : non évaluée.
```

Cet exemple décrit des cartes fictives et des annotations contrôlées. Pour les cartes réelles, chaque ligne fonctionnelle pointe vers les capacités et fragments source utilisés. Une explication ne mentionne pas une carte extérieure au groupe sans la marquer explicitement comme condition ou pièce manquante.

Le graphe fonctionnel peut contenir des cycles. L'arbre de provenance d'un résultat doit rester parcourable sans boucle infinie ; une répétition est représentée par une référence explicite à une séquence, pas par des parents cycliques.

**17. Jeu de référence et évaluation de la pertinence**

Constituer un premier jeu de conception avec environ 45 cartes, 15 par famille. Pour chaque famille, viser 15 relations positives et 15 contre-exemples proches. Ajouter environ 20 variantes de référence, 10 groupes synthétiques et 5 contextes de decks. Ces volumes sont des cibles de démarrage ajustables, pas une preuve statistique de performance.

Chaque annotation conserve identité, instantané, capacités attendues, relation dirigée, restrictions, résultat attendu, justification, auteur et statut de revue. Distinguer désaccord sur les règles et préférence stratégique. Prévoir une seconde relecture humaine pour les cas de référence déterminants.

Créer ensuite un jeu de réglage et un jeu d'évaluation réservés. Les impressions d'une même carte ne sont pas réparties entre entraînement et test. Regrouper également les variantes très proches d'un même mécanisme pour limiter les fuites ; une évaluation de généralisation exige des structures ou familles non utilisées pour écrire les règles. Si les données sont trop rares pour ce découpage, annoncer une évaluation exploratoire au lieu d'une validation générale.

| Niveau | Mesures | Ce que cela vérifie |
|---|---|---|
| Extraction | Exactitude des acteurs, zones, coûts, événements, restrictions ; couverture | Compréhension des textes dans le périmètre |
| Candidats | Rappel à k par voie, avec dénominateur annoté explicite | Capacité à retrouver les interactions sans mots communs |
| Relations | Précision, rappel, taux de fausse affirmation certaine | Validité des liens dirigés |
| Groupes | Composants exacts, conditions préservées, comparaison exhaustive | Cohérence conjointe des propositions |
| Classement | Précision à k et préférence annotée entre résultats | Utilité des premières propositions |
| Incertitude | Abstention, couverture, erreurs parmi les affirmations établies | Capacité à reconnaître les limites |
| Deck | Validité des remplacements, critères avant/après, avis réservé | Intérêt contextuel et fonctions perdues |
| Exécution | Temps médian et p95, mémoire, états explorés | Coût réel pour plusieurs tailles de collection |

Ne pas traiter toute paire non annotée comme négative. Comparer aux références simples : ancien moteur, affinité seule, rôles seuls, références seules. Retirer successivement chaque composante pour mesurer son apport. Publier les résultats par famille afin qu'une famille facile ne masque pas les erreurs d'une autre.

Critères de passage : tous les invariants et contre-exemples critiques passent ; aucune nouvelle erreur critique connue sur le périmètre livré ; amélioration mesurée du classement sur les exemples réservés ; couverture et abstention publiées. Fixer les seuils chiffrés après le pilote et avant l'ouverture du jeu réservé. Un jeu de quelques dizaines de cartes ne permet pas d'annoncer un pourcentage de qualité universel.

**18. Invariants et tests discriminants**

1. Changer la langue ou l'impression ne change pas les faits canoniques.
2. Représenter le même stock par une ou plusieurs lignes ne change pas le profil.
3. Permuter les cartes ne change pas le classement hors égalités explicitement définies.
4. Fournir un coût ne le paye pas automatiquement ; une ressource consommable n'est pas dépensée deux fois.
5. Les restrictions « autre », contrôleur, type, zone et fréquence changent effectivement les résultats.
6. Deux consommateurs d'une ressource ne deviennent pas producteurs l'un pour l'autre.
7. Une sortie sans mots communs avec un besoin compatible reste découvrable.
8. Une carte manquante dans un combo reste visible ; la référence n'est jamais amputée.
9. La limite d'affichage ne change ni score métier, ni composants, ni conditions.
10. Une condition indispensable fausse ne peut être compensée par popularité ou affinité.
11. Une limite d'usage consommée bloque une répétition qui en dépend.
12. Un gain net positif ne prouve pas que le coût initial est payable.
13. Les modes incompatibles ne sont pas utilisés simultanément par la même instance.
14. Les données ou règles inconnues restent inconnues après sérialisation API.
15. Le résultat R direct et le résultat API sont équivalents sur le même instantané.
16. La recherche bornée indique ses limites et est comparée à l'exhaustif sur petits cas.

**19. Architecture proposée dans mana-engine**

Les fichiers ci-dessous sont des modules à créer, pas des composants déjà implémentés.

| Module proposé | Responsabilité |
|---|---|
| `R/analysis_context.R` | Validation du contexte, règles de construction et inconnues |
| `R/analysis_cards.R` | Adaptation canonique, identités, faces et modes |
| `R/analysis_abilities.R` | Schéma des capacités et validation des annotations |
| `R/analysis_extract.R` | Extraction déterministe et preuves textuelles |
| `R/analysis_candidates.R` | Index et union des voies de découverte |
| `R/analysis_relations.R` | Unification des objets et compatibilités dirigées |
| `R/analysis_groups.R` | Dépendances, recherche bornée, quantités et alternatives |
| `R/analysis_transitions.R` | Validation des séquences dans le périmètre couvert |
| `R/analysis_ranking.R` | Critères, dominance, classement et diversification |
| `R/analysis_deck.R` | Diagnostic et comparaison des remplacements |
| `R/query_analysis_*.R` | Adaptateurs des appels API, sans logique métier dupliquée |
| `tests/testthat/fixtures/analysis/` | Instantanés, annotations et résultats attendus |
| `dev/evaluate-analysis.R` | Évaluation reproductible et comparaison des versions |

Faire évoluer `R/query_reference_spellbook.R` vers un adaptateur conservant les variantes complètes. Garder `R/bridge_synergy.R` disponible pour son mode historique d'affinité tant que ses utilisateurs n'ont pas migré.

Les routes proposées sont des POST versionnés, par exemple `/analysis/v1/synergies`, `/analysis/v1/combos`, `/analysis/v1/bridges` et `/analysis/v1/deck`. Elles reçoivent un contexte et des identifiants résolus côté serveur. Elles retournent versions des données, extraction et classement, résultats structurés, inconnues et budgets. Les chemins de fichiers arbitraires ne constituent pas l'interface du nouveau moteur.

L'interface gère chargement, annulation logique des réponses périmées, erreurs et changements de contexte. Elle distingue les catégories de résultat et affiche les composantes utiles, sans exposer les détails d'implémentation au joueur.

**20. Performance, caches et maîtrise de la recherche**

Éviter de comparer toutes les paires d'une collection, ce qui croît quadratiquement avec le nombre de cartes. Les index proposent un sous-ensemble ; mesurer son rappel avant de réduire les budgets. La recherche de groupes est combinatoire : les bornes et les heuristiques doivent être explicites.

Extraire les capacités une fois par empreinte de texte et version d'extracteur. Mettre en cache séparément les compatibilités indépendantes du deck et les validations dépendantes du contexte. Les clés comprennent versions pertinentes, identités, modes et paramètres. Un changement de stock peut invalider la disponibilité sans imposer une nouvelle extraction Oracle.

Mesurer séparément normalisation, extraction, génération de candidats, relations, recherche et sérialisation, à froid et à chaud. Tester des corpus de tailles croissantes et plusieurs densités de relations. Le nombre de cartes seul ne décrit pas toute la difficulté.

Ne promettre aucun gain de vitesse avant ces mesures. Une meilleure recherche peut coûter davantage que le cosinus actuel tout en donnant des propositions plus utiles. Le budget de performance sera choisi à partir des parcours réels et des mesures p95.

**21. Ordre d'implémentation et conditions de fin**

| Étape | Travail concret | Dépendance | Condition de fin |
|---|---|---|---|
| A — Référence | Figer code, fixtures, observations et commandes ; rendre les tests R exécutables | Aucune | État initial reproduit ; aucun test R présenté comme passé sans exécution |
| B — Contrats | Définir contexte, prédicats, schéma des capacités, catégories de résultats | A | Exemples d'entrée/sortie validés ; inconnues et modes explicites |
| C — Annotations | Annoter les trois familles et leurs contre-exemples | B | Chaque relation attendue possède ses preuves et conditions |
| D — Relations manuelles | Implémenter candidats par rôles et compatibilités sur annotations | C | Relations positives et contre-exemples critiques passent |
| E — Références complètes | Adapter Spellbook, conserver pièces, conditions et pagination | B | Variantes intactes, y compris plus de cinq cartes et quantités multiples |
| F — Classement | Implémenter besoins, couverture et critères séparés | D | Classement déterministe et explication de chaque critère |
| G — Extracteur | Produire automatiquement les annotations du périmètre | C, D | Erreurs d'extraction mesurées ; clauses inconnues préservées |
| H — Groupes et ponts | Recherche exhaustive de référence, puis recherche bornée | D, E, F | Validation conjointe, limites et provenance vérifiées |
| I — Séquences limitées | Transitions sur un sous-ensemble annoncé | H | Coûts, modes et limites contrôlés ; abstention hors périmètre |
| J — API et interface | Exposer puis afficher les résultats du moteur R | F, G ; H pour groupes | Parité R/API et parcours navigateur vérifiés |
| K — Deck | Diagnostic, remplacements et premières estimations de disponibilité | H, J | Validité et bilan avant/après contrôlés |
| L — Évaluation et bascule | Mesures réservées, performances, décision par tâche | J ; K pour deck | Gains documentés ; retour au mode précédent disponible |

E peut avancer indépendamment de C et D après B. La consultation des références complètes et les premières relations utiles peuvent être livrées avant I : le moteur de transitions n'est pas un préalable à toute synergie.

Trois jalons utilisables : premier jalon avec références complètes et relations expliquées sur annotations ; deuxième avec extraction du périmètre, groupes et ponts ; troisième avec remplacements contextualisés. Le jeu de référence et les vérifications accompagnent chaque jalon.

Avant toute bascule frontend, réconcilier les fonctionnalités présentes dans `inst/www` et `frontend/src`, construire dans un dossier isolé et vérifier les parcours existants. Ne pas relancer un build qui efface les assets distribués avant cette réconciliation. Conserver un mode expérimental et comparer les anciens et nouveaux résultats sur les mêmes instantanés.

Toute migration persistante s'effectue d'abord sur une copie : comparer nombres de lignes, identités, quantités et conflits ; tester la restauration. Les annotations dérivées peuvent commencer dans un cache séparé afin de réduire la portée de la migration initiale.

Les estimations antérieures en nombre de lignes ne constituent pas une base fiable de chiffrage. Après D et E, mesurer le coût d'une famille complète et d'une intégration avant d'estimer le reste. La difficulté principale est la portée des règles correctement représentées, puis la qualité des annotations.

**22. Définition d'une première version réussie**

La première version est réussie si elle retrouve des partenaires complémentaires même sans proximité textuelle, conserve toutes les conditions des références, explique les contributions et refuse les contre-exemples du périmètre. Elle doit rendre visibles ses inconnues et produire des résultats stables sous changement de langue, impression, ordre et représentation du stock.

L'amélioration attendue est une hausse de la pertinence des propositions et une baisse des affirmations injustifiées. Son ampleur devra être mesurée. Une meilleure méthode de représentation ne constitue pas, à elle seule, une preuve d'amélioration du taux de victoire.
