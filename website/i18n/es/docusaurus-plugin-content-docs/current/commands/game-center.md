---
sidebar_position: 18
title: Game Center
---

# Game Center

Los logros, las tablas de clasificación y los grupos de tablas de clasificación de una app, con sus idiomas, imágenes y orden. Cada uno se indica por su **ID** (el vendor identifier que usa el juego), su nombre de referencia o su ID de Apple.

Sus textos e imágenes están en una **versión**. Un logro, una tabla o un grupo nuevo empieza con la versión 1 en Prepare for Submission, y una versión va a App Review junto con la app. Para cambiar uno que ya está publicado, el comando crea primero su siguiente versión, tras preguntar.

## Activar Game Center

```bash
ascelerate game-center <bundle-id>                      # activado o no, recuentos, la tabla predeterminada
ascelerate game-center enable <bundle-id>
ascelerate game-center version <bundle-id> --enabled true   # el interruptor de Game Center de la versión del App Store
```

La API de App Store Connect no puede desactivar Game Center en una app una vez activado. El bundle ID necesita la capacidad Game Center. `version` trabaja con la versión en preparación o con la que indique `--version`.

## Logros

```bash
ascelerate game-center achievements <bundle-id> [--json]
ascelerate game-center achievements info <bundle-id> first.win
ascelerate game-center achievements create <bundle-id> --id first.win --name "First Win" --points 10 [--hidden] [--repeatable]
ascelerate game-center achievements update <bundle-id> first.win --points 20 --hidden false
ascelerate game-center achievements update <bundle-id> first.win --archived true
ascelerate game-center achievements delete <bundle-id> first.win
```

Los logros de una app comparten 1000 puntos, y cada uno da de 1 a 100. `--hidden` mantiene un logro oculto hasta que un jugador lo consigue. Uno que ya ha estado publicado no se puede eliminar; archívelo en su lugar.

## Tablas de clasificación

```bash
ascelerate game-center leaderboards <bundle-id> [--json]
ascelerate game-center leaderboards create <bundle-id> --id high.score --name "High Score"
ascelerate game-center leaderboards create <bundle-id> --id weekly.time --name "Weekly Time" \
  --formatter elapsed-time-second --sort low --submission recent --min 0 --max 3600 \
  --recurrence-start 2026-12-07T00:00:00Z --recurrence-duration PT168H --recurrence-rule "FREQ=DAILY;INTERVAL=7"
ascelerate game-center leaderboards update <bundle-id> weekly.time --hidden true
ascelerate game-center leaderboards default <bundle-id> high.score
```

De forma predeterminada, las puntuaciones son enteros, las más altas van primero y cuenta la mejor puntuación de cada jugador. `--formatter` admite `integer`, de `decimal-point-1-place` a `decimal-point-3-place`, `elapsed-time-centisecond`, `elapsed-time-second`, `elapsed-time-minute` o una moneda como `money-dollar-decimal`.

Una tabla recurrente vuelve a empezar con regularidad. La duración se indica en horas o minutos (`PT24H`, o `PT168H` para una semana), y la regla se repite por minutos, horas o días (`FREQ=DAILY;INTERVAL=7` reinicia cada semana). Un rango de puntuaciones solo se borra entero, con `--min "" --max ""`.

La primera tabla pasa a ser la predeterminada, con la que se abre Game Center; `default` la cambia.

## Grupos de tablas de clasificación

```bash
ascelerate game-center sets <bundle-id>
ascelerate game-center sets create <bundle-id> --id all.scores --name "All Scores" --leaderboards high.score,weekly.time
ascelerate game-center sets update <bundle-id> all.scores --leaderboards weekly.time,high.score
```

`--leaderboards` fija las tablas de un grupo en ese orden y sustituye las actuales.

## Actividades

Una actividad es una parte del juego, como un nivel o un modo, a la que se puede invitar directamente a los jugadores. Sus logros y tablas de clasificación son los que le pertenecen.

```bash
ascelerate game-center activities <bundle-id> [--json]
ascelerate game-center activities create <bundle-id> --id duel --name "Duel" --play-style sync \
  --min-players 2 --max-players 2 [--party-code true] [--properties mode=duel] [--fallback-url https://example.com/duel]
ascelerate game-center activities update <bundle-id> duel --max-players 4 --fallback-url ""
ascelerate game-center activities link <bundle-id> duel --achievements first.win --leaderboards high.score
ascelerate game-center activities link <bundle-id> duel --leaderboards high.score --remove
```

`--play-style` es `sync` (los jugadores juegan a la vez) o `async` (por turnos). `--properties` sustituye las propiedades clave-valor propias del juego para la actividad. La URL alternativa es una página web para jugadores que no tienen el juego; pertenece a la última versión.

## Desafíos

Un desafío permite a los jugadores retar a sus amigos a superar una puntuación en una de las tablas de clasificación de la app.

```bash
ascelerate game-center challenges <bundle-id> [--json]
ascelerate game-center challenges create <bundle-id> --id beat.score --name "Beat My Score" --leaderboard high.score --repeatable
ascelerate game-center challenges update <bundle-id> beat.score --leaderboard weekly.best
```

Las reglas de App Store Connect, que los comandos comprueban antes: una tabla tiene como mucho un desafío, debe contar la mejor puntuación de cada jugador y un desafío que no sea `--repeatable` necesita una tabla recurrente.

## Idiomas e imágenes

Los logros, las tablas, los grupos, las actividades y los desafíos tienen los mismos comandos de idiomas e imágenes; cambie `achievements` por `leaderboards`, `sets`, `activities` o `challenges`:

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

Un idioma nuevo de un logro necesita su nombre y las dos descripciones. Un idioma de una tabla tiene un nombre, una descripción opcional, su propio `--formatter` y la unidad que sigue a una puntuación (`--suffix " points"`, `--suffix-singular " point"`). Un idioma de un grupo tiene un nombre; uno de una actividad o un desafío, un nombre y una descripción (`--name`, `--description`).

Una imagen pertenece a un idioma. Para logros, tablas y grupos debe ser cuadrada y de al menos 512×512 (lo habitual es 512×512 o 1024×1024); para actividades y desafíos, exactamente de 3840×2160, y sus versiones admiten además una imagen predeterminada (`image upload --default`). En PNG o JPEG. La subida sustituye la imagen actual y espera la comprobación de Apple, de modo que una imagen rechazada se notifica al momento.

## Orden y App Review

```bash
ascelerate game-center achievements reorder <bundle-id> first.win,high.five
ascelerate game-center achievements submit <bundle-id> first.win [--platform ios]
```

`reorder` (logros, tablas y grupos) coloca primero los indicados, en ese orden; el resto les sigue tal como está. `submit` añade la nueva versión del elemento al borrador de envío de la app (y crea uno si no lo hay). Va a App Review cuando envíe el borrador con `ascelerate apps review submit`. `apps review submit` también muestra todos los elementos con cambios pendientes de revisión y ofrece añadirlos al envío; `game-center <bundle-id>` muestra cuántos hay.

## Grupos de Game Center

Un grupo de Game Center comparte logros, tablas de clasificación, grupos de tablas, actividades y desafíos entre las apps de un equipo. Los grupos de Game Center se indican por su nombre de referencia o su ID.

```bash
ascelerate game-center groups [--json]                  # the team's groups with their apps
ascelerate game-center groups create --name "My Games"
ascelerate game-center groups rename "My Games" --name "Our Games"
ascelerate game-center groups delete "Our Games"
ascelerate game-center groups add-app "Our Games" <bundle-id> --dry-run
```

Añadir una app a un grupo de Game Center no se puede deshacer: la app no puede salir del grupo y sus logros, tablas y demás elementos pasan al grupo. `add-app` lo advierte y pregunta antes; pruébelo con `--dry-run`. Para una app de un grupo de Game Center, los demás comandos `game-center` listan, crean y ordenan los elementos del grupo, y `leaderboards default` fija la tabla del grupo con la que se abre Game Center para esa app.

## Emparejamiento

El emparejamiento basado en reglas pertenece al equipo, no a una app, así que estos comandos no llevan bundle ID. Un **conjunto de reglas** fija el número de jugadores, las reglas y los equipos; una **cola** es donde los juegos envían sus solicitudes de partida, que empareja con un conjunto de reglas. Los conjuntos de reglas y las colas se indican por su nombre de referencia o su ID.

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

Las reglas se escriben en el lenguaje de reglas de Apple, basado en JMESPath (que no tiene operadores aritméticos). Una regla de compatibilidad (compatible) compara `requests[0]` con `requests[1]`; una regla de distancia (distance) da un número para `requests[0]`, y las solicitudes con números más cercanos se emparejan primero. Las propiedades de un jugador se leen como `requests[0].properties.<clave>`. App Store Connect solo comprueba la sintaxis de una expresión al guardarla, así que pruebe un conjunto de reglas antes de usarlo.

`test` pasa solicitudes de ejemplo por un conjunto de reglas y muestra las partidas que formaría Apple, con el equipo de cada jugador; no se guarda nada. El archivo es una matriz JSON:

```json
[
  {"requestName": "alice", "bundleId": "com.example.MyApp", "platform": "IOS", "appVersion": "1.0",
   "secondsInQueue": 5, "locale": "EN-US", "players": [{"playerId": "alice", "properties": {"skill": "10"}}]},
  {"requestName": "bob", "bundleId": "com.example.MyApp", "platform": "IOS", "appVersion": "1.0",
   "secondsInQueue": 8, "locale": "EN-US", "players": [{"playerId": "bob", "properties": {"skill": "12"}}]}
]
```

Una solicitud también puede indicar `latitude`, `longitude`, `playerCount`, `minPlayers` y `maxPlayers`. Un conjunto de reglas que usa una cola no se puede eliminar; cambie o elimine antes la cola.
