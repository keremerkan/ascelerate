---
sidebar_position: 14
title: Eventos dentro de la app
---

# Eventos dentro de la app

Cree y gestione eventos dentro de la app: eventos puntuales (eventos en directo, estrenos, retos, ofertas especiales) que aparecen en la página de producto del App Store y en las búsquedas. Los eventos se indican por su **nombre de referencia** o su ID.

## Listar e inspeccionar

```bash
ascelerate events list <bundle-id>
ascelerate events list <bundle-id> --state PUBLISHED
ascelerate events info <bundle-id> <reference-name-or-id>
```

`info` muestra los atributos del evento, su programación por país o región y un resumen de sus localizaciones.

## Crear, actualizar y eliminar

```bash
ascelerate events create <bundle-id> --reference-name "summer-sale" --badge SPECIAL_EVENT --purpose ATTRACT_NEW_USERS --priority HIGH

# Con una programación inicial
ascelerate events create <bundle-id> --reference-name "launch" \
  --territories USA,GBR --publish-start 2026-07-01 --event-start 2026-07-05 --event-end 2026-07-12

ascelerate events update <bundle-id> summer-sale --priority NORMAL --badge NONE
ascelerate events delete <bundle-id> summer-sale
```

- **Distintivos:** `LIVE_EVENT`, `PREMIERE`, `CHALLENGE`, `COMPETITION`, `NEW_SEASON`, `MAJOR_UPDATE`, `SPECIAL_EVENT`. Indique `--badge NONE` en `update` para quitarlo.
- **Objetivos:** `APPROPRIATE_FOR_ALL_USERS`, `ATTRACT_NEW_USERS`, `KEEP_ACTIVE_USERS_INFORMED`, `BRING_BACK_LAPSED_USERS`.
- **Prioridad:** `HIGH` o `NORMAL`.
- **Fechas de la programación** (`--publish-start`, `--event-start`, `--event-end`): admiten ISO 8601 (`2026-07-01T09:00:00Z`) o `yyyy-MM-dd` (medianoche UTC). Omita `--territories` para programar el evento en todos los países y regiones.

## Localizaciones

```bash
ascelerate events localizations view <bundle-id> summer-sale
ascelerate events localizations export <bundle-id> summer-sale
ascelerate events localizations import <bundle-id> summer-sale --file event-locales.json
```

Cada localización contiene `name`, `shortDescription` y `longDescription`. Los idiomas deben coincidir con los configurados en la app (p. ej. `tr`, no `tr-TR`).

```json
{
  "en-US": {
    "name": "Summer Sale",
    "shortDescription": "Big summer discounts",
    "longDescription": "Join our summer event for limited-time discounts."
  }
}
```

## Contenido multimedia

Capturas de pantalla (`.png`/`.jpg`) y clips de vídeo (`.mp4`/`.mov`) para la tarjeta del evento y la página de detalles del evento, por localización.

```bash
ascelerate events media list <bundle-id> summer-sale
ascelerate events media upload <bundle-id> summer-sale --locale en-US --asset-type EVENT_CARD card.png
ascelerate events media upload <bundle-id> summer-sale --locale en-US --asset-type EVENT_DETAILS_PAGE clip.mp4 --preview-frame 00:00:03:00
ascelerate events media delete <bundle-id> summer-sale <media-id>
```

Los tipos de recurso son `EVENT_CARD` y `EVENT_DETAILS_PAGE`. El tipo de archivo determina si se sube como captura de pantalla o como clip de vídeo; `--preview-frame` fija el código de tiempo del fotograma de vista previa de un vídeo.
