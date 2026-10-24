---
sidebar_position: 3
title: Localizaciones
---

# Localizaciones

Gestione las localizaciones de las versiones del App Store (descripción, novedades, palabras clave, etc.).

Todos los subcomandos admiten `--platform ios|macos|tvos|visionos` para las apps de compra universal que tienen la misma versión en varias plataformas; sin esta opción, preguntan cuando la versión es ambigua.

## Ver

```bash
ascelerate apps localizations view <bundle-id>
ascelerate apps localizations view <bundle-id> --version 2.1.0 --locale en-US
```

## Exportar

```bash
ascelerate apps localizations export <bundle-id>
ascelerate apps localizations export <bundle-id> --version 2.1.0 --output my-localizations.json
```

## Actualizar un solo idioma

```bash
ascelerate apps localizations update <bundle-id> --whats-new "Bug fixes" --locale en-US
```

## Actualización masiva desde JSON

```bash
ascelerate apps localizations import <bundle-id> --file localizations.json
```

## Formato JSON

Se usa el mismo formato para exportar y para importar:

```json
{
  "en-US": {
    "description": "My app description.\n\nSecond paragraph.",
    "whatsNew": "- Bug fixes\n- New dark mode",
    "keywords": "productivity,tools,utility",
    "promotionalText": "Try our new features!",
    "marketingURL": "https://example.com",
    "supportURL": "https://example.com/support"
  },
  "de-DE": {
    "whatsNew": "- Fehlerbehebungen\n- Neuer Dunkelmodus"
  }
}
```

Solo se actualizan los campos presentes en el JSON; los campos omitidos no se modifican.

:::note
Solo las versiones en estados editables (`PREPARE_FOR_SUBMISSION` o `WAITING_FOR_REVIEW`) aceptan cambios en las localizaciones, salvo `promotionalText` (el texto promocional), que puede actualizarse en cualquier estado.
:::
