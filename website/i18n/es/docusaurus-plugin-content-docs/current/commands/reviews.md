---
sidebar_position: 13
title: Reseñas de clientes
---

# Reseñas de clientes

Consulte las reseñas de clientes y gestione las respuestas del desarrollador. Las reseñas en sí son de solo lectura: únicamente puede publicar, sustituir o eliminar la **respuesta del desarrollador**.

## Listar

```bash
ascelerate reviews list <bundle-id>
ascelerate reviews list <bundle-id> --rating 1 --sort critical --unanswered --limit 20
ascelerate reviews list <bundle-id> --territory USA
```

La tabla muestra el ID de la reseña, la valoración en estrellas, la fecha, el país o región, si tiene respuesta y el título.

- `--rating`: filtra por valoración en estrellas (1–5).
- `--territory`: filtra por el código del país o región de la reseña (p. ej., `USA`).
- `--sort`: `recent` (predeterminado), `oldest`, `critical` (primero la valoración más baja) o `best` (primero la más alta).
- `--unanswered`: solo las reseñas sin respuesta publicada.
- `--limit`: número máximo de reseñas que se muestran (50 de forma predeterminada, 200 como máximo).
- `--json`: salida legible por máquinas que incluye el **texto completo de las reseñas y las respuestas del desarrollador**, de modo que no hace falta llamar a `info` para cada reseña ([convenciones](../guides/automation.md#json-output)).

## Detalles

```bash
ascelerate reviews info <review-id>
```

Muestra el texto completo de la reseña y la respuesta del desarrollador (si la hay). Los ID de las reseñas se obtienen con `reviews list`. También acepta `--json`, con la misma estructura que un elemento de `reviews list --json`.

## Responder

```bash
ascelerate reviews respond <review-id> --body "Thanks for the feedback! We've fixed this in the latest update."
```

Publica una respuesta del desarrollador. Si la reseña ya tiene una respuesta, se sustituye (previa confirmación).

## Eliminar una respuesta

```bash
ascelerate reviews delete-response <review-id>
```
