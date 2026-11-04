---
sidebar_position: 18
title: Game Center
---

# Game Center

Die Erfolge, Bestenlisten und Bestenlistengruppen einer App mit ihren Sprachen, Bildern und ihrer Reihenfolge. Jedes Element wird über seine **ID** (den Vendor Identifier, den das Spiel verwendet), seinen Referenznamen oder seine Apple-ID angegeben.

Texte und Bilder gehören zu einer **Version**. Ein neuer Erfolg, eine neue Bestenliste oder Gruppe beginnt mit Version 1 im Status „Prepare for Submission“, und eine Version geht zusammen mit der App zum App Review. Um ein bereits veröffentlichtes Element zu ändern, legt der Befehl nach einer Rückfrage zuerst dessen nächste Version an.

## Game Center aktivieren

```bash
ascelerate game-center <bundle-id>                      # an oder aus, Anzahlen, Standard-Bestenliste
ascelerate game-center enable <bundle-id>
ascelerate game-center version <bundle-id> --enabled true   # der Game-Center-Schalter der App-Store-Version
```

Die App Store Connect API kann Game Center für eine App nicht wieder deaktivieren, sobald es aktiv ist. Die Bundle-ID braucht die Game-Center-Fähigkeit. `version` arbeitet mit der Version in Vorbereitung oder mit der, die `--version` angibt.

## Erfolge

```bash
ascelerate game-center achievements <bundle-id> [--json]
ascelerate game-center achievements info <bundle-id> first.win
ascelerate game-center achievements create <bundle-id> --id first.win --name "First Win" --points 10 [--hidden] [--repeatable]
ascelerate game-center achievements update <bundle-id> first.win --points 20 --hidden false
ascelerate game-center achievements update <bundle-id> first.win --archived true
ascelerate game-center achievements delete <bundle-id> first.win
```

Die Erfolge einer App teilen sich 1.000 Punkte, und ein Erfolg vergibt 1 bis 100. `--hidden` hält einen Erfolg verborgen, bis ein Spieler ihn erreicht. Ein bereits veröffentlichter Erfolg kann nicht gelöscht werden; archivieren Sie ihn stattdessen.

## Bestenlisten

```bash
ascelerate game-center leaderboards <bundle-id> [--json]
ascelerate game-center leaderboards create <bundle-id> --id high.score --name "High Score"
ascelerate game-center leaderboards create <bundle-id> --id weekly.time --name "Weekly Time" \
  --formatter elapsed-time-second --sort low --submission recent --min 0 --max 3600 \
  --recurrence-start 2026-12-07T00:00:00Z --recurrence-duration PT168H --recurrence-rule "FREQ=DAILY;INTERVAL=7"
ascelerate game-center leaderboards update <bundle-id> weekly.time --hidden true
ascelerate game-center leaderboards default <bundle-id> high.score
```

Standardmäßig sind Punktzahlen ganze Zahlen, höhere Punktzahlen stehen vorn, und es zählt die beste Punktzahl jedes Spielers. `--formatter` nimmt `integer`, `decimal-point-1-place` bis `decimal-point-3-place`, `elapsed-time-centisecond`, `elapsed-time-second`, `elapsed-time-minute` oder eine Währung wie `money-dollar-decimal`.

Eine wiederkehrende Bestenliste beginnt regelmäßig von vorn. Die Dauer wird in Stunden oder Minuten angegeben (`PT24H` oder `PT168H` für eine Woche), und die Regel wiederholt sich nach Minuten, Stunden oder Tagen (`FREQ=DAILY;INTERVAL=7` beginnt wöchentlich neu). Ein Punktebereich wird nur als Ganzes gelöscht, mit `--min "" --max ""`.

Die erste Bestenliste wird zur Standard-Bestenliste, mit der Game Center öffnet; `default` ändert das.

## Bestenlistengruppen

```bash
ascelerate game-center sets <bundle-id>
ascelerate game-center sets create <bundle-id> --id all.scores --name "All Scores" --leaderboards high.score,weekly.time
ascelerate game-center sets update <bundle-id> all.scores --leaderboards weekly.time,high.score
```

`--leaderboards` legt die Bestenlisten einer Gruppe in dieser Reihenfolge fest und ersetzt die bisherigen.

## Aktivitäten

Eine Aktivität ist ein Teil des Spiels, etwa ein Level oder ein Modus, in den Spieler direkt eingeladen werden können. Ihre Erfolge und Bestenlisten sind die, die zu ihr gehören.

```bash
ascelerate game-center activities <bundle-id> [--json]
ascelerate game-center activities create <bundle-id> --id duel --name "Duel" --play-style sync \
  --min-players 2 --max-players 2 [--party-code true] [--properties mode=duel] [--fallback-url https://example.com/duel]
ascelerate game-center activities update <bundle-id> duel --max-players 4 --fallback-url ""
ascelerate game-center activities link <bundle-id> duel --achievements first.win --leaderboards high.score
ascelerate game-center activities link <bundle-id> duel --leaderboards high.score --remove
```

`--play-style` ist `sync` (Spieler spielen gemeinsam) oder `async` (abwechselnd). `--properties` ersetzt die eigenen Schlüssel-Wert-Eigenschaften des Spiels für die Aktivität. Die Fallback-URL ist eine Webseite für Spieler ohne das Spiel; sie gehört zur neuesten Version.

## Herausforderungen

Mit einer Herausforderung fordern Spieler Freunde heraus, eine Punktzahl auf einer der Bestenlisten der App zu schlagen.

```bash
ascelerate game-center challenges <bundle-id> [--json]
ascelerate game-center challenges create <bundle-id> --id beat.score --name "Beat My Score" --leaderboard high.score --repeatable
ascelerate game-center challenges update <bundle-id> beat.score --leaderboard weekly.best
```

Die Regeln von App Store Connect, die die Befehle vorab prüfen: Eine Bestenliste hat höchstens eine Herausforderung, sie muss die beste Punktzahl jedes Spielers zählen, und eine Herausforderung ohne `--repeatable` braucht eine wiederkehrende Bestenliste.

## Sprachen und Bilder

Erfolge, Bestenlisten, Gruppen, Aktivitäten und Herausforderungen haben dieselben Sprach- und Bildbefehle; ersetzen Sie `achievements` durch `leaderboards`, `sets`, `activities` oder `challenges`:

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

Eine neue Sprache eines Erfolgs braucht den Namen und beide Beschreibungen. Eine Sprache einer Bestenliste hat einen Namen, eine optionale Beschreibung, einen eigenen `--formatter` und die Einheit nach einer Punktzahl (`--suffix " points"`, `--suffix-singular " point"`). Eine Sprache einer Gruppe hat einen Namen, eine Sprache einer Aktivität oder Herausforderung einen Namen und eine Beschreibung (`--name`, `--description`).

Ein Bild gehört zu einer Sprache. Für Erfolge, Bestenlisten und Gruppen muss es quadratisch und mindestens 512 × 512 groß sein (üblich sind 512 × 512 oder 1024 × 1024), für Aktivitäten und Herausforderungen genau 3840 × 2160; deren Versionen nehmen außerdem ein Standardbild (`image upload --default`). PNG oder JPEG. Der Upload ersetzt das aktuelle Bild und wartet auf Apples Prüfung, sodass ein abgelehntes Bild sofort gemeldet wird.

## Reihenfolge und App Review

```bash
ascelerate game-center achievements reorder <bundle-id> first.win,high.five
ascelerate game-center achievements submit <bundle-id> first.win [--platform ios]
```

`reorder` (Erfolge, Bestenlisten und Gruppen) stellt die aufgeführten Elemente in dieser Reihenfolge an den Anfang; die übrigen folgen unverändert. `submit` fügt die neue Version des Elements dem Einreichungsentwurf der App hinzu (und legt einen an, wenn es keinen gibt). Sie geht zum App Review, wenn Sie den Entwurf mit `ascelerate apps review submit` einreichen.

## Matchmaking

Regelbasiertes Matchmaking gehört zum Team, nicht zu einer einzelnen App, daher nehmen diese Befehle keine Bundle-ID. Ein **Regelsatz** legt die Spielerzahl, die Regeln und die Teams fest; eine **Warteschlange** ist der Ort, an den Spiele ihre Match-Anfragen senden, und sie gleicht sie mit einem Regelsatz ab. Regelsätze und Warteschlangen werden über Referenznamen oder ID angegeben.

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

Regeln werden in Apples Regelsprache geschrieben, die auf JMESPath beruht (das keine Rechenoperatoren kennt). Eine Kompatibilitätsregel (compatible) vergleicht `requests[0]` mit `requests[1]`; eine Distanzregel (distance) liefert eine Zahl für `requests[0]`, und Anfragen mit näher beieinanderliegenden Zahlen werden zuerst zusammengeführt. Die Eigenschaften eines Spielers werden als `requests[0].properties.<Schlüssel>` gelesen. App Store Connect prüft beim Speichern nur die Syntax eines Ausdrucks; testen Sie einen Regelsatz daher, bevor Sie ihn verwenden.

`test` schickt Beispielanfragen durch einen Regelsatz und zeigt die Matches, die Apple bilden würde, mit dem Team jedes Spielers; es wird nichts gespeichert. Die Datei ist ein JSON-Array:

```json
[
  {"requestName": "alice", "bundleId": "com.example.MyApp", "platform": "IOS", "appVersion": "1.0",
   "secondsInQueue": 5, "locale": "EN-US", "players": [{"playerId": "alice", "properties": {"skill": "10"}}]},
  {"requestName": "bob", "bundleId": "com.example.MyApp", "platform": "IOS", "appVersion": "1.0",
   "secondsInQueue": 8, "locale": "EN-US", "players": [{"playerId": "bob", "properties": {"skill": "12"}}]}
]
```

Eine Anfrage kann außerdem `latitude`, `longitude`, `playerCount`, `minPlayers` und `maxPlayers` angeben. Ein Regelsatz, den eine Warteschlange verwendet, kann nicht gelöscht werden; ändern oder löschen Sie zuerst die Warteschlange.
