# Calculateur serveur et assistant ChatGPT

Le parcours Strategy utilise désormais `/analysis/v1/synergies` et
`/analysis/v1/groups`. Les recommandations de deck interrogent le même moteur,
et le générateur classe ses candidats à partir de ses relations fonctionnelles.
Le score lexical global « synergie /100 » n’est plus affiché. Les anciennes
fonctions JavaScript restent présentes pour les probes historiques, mais ne
sont plus appelées par ces parcours. Les endpoints R historiques restent
compatibles pour les clients externes.

Le moteur est expérimental : une interaction non détectée n’est pas une
interaction impossible. Ses résultats distinguent relations, conditions
inconnues et recherche tronquée. Ce n’est pas un simulateur de parties.
Strategy recherche les groupes parmi la carte choisie et les candidats affichés
(budget de 1 200 paires). Commander Spellbook reste une source externe séparée.
Les recommandations de deck analysent chaque carte contre un sous-ensemble
de la collection, limité à 1 200 paires. Le nombre de candidats examinés est
affiché ; les candidats sont pris dans l’ordre de la collection. L’identité du commandant et
la légalité complète restent à vérifier lorsque les métadonnées sont absentes.

## Lancement local avec assistant

Prérequis : Node.js 20+, R avec les dépendances du projet et `pkgload`, et le
binaire officiel `codex` dans le PATH. Si nécessaire, définir
`$env:MANA_CODEX_BIN = 'chemin complet vers codex.exe'`.

Depuis la racine, dans PowerShell :

```powershell
node scripts/run-with-assistant.mjs
```

Ouvrir **http://127.0.0.1:8012/ui**. Le script lance sa propre API locale sur
8013 ; choisir d’autres ports avec `-Port` et `-ApiPort` s’ils sont occupés.
Ctrl+C arrête ce lancement. Les logs API se trouvent dans `.local-data`.

Pour une API déjà lancée et à jour :

```powershell
$env:MANA_API_URL = 'http://127.0.0.1:8010'
node scripts/assistant-server.mjs
```

Le lancement autonome habituel `scripts/run-api.R` continue de fonctionner
sans Codex ni connexion ChatGPT. Il charge désormais le code du checkout avec
`pkgload`, pour éviter un mélange entre ancien package installé et nouveaux
fichiers. Après modification du moteur R, redémarrer le serveur.

## Utilisation

Dans Strategy :

1. Cliquer sur **Connecter ChatGPT**, puis suivre le lien de connexion officiel.
2. Après connexion, cliquer sur **Vérifier la connexion**.
3. Choisir l’action et les réglages de la page, puis cocher **Utiliser ChatGPT avec ces réglages**.
4. Lancer **Calculer** ou **Construire le deck**. Aucun prompt à rédiger.

Case décochée : seuls les calculs autonomes sont exécutés.
Pour **Analyser les synergies**, le moteur calcule d’abord, puis Codex interprète
les résultats en tenant compte de la carte choisie, de la collection, du filtre
mana, des limites d’affichage et de l’option Spellbook.

Pour **Construire un deck Commander**, la carte choisie devient le commandant.
L’option de cartes connues autorise le catalogue externe ; sinon seules les
cartes possédées dans la collection choisie sont autorisées, commandant compris.
Le type de créatures peut être libre ou limité aux Murs (hors commandant).
L’identité du commandant détermine les couleurs. Les réglages mana, Spellbook
et limites d’affichage de synergies ne contraignent pas cette construction.
Le format est Commander à 100 cartes, avec exclusion des cartes connues bannies.
Cette page ne propose pas encore de contrainte de prix ou de bracket.

Le serveur prépare une liste et un catalogue de candidats. L’IA reçoit ces
données et les réglages structurés, puis propose jusqu’à douze remplacements
en conservant les rôles de la liste (terrains, pioche, ramp, etc.). Le serveur
contrôle les noms, couleurs, types, propriété et quantités, puis relance le
calculateur sur la liste ajustée. Une proposition invalide bénéficie d’une
correction, puis est rejetée si elle reste invalide : la liste autonome est
alors conservée avec un avertissement. Une erreur de l’IA après préparation
conserve également la liste autonome. Les terrains de base peuvent être
répétés dans la limite de leur disponibilité en mode collection uniquement.

Le résultat contient les changements motivés, le rapport recalculé et un bouton
de téléchargement au format texte. Il ne remplace aucun deck enregistré.
L’orchestration est bornée et ne donne pas à l’IA un accès libre à la machine.
Les conversations ChatGPT existantes ne sont pas récupérées.

La connexion passe par [Codex App Server](https://learn.chatgpt.com/docs/app-server),
avec l’authentification ChatGPT gérée officiellement par Codex. Les conditions
d’accès et quotas du compte s’appliquent ; aucune clé API n’est demandée.
Les cartes et contraintes sont transmises à OpenAI seulement lors de l’analyse
assistée. L’authentification est isolée dans `.local-data/assistant-codex`,
ignorée par Git, et ne copie pas la session de votre IDE.

La passerelle est destinée à **un utilisateur sur sa machine**, sur loopback.
Elle refuse les origines étrangères et les demandes d’actions externes de
l’assistant. Ne pas la publier derrière un proxy partagé : une application
multiutilisateur nécessiterait des sessions et comptes isolés par utilisateur.

## Vérifications

```powershell
node --test tests/assistant.test.mjs tests/deck-assistant.test.mjs
node docs/audit/probes-js.cjs
cd frontend
npm run build
```

Les tests R passent par `testthat::test_local('.')`. Les tests de protocole ne
consomment pas de quota : une analyse réelle exige votre connexion ChatGPT.
