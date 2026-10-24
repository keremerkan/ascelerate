---
sidebar_position: 15
title: Páginas de producto personalizadas
---

# Páginas de producto personalizadas

Cree y gestione páginas de producto personalizadas: versiones alternativas de su página de producto del App Store con su propio texto promocional y sus propias capturas de pantalla, cada una accesible desde una URL única. Las páginas se indican por su **nombre** o su ID.

## Listar e inspeccionar

```bash
ascelerate product-pages list <bundle-id>
ascelerate product-pages info <bundle-id> <name-or-id>
```

`list` muestra el nombre de cada página, su visibilidad, la URL del App Store para compartirla (con su `ppid`) y su ID. `info` añade las versiones de la página y sus localizaciones.

## Crear

```bash
ascelerate product-pages create <bundle-id> --name "Summer Campaign" --locale en-US --promotional-text "Limited-time offer"
```

La API de App Store Connect exige crear la página junto con una primera versión y al menos una localización, por eso `--locale` es obligatorio. Añada más idiomas después con `product-pages localizations import`.

## Actualizar y eliminar

```bash
ascelerate product-pages update <bundle-id> "Summer Campaign" --name "Summer 2026" --visible false
ascelerate product-pages delete <bundle-id> "Summer Campaign"
```

`--visible` determina si la página está publicada en el App Store.

## Localizaciones

```bash
ascelerate product-pages localizations view <bundle-id> "Summer 2026"
ascelerate product-pages localizations export <bundle-id> "Summer 2026"
ascelerate product-pages localizations import <bundle-id> "Summer 2026" --file page-locales.json
```

Cada localización contiene `promotionalText`, que se aplica a la versión editable de la página.

```json
{
  "en-US": { "promotionalText": "Limited-time offer" },
  "fr-FR": { "promotionalText": "Offre à durée limitée" }
}
```

## Capturas de pantalla y vistas previas de la app

Capturas de pantalla por idioma (`.png`/`.jpg`, por tipo de pantalla) y vistas previas de la app (`.mp4`/`.mov`, por tipo de vista previa). El conjunto se crea automáticamente con la primera subida.

```bash
ascelerate product-pages media list <bundle-id> "Summer 2026"
ascelerate product-pages media upload <bundle-id> "Summer 2026" --locale en-US --display-type APP_IPHONE_67 screenshot.png
ascelerate product-pages media upload <bundle-id> "Summer 2026" --locale en-US --preview-type APP_IPHONE_67 preview.mp4 --preview-frame 00:00:03:00
ascelerate product-pages media delete <bundle-id> "Summer 2026" <media-id>
```

El tipo de archivo determina si se sube como captura de pantalla o como vista previa de la app. Los tipos de pantalla y de vista previa usan los identificadores de dispositivo habituales del App Store (p. ej. `APP_IPHONE_67`, `APP_IPAD_PRO_3GEN_129`).

`--display-type` también admite los espacios de la biblioteca multimedia `PRODUCT_PAGE_HEADER` y `APP_STORE_SEARCH_RESULTS` (una imagen o un vídeo que sustituye al actual) y `APP_IPHONE_DUO` (una captura de pantalla o una vista previa de la app, que se añade después de las existentes); en [Capturas y vistas previas](media.md#header-and-search-results) encontrará sus tamaños. `media list` los muestra y `media delete` los elimina por su ID.
