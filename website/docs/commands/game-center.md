---
sidebar_position: 18
title: Game Center
---

# Game Center

An app's achievements, leaderboards and leaderboard sets, with their languages, images and order. Each is named by its **ID** (the vendor identifier the game uses), its reference name or its Apple ID.

Their text and images live on a **version**. A new achievement, leaderboard or set starts with version 1 in Prepare for Submission, and a version goes to App Review with the app. To change one that's already live, the command makes its next version first, after asking.

## Turn Game Center On

```bash
ascelerate game-center <bundle-id>                      # on or off, counts, the default leaderboard
ascelerate game-center enable <bundle-id>
ascelerate game-center version <bundle-id> --enabled true   # the App Store version's Game Center switch
```

The App Store Connect API can't turn Game Center off for an app once it's on. The bundle ID needs the Game Center capability. `version` works on the version being prepared, or the one `--version` names.

## Achievements

```bash
ascelerate game-center achievements <bundle-id> [--json]
ascelerate game-center achievements info <bundle-id> first.win
ascelerate game-center achievements create <bundle-id> --id first.win --name "First Win" --points 10 [--hidden] [--repeatable]
ascelerate game-center achievements update <bundle-id> first.win --points 20 --hidden false
ascelerate game-center achievements update <bundle-id> first.win --archived true
ascelerate game-center achievements delete <bundle-id> first.win
```

An app's achievements share 1,000 points, and one gives 1 to 100. `--hidden` keeps an achievement hidden until a player earns it. One that has been live can't be deleted; archive it instead.

## Leaderboards

```bash
ascelerate game-center leaderboards <bundle-id> [--json]
ascelerate game-center leaderboards create <bundle-id> --id high.score --name "High Score"
ascelerate game-center leaderboards create <bundle-id> --id weekly.time --name "Weekly Time" \
  --formatter elapsed-time-second --sort low --submission recent --min 0 --max 3600 \
  --recurrence-start 2026-12-07T00:00:00Z --recurrence-duration PT168H --recurrence-rule "FREQ=DAILY;INTERVAL=7"
ascelerate game-center leaderboards update <bundle-id> weekly.time --hidden true
ascelerate game-center leaderboards default <bundle-id> high.score
```

By default, scores are integers, higher scores rank first, and each player's best score counts. `--formatter` takes `integer`, `decimal-point-1-place` to `decimal-point-3-place`, `elapsed-time-centisecond`, `elapsed-time-second`, `elapsed-time-minute`, or a currency such as `money-dollar-decimal`.

A recurring leaderboard starts over regularly. The duration is in hours or minutes (`PT24H`, or `PT168H` for a week), and the rule repeats by minutes, hours or days (`FREQ=DAILY;INTERVAL=7` restarts weekly). A score range is cleared as a whole, with `--min "" --max ""`.

The first leaderboard becomes the default, the one Game Center opens on; `default` changes it.

## Leaderboard Sets

```bash
ascelerate game-center sets <bundle-id>
ascelerate game-center sets create <bundle-id> --id all.scores --name "All Scores" --leaderboards high.score,weekly.time
ascelerate game-center sets update <bundle-id> all.scores --leaderboards weekly.time,high.score
```

`--leaderboards` sets a set's leaderboards in that order, replacing the current ones.

## Languages and Images

Achievements, leaderboards and sets have the same language and image commands; replace `achievements` with `leaderboards` or `sets`:

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

A new achievement language needs its name and both descriptions. A leaderboard language has a name, an optional description, its own `--formatter`, and the unit after a score (`--suffix " points"`, `--suffix-singular " point"`). A set language has a name.

An image belongs to one language. It must be square and at least 512×512 (512×512 or 1024×1024 are usual), PNG or JPEG. The upload replaces the language's current image and waits for Apple's check, so a refused image is reported at once.

## Order and App Review

```bash
ascelerate game-center achievements reorder <bundle-id> first.win,high.five
ascelerate game-center achievements submit <bundle-id> first.win [--platform ios]
```

`reorder` puts the ones listed first, in that order; the rest follow as they are. `submit` adds the item's new version to the app's draft submission (making one when there's none). It goes to App Review when you submit the draft with `ascelerate apps review submit`.

## Matchmaking

Rule-based matchmaking belongs to the team, not to one app, so these commands take no bundle ID. A **rule set** sets the player count, the rules and the teams; a **queue** is where games send their match requests, matched with one rule set. Rule sets and queues are named by reference name or ID.

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

Rules are written in Apple's rule language, based on JMESPath (which has no arithmetic operators). A compatible rule compares `requests[0]` with `requests[1]`; a distance rule gives a number for `requests[0]`, and requests with closer numbers match first. A player's properties are read as `requests[0].properties.<key>`. App Store Connect only checks an expression's syntax when it's saved, so run a test before using a rule set.

`test` runs sample requests through a rule set and shows the matches Apple would make, with each player's team; nothing is saved. The file is a JSON array:

```json
[
  {"requestName": "alice", "bundleId": "com.example.MyApp", "platform": "IOS", "appVersion": "1.0",
   "secondsInQueue": 5, "locale": "EN-US", "players": [{"playerId": "alice", "properties": {"skill": "10"}}]},
  {"requestName": "bob", "bundleId": "com.example.MyApp", "platform": "IOS", "appVersion": "1.0",
   "secondsInQueue": 8, "locale": "EN-US", "players": [{"playerId": "bob", "properties": {"skill": "12"}}]}
]
```

A request can also give `latitude`, `longitude`, `playerCount`, `minPlayers` and `maxPlayers`. A rule set that a queue uses can't be deleted; change or delete the queue first.
