---
sidebar_position: 5
title: Información de la app y categorías
---

# Información de la app y categorías

## Ver

```bash
# Ver la información de la app, las categorías y los metadatos por idioma
ascelerate apps app-info view <bundle-id>

# Listar todos los ID de categoría disponibles (no hace falta un Bundle ID)
ascelerate apps app-info view --list-categories
```

## Actualizar

```bash
# Actualizar los campos de localización de un solo idioma
ascelerate apps app-info update <bundle-id> --name "My App" --subtitle "Best app ever"
ascelerate apps app-info update <bundle-id> --locale de-DE --name "Meine App"

# Actualizar las categorías (se puede combinar con las opciones de localización)
ascelerate apps app-info update <bundle-id> --primary-category UTILITIES
ascelerate apps app-info update <bundle-id> --primary-category GAMES_ACTION --secondary-category ENTERTAINMENT
```

## Exportar

```bash
ascelerate apps app-info export <bundle-id>
ascelerate apps app-info export <bundle-id> --output app-infos.json
```

## Importar

```bash
ascelerate apps app-info import <bundle-id> --file app-infos.json
```

## Formato JSON

```json
{
  "en-US": {
    "name": "My App",
    "subtitle": "Best app ever",
    "privacyPolicyURL": "https://example.com/privacy",
    "privacyChoicesURL": "https://example.com/choices"
  }
}
```

Solo se actualizan los campos presentes; los que se omiten no cambian.

:::note
Los comandos `app-info update` y `app-info import` requieren que la información de la app esté en un estado editable (`PREPARE_FOR_SUBMISSION`, `READY_FOR_REVIEW`, `WAITING_FOR_REVIEW`, `DEVELOPER_REJECTED` o `REJECTED`).
:::

## Clasificación por edad

```bash
# Ver la declaración de clasificación por edad
ascelerate apps app-info age-rating <bundle-id>

# Exportar la clasificación por edad a JSON
ascelerate apps app-info age-rating export <bundle-id>

# Actualizar la clasificación por edad desde un archivo JSON
ascelerate apps app-info age-rating import <bundle-id> --file age-rating.json
```

El archivo JSON usa los mismos nombres de campo que la API. Solo se actualizan los campos presentes en el archivo:

```json
{
  "isAdvertising": false,
  "isUserGeneratedContent": true,
  "violenceCartoonOrFantasy": "INFREQUENT_OR_MILD",
  "alcoholTobaccoOrDrugUseOrReferences": "NONE"
}
```

Se rechaza una clave que el formato no tiene (si es un nombre de atributo de Apple, como `advertising` en lugar de `isAdvertising`, el mensaje indica el correcto). La exportación también incluye `koreaAgeRatingOverride`, `developerAgeRatingInfoUrl` y `gracRatingClassificationNumber`.

Los campos de intensidad admiten `NONE`, `INFREQUENT_OR_MILD` y `FREQUENT_OR_INTENSE`. Los campos booleanos admiten `true`/`false`.

## Cobertura de apps de rutas

```bash
# Ver el estado actual de la cobertura de rutas
ascelerate apps routing-coverage <bundle-id>

# Subir un archivo .geojson
ascelerate apps routing-coverage <bundle-id> --file coverage.geojson
```

## Más opciones

Opciones que los ejemplos anteriores no muestran:

- `apps app-info update` `--privacy-policy-url`, `--privacy-choices-url`: las URL de la política de privacidad y de las opciones de privacidad del idioma
