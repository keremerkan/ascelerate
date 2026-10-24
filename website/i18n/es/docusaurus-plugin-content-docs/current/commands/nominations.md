---
sidebar_position: 19
title: Nominaciones para destacar
---

# Nominaciones para destacar

Informe al equipo editorial de Apple de un próximo lanzamiento, una actualización importante o contenido nuevo, para que pueda tenerlo en cuenta a la hora de destacarlo en el App Store.

## Listar

```bash
ascelerate nominations
ascelerate nominations --app <bundle-id> --state draft
```

Lista las nominaciones en borrador, enviadas y archivadas (o las de un solo estado con `--state`). Añada `--json` para obtener una salida legible por máquinas.

## Crear

```bash
ascelerate nominations create --app <bundle-id> --type enhancements --name "Version 5" \
  --description "What's new and why it matters to users" --publish-start 2026-11-01 \
  --devices iphone,ipad --locales en-US,tr-TR
```

| Opción | Descripción |
|---|---|
| `--app` | La app (repita `--app` para una nominación que abarque varias apps) |
| `--type` | `launch`, `enhancements` o `new-content` |
| `--name`, `--description` | De qué trata la nominación, redactado para los editores de Apple |
| `--publish-start` | Fecha de lanzamiento (`yyyy-MM-dd` o ISO 8601); `--publish-end` para contenido por tiempo limitado |
| `--devices` | Familias de dispositivos: `iphone`, `ipad`, `mac`, `apple-tv`, `apple-watch`, `vision` |
| `--locales` | Idiomas a los que está localizado el lanzamiento |
| `--territories` | Países o regiones donde se lanza primero (todos de forma predeterminada) |
| `--materials` | Enlaces a material de apoyo (kit de prensa, vídeo), separados por comas |
| `--notes` | Notas para Apple |
| `--pre-order` | La app está disponible para reservar |
| `--submit` | Enviarla de inmediato en lugar de guardarla como borrador |

Sin `--submit`, la nominación se guarda como borrador que puede revisar y modificar.

## Actualizar, enviar, archivar y eliminar

```bash
ascelerate nominations update <id> --publish-start 2026-11-08
ascelerate nominations submit <id>
ascelerate nominations archive <id>
ascelerate nominations delete <id>
```

`update` modifica un borrador; los ID de las nominaciones se obtienen con `nominations`. La decisión de destacar una app corresponde a los editores de Apple, así que envíe la nominación con bastante antelación a la fecha de lanzamiento.
