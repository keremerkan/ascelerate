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

## Idiomas e imágenes

Los logros, las tablas y los grupos tienen los mismos comandos de idiomas e imágenes; cambie `achievements` por `leaderboards` o `sets`:

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

Un idioma nuevo de un logro necesita su nombre y las dos descripciones. Un idioma de una tabla tiene un nombre, una descripción opcional, su propio `--formatter` y la unidad que sigue a una puntuación (`--suffix " points"`, `--suffix-singular " point"`). Un idioma de un grupo tiene un nombre.

Una imagen pertenece a un idioma. Debe ser cuadrada y de al menos 512×512 (lo habitual es 512×512 o 1024×1024), en PNG o JPEG. La subida sustituye la imagen actual del idioma y espera la comprobación de Apple, de modo que una imagen rechazada se notifica al momento.

## Orden y App Review

```bash
ascelerate game-center achievements reorder <bundle-id> first.win,high.five
ascelerate game-center achievements submit <bundle-id> first.win [--platform ios]
```

`reorder` coloca primero los indicados, en ese orden; el resto les sigue tal como está. `submit` añade la nueva versión del elemento al borrador de envío de la app (y crea uno si no lo hay). Va a App Review cuando envíe el borrador con `ascelerate apps review submit`.
