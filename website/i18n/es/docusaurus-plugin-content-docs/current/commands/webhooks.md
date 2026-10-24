---
sidebar_position: 20
title: Webhooks
---

# Webhooks

Haga que App Store Connect envíe los eventos de una app a su servidor en cuanto se producen: cambios de estado de la revisión, subidas de compilaciones, estados de las compilaciones externas de TestFlight y comentarios de los probadores. Los webhooks se indican por su **nombre** o su ID.

## Listar

```bash
ascelerate webhooks <bundle-id>
```

## Crear

```bash
ascelerate webhooks create <bundle-id> --name "Release bot" --url https://example.com/hook \
  --events app-store-version-app-version-state-updated,build-upload-state-updated
```

`--events` acepta una lista separada por comas o `all`. Entre los tipos de evento se encuentran:

| Evento | Se envía cuando |
|---|---|
| `app-store-version-app-version-state-updated` | Cambia el estado de App Review o de publicación de una versión |
| `build-upload-state-updated` | Cambia el estado de la subida de una compilación |
| `build-beta-detail-external-build-state-updated` | Cambia el estado de TestFlight externo de una compilación |
| `beta-feedback-crash-submission-created` | Un probador envía un comentario sobre un fallo |
| `beta-feedback-screenshot-submission-created` | Un probador envía un comentario con una captura de pantalla |

`ascelerate webhooks create --help` muestra todos los tipos, incluidos los eventos de recursos en segundo plano y de distribución alternativa.

Apple firma cada solicitud con el secreto del webhook. Sin `--secret`, `create` genera uno aleatorio y lo muestra una sola vez: guárdelo en su servidor, ya que App Store Connect no vuelve a mostrarlo. `--disabled` crea el webhook sin activarlo.

## Probar y depurar

```bash
ascelerate webhooks ping <bundle-id> "Release bot"
ascelerate webhooks deliveries <bundle-id> "Release bot"
ascelerate webhooks deliveries <bundle-id> "Release bot" --state failed
ascelerate webhooks redeliver <delivery-id>
```

`ping` envía un evento de prueba. `deliveries` muestra las entregas recientes con el tipo de evento, el código de estado HTTP con el que respondió su servidor y cualquier error (`--state succeeded|failed|pending`, `--limit`, `--json`). Una vez corregido su servidor, `redeliver` vuelve a enviar el evento de una entrega.

## Actualizar y eliminar

```bash
ascelerate webhooks update <bundle-id> "Release bot" --enabled false
ascelerate webhooks update <bundle-id> "Release bot" --events all --url https://example.com/new-hook
ascelerate webhooks delete <bundle-id> "Release bot"
```

`--events` sustituye la lista completa; `--secret` establece un nuevo secreto de firma.
