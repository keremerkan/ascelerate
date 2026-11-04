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

## Sprachen und Bilder

Erfolge, Bestenlisten und Gruppen haben dieselben Sprach- und Bildbefehle; ersetzen Sie `achievements` durch `leaderboards` oder `sets`:

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

Eine neue Sprache eines Erfolgs braucht den Namen und beide Beschreibungen. Eine Sprache einer Bestenliste hat einen Namen, eine optionale Beschreibung, einen eigenen `--formatter` und die Einheit nach einer Punktzahl (`--suffix " points"`, `--suffix-singular " point"`). Eine Sprache einer Gruppe hat einen Namen.

Ein Bild gehört zu einer Sprache. Es muss quadratisch und mindestens 512 × 512 groß sein (üblich sind 512 × 512 oder 1024 × 1024), als PNG oder JPEG. Der Upload ersetzt das aktuelle Bild der Sprache und wartet auf Apples Prüfung, sodass ein abgelehntes Bild sofort gemeldet wird.

## Reihenfolge und App Review

```bash
ascelerate game-center achievements reorder <bundle-id> first.win,high.five
ascelerate game-center achievements submit <bundle-id> first.win [--platform ios]
```

`reorder` stellt die aufgeführten Elemente in dieser Reihenfolge an den Anfang; die übrigen folgen unverändert. `submit` fügt die neue Version des Elements dem Einreichungsentwurf der App hinzu (und legt einen an, wenn es keinen gibt). Sie geht zum App Review, wenn Sie den Entwurf mit `ascelerate apps review submit` einreichen.
