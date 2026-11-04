---
sidebar_position: 18
title: Game Center
---

# Game Center

Les succès, classements et groupes de classements d’une app, avec leurs langues, images et leur ordre. Chacun est désigné par son **ID** (le vendor identifier qu’utilise le jeu), son nom de référence ou son identifiant Apple.

Leurs textes et images appartiennent à une **version**. Un nouveau succès, classement ou groupe commence avec la version 1 en Prepare for Submission, et une version part en App Review avec l’app. Pour modifier un élément déjà publié, la commande crée d’abord sa version suivante, après confirmation.

## Activer Game Center

```bash
ascelerate game-center <bundle-id>                      # activé ou non, nombres, classement par défaut
ascelerate game-center enable <bundle-id>
ascelerate game-center version <bundle-id> --enabled true   # l’interrupteur Game Center de la version App Store
```

L’API App Store Connect ne peut pas désactiver Game Center pour une app une fois activé. Le bundle ID doit avoir la fonctionnalité Game Center. `version` agit sur la version en préparation ou sur celle qu’indique `--version`.

## Succès

```bash
ascelerate game-center achievements <bundle-id> [--json]
ascelerate game-center achievements info <bundle-id> first.win
ascelerate game-center achievements create <bundle-id> --id first.win --name "First Win" --points 10 [--hidden] [--repeatable]
ascelerate game-center achievements update <bundle-id> first.win --points 20 --hidden false
ascelerate game-center achievements update <bundle-id> first.win --archived true
ascelerate game-center achievements delete <bundle-id> first.win
```

Les succès d’une app se partagent 1 000 points, et chacun en donne de 1 à 100. `--hidden` garde un succès caché jusqu’à ce qu’un joueur l’obtienne. Un succès déjà publié ne peut pas être supprimé ; archivez-le à la place.

## Classements

```bash
ascelerate game-center leaderboards <bundle-id> [--json]
ascelerate game-center leaderboards create <bundle-id> --id high.score --name "High Score"
ascelerate game-center leaderboards create <bundle-id> --id weekly.time --name "Weekly Time" \
  --formatter elapsed-time-second --sort low --submission recent --min 0 --max 3600 \
  --recurrence-start 2026-12-07T00:00:00Z --recurrence-duration PT168H --recurrence-rule "FREQ=DAILY;INTERVAL=7"
ascelerate game-center leaderboards update <bundle-id> weekly.time --hidden true
ascelerate game-center leaderboards default <bundle-id> high.score
```

Par défaut, les scores sont des entiers, les plus élevés passent en premier et le meilleur score de chaque joueur compte. `--formatter` accepte `integer`, de `decimal-point-1-place` à `decimal-point-3-place`, `elapsed-time-centisecond`, `elapsed-time-second`, `elapsed-time-minute` ou une devise comme `money-dollar-decimal`.

Un classement récurrent repart de zéro à intervalles réguliers. La durée s’exprime en heures ou en minutes (`PT24H`, ou `PT168H` pour une semaine), et la règle se répète en minutes, heures ou jours (`FREQ=DAILY;INTERVAL=7` recommence chaque semaine). Une plage de scores ne s’efface qu’en entier, avec `--min "" --max ""`.

Le premier classement devient celui par défaut, sur lequel s’ouvre Game Center ; `default` le change.

## Groupes de classements

```bash
ascelerate game-center sets <bundle-id>
ascelerate game-center sets create <bundle-id> --id all.scores --name "All Scores" --leaderboards high.score,weekly.time
ascelerate game-center sets update <bundle-id> all.scores --leaderboards weekly.time,high.score
```

`--leaderboards` définit les classements d’un groupe dans cet ordre, à la place des actuels.

## Langues et images

Les succès, classements et groupes ont les mêmes commandes de langues et d’images ; remplacez `achievements` par `leaderboards` ou `sets` :

```bash
ascelerate game-center achievements localizations <bundle-id> first.win
ascelerate game-center achievements localizations set <bundle-id> first.win --locale en-US \
  --name "First Win" --before-earned "Win a round." --after-earned "You won a round."
ascelerate game-center achievements localizations export <bundle-id> first.win --output first-win.json
ascelerate game-center achievements localizations import <bundle-id> first.win --file first-win.json
ascelerate game-center achievements localizations delete <bundle-id> first.win --locale tr

ascelerate game-center achievements image upload <bundle-id> first.win --locale en-US icon.png
ascelerate game-center achievements image delete <bundle-id> first.win --locale en-US
```

Une nouvelle langue d’un succès demande son nom et ses deux descriptions. Une langue d’un classement a un nom, une description facultative, son propre `--formatter` et l’unité qui suit un score (`--suffix " points"`, `--suffix-singular " point"`). Une langue d’un groupe a un nom.

Une image appartient à une langue. Elle doit être carrée et faire au moins 512 × 512 (le plus souvent 512 × 512 ou 1024 × 1024), en PNG ou JPEG. Le téléversement remplace l’image actuelle de la langue et attend la vérification d’Apple, si bien qu’une image refusée est signalée aussitôt.

## Ordre et App Review

```bash
ascelerate game-center achievements reorder <bundle-id> first.win,high.five
ascelerate game-center achievements submit <bundle-id> first.win [--platform ios]
```

`reorder` place en tête ceux qui sont indiqués, dans cet ordre ; les autres suivent tels quels. `submit` ajoute la nouvelle version de l’élément au brouillon de soumission de l’app (en créant un s’il n’y en a pas). Elle part en App Review quand vous soumettez le brouillon avec `ascelerate apps review submit`.

## Matchmaking

Le matchmaking à base de règles appartient à l’équipe, pas à une app, donc ces commandes ne prennent pas de bundle ID. Un **ensemble de règles** fixe le nombre de joueurs, les règles et les équipes ; une **file d’attente** est l’endroit où les jeux envoient leurs demandes de partie, qu’elle met en relation avec un ensemble de règles. Ensembles de règles et files d’attente sont désignés par leur nom de référence ou leur ID.

```bash
ascelerate game-center matchmaking rule-sets [--json]
ascelerate game-center matchmaking rule-sets create --name Ranked --min 2 --max 4
ascelerate game-center matchmaking rule-sets info Ranked
ascelerate game-center matchmaking rules add Ranked --name SameVersion --type compatible \
  --expression "requests[0].appVersion == requests[1].appVersion" --description "Same app version"
ascelerate game-center matchmaking rules add Ranked --name Skill --type distance \
  --expression "requests[0].properties.skill" --description "Close skill" --weight 2
ascelerate game-center matchmaking teams add Ranked --name Red --min 1 --max 2
ascelerate game-center matchmaking queues create --name RankedQueue --rule-set Ranked [--experiment-rule-set RankedB] [--classic-apps com.example.MyApp]
ascelerate game-center matchmaking queues update RankedQueue --experiment-rule-set none
ascelerate game-center matchmaking test Ranked --file requests.json
```

Les règles s’écrivent dans le langage de règles d’Apple, basé sur JMESPath (qui n’a pas d’opérateurs arithmétiques). Une règle de compatibilité (compatible) compare `requests[0]` à `requests[1]` ; une règle de distance (distance) donne un nombre pour `requests[0]`, et les demandes aux nombres les plus proches sont réunies en premier. Les propriétés d’un joueur se lisent comme `requests[0].properties.<clé>`. App Store Connect ne vérifie que la syntaxe d’une expression à l’enregistrement ; testez donc un ensemble de règles avant de l’utiliser.

`test` fait passer des demandes d’exemple par un ensemble de règles et montre les parties qu’Apple formerait, avec l’équipe de chaque joueur ; rien n’est enregistré. Le fichier est un tableau JSON :

```json
[
  {"requestName": "alice", "bundleId": "com.example.MyApp", "platform": "IOS", "appVersion": "1.0",
   "secondsInQueue": 5, "locale": "EN-US", "players": [{"playerId": "alice", "properties": {"skill": "10"}}]},
  {"requestName": "bob", "bundleId": "com.example.MyApp", "platform": "IOS", "appVersion": "1.0",
   "secondsInQueue": 8, "locale": "EN-US", "players": [{"playerId": "bob", "properties": {"skill": "12"}}]}
]
```

Une demande peut aussi indiquer `latitude`, `longitude`, `playerCount`, `minPlayers` et `maxPlayers`. Un ensemble de règles utilisé par une file d’attente ne peut pas être supprimé ; modifiez ou supprimez d’abord la file.
