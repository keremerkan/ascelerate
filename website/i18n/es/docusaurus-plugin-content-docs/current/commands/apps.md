---
sidebar_position: 1
title: Apps
---

# Apps

## Listar las apps

```bash
ascelerate apps list
```

## Detalles de una app

```bash
ascelerate apps info <bundle-id>
```

## Listar las versiones

```bash
ascelerate apps versions <bundle-id>
```

`apps list`, `apps info` y `apps versions` admiten `--json` para obtener una salida legible por máquinas ([convenciones](../guides/automation.md#json-output)).

## Crear una versión

```bash
ascelerate apps create-version <bundle-id> <version-string>
ascelerate apps create-version <bundle-id> 2.1.0 --platform ios --release-type manual
```

`--release-type` es opcional: si se omite, se usa la configuración de la versión anterior.

:::note Compra universal
En las apps de compra universal (un único registro del App Store que abarca iOS, macOS, tvOS o visionOS), la misma cadena de versión puede existir una vez por plataforma. `create-version` y `review submit` usan iOS de forma predeterminada; indique `--platform macos` (o `tvos`, `visionos`) para trabajar con otra plataforma. Todos los demás comandos que actúan sobre una versión (localizaciones, contenido multimedia, asignación de compilaciones, review preflight/info/attachments/resolve-issues/cancel-submission, publicación por fases, publicación manual) también admiten una opción `--platform`; sin ella, preguntan cada vez que una versión (o un envío a App Review activo) coincide con más de una plataforma, y con `--yes` se niegan a continuar y muestran una indicación en lugar de preguntar.
:::

## Copyright

```bash
ascelerate apps copyright <bundle-id>
ascelerate apps copyright <bundle-id> --set "2026 Your Name" --version 2.1.0 --platform macos
```

Sin `--set`, muestra el aviso de copyright actual. Para actualizarlo, la versión debe estar en un estado editable.

## Revisión

### Consultar el estado de la revisión

```bash
ascelerate apps review status <bundle-id>
ascelerate apps review status <bundle-id> --version 2.1.0
```

Añada `--json` para obtener los envíos, con el estado de cada elemento, en formato JSON legible por máquinas.

### Enviar a revisión {#submit-for-review}

```bash
ascelerate apps review submit <bundle-id>
ascelerate apps review submit <bundle-id> --version 2.1.0
ascelerate apps review submit <bundle-id> --platform macos
```

Al enviar, el comando detecta automáticamente las compras dentro de la app y las suscripciones con cambios pendientes y ofrece enviarlas junto con la versión de la app. Los cambios pendientes se leen del historial de versiones de cada producto (una versión en Prepare for Submission, Ready for Review o en un estado de rechazo), por lo que también se detectan los cambios que solo afectan a capturas de pantalla. `apps review status` relaciona los elementos de los envíos activos con la versión de la app o el producto al que corresponden.

### Resolver los elementos rechazados

Después de corregir los problemas y responder en el Resolution Center:

```bash
ascelerate apps review resolve-issues <bundle-id>
```

### Cancelar el envío

```bash
ascelerate apps review cancel-submission <bundle-id>
```

### Información para App Review

Consulte o actualice el contacto, la cuenta de demostración y las notas que se facilitan a App Review. Sin opciones, muestra los valores actuales; indique la opción de cualquier campo para actualizarlo (los campos omitidos no se modifican).

```bash
ascelerate apps review info <bundle-id>
ascelerate apps review info <bundle-id> --contact-email you@example.com --demo-account-name reviewer --demo-account-password "hunter2" --demo-account-required true --notes "Steps to test…"

# Archivos adjuntos (vídeos de demostración, documentos, etc.)
ascelerate apps review attachment list <bundle-id>
ascelerate apps review attachment upload <bundle-id> demo.mp4
ascelerate apps review attachment delete <attachment-id>
```

## Comprobaciones previas

Antes de enviar a revisión, ejecute `preflight` para verificar que todos los campos obligatorios estén completos en todos los idiomas:

```bash
# Comprobar la versión editable más reciente
ascelerate apps review preflight <bundle-id>

# Comprobar una versión concreta
ascelerate apps review preflight <bundle-id> --version 2.1.0
```

El comando comprueba el estado y la compilación de la versión (procesada y con el cumplimiento de exportación respondido), el copyright, el contacto y el inicio de sesión para la revisión, y la categoría principal, los derechos de contenido, el precio y la disponibilidad de la app. Después recorre cada idioma: la información de la app (nombre y, en el idioma principal, la URL de la política de privacidad), los textos de la versión (descripción y palabras clave en todos los idiomas, la URL de soporte en el idioma principal) y las capturas de pantalla. Un idioma sin capturas propias muestra en el App Store las del idioma principal, así que solo el idioma principal las necesita:

```
Preflight checks for MyApp v2.1.0 (Prepare for Submission)

Check                                Status
──────────────────────────────────────────────────────────────────
Version state                        ✓ Prepare for Submission
Build attached                       ✓ Build 42
Copyright                            ✓ 2026 Your Name
Review contact                       ✓ Jane Doe, jane@example.com
Sign-in                              ✓ Not required
Category                             ✓ Productivity
Content rights                       ✓ Does Not Use Third Party Content
Price                                ✓ Set
Availability                         ✓ 175 territories

en-US (English (United States))
  App info                           ✓ All fields filled
  Localizations                      ✓ All fields filled
  Screenshots                        ✓ 2 sets, 10 screenshots

de-DE (German (Germany))
  App info                           ✓ All fields filled
  Localizations                      ✗ Missing: Keywords, What's New
  Screenshots                        ✓ None (uses en-US's)
──────────────────────────────────────────────────────────────────
Result: 14 passed, 1 failed
```

En las compras dentro de la app y las suscripciones se comprueba que tengan precios y un estado compatible con un envío. Un producto que haya retirado de la venta (Developer Removed from Sale) aparece como omitido (–) y no hace fallar la comprobación; la línea del resultado lo cuenta aparte.

Las novedades (What's New) solo se comprueban en las actualizaciones, es decir, cuando ya se publicó una versión de la misma plataforma. Una publicación en otra plataforma no cuenta: la primera versión para Mac de una app de iOS no las necesita.

El comando termina con un código de salida distinto de cero si falla alguna comprobación, lo que lo hace adecuado para pipelines de CI y archivos de workflow. Con `--json`, en lugar de la tabla emite un informe estructurado (un booleano `passed` y una entrada por comprobación con `group`, `name`, `passed` y `detail`) y mantiene el mismo comportamiento del código de salida, de modo que los controles de CI pueden indicar exactamente qué comprobación ha fallado.

## Publicación por fases

```bash
# Ver el estado de la publicación por fases
ascelerate apps phased-release <bundle-id>

# Activar la publicación por fases (empieza inactiva y se activa cuando la versión se publica)
ascelerate apps phased-release <bundle-id> --enable

# Pausar, reanudar o completar una publicación por fases
ascelerate apps phased-release <bundle-id> --pause
ascelerate apps phased-release <bundle-id> --resume
ascelerate apps phased-release <bundle-id> --complete

# Quitar por completo la publicación por fases
ascelerate apps phased-release <bundle-id> --disable
```

## Publicación manual

Cuando la opción de publicación de una versión es manual, la versión aprobada queda en Pending Developer Release hasta que usted la publique:

```bash
# Publicar la versión pendiente de publicación por el desarrollador
ascelerate apps release <bundle-id>

# Indicar una versión o plataforma concreta
ascelerate apps release <bundle-id> --version 2.1.0 --platform macos
```

## Declaraciones de accesibilidad

El App Store muestra qué funciones de accesibilidad admite una app, declaradas por familia de dispositivos: VoiceOver, Control por Voz, Texto Más Grande, Interfaz oscura, Diferenciar sin solo color, Contraste suficiente, Reducir Movimiento, Subtítulos y Audiodescripciones.

```bash
# Ver las declaraciones (en borrador o publicadas) por familia de dispositivos
ascelerate apps accessibility <bundle-id>

# Declarar lo que la app admite en el iPhone y publicarlo
ascelerate apps accessibility set <bundle-id> --device iphone --supports voiceover,larger-text,dark-interface --publish

# Publicar las declaraciones en borrador tal como están
ascelerate apps accessibility publish <bundle-id>
```

`set` declara la lista completa: las funciones que no incluya se declaran como no admitidas (`--supports none` no declara ninguna). Familias de dispositivos: `iphone`, `ipad`, `mac`, `apple-tv`, `apple-watch`, `vision`. Sin `--publish`, la declaración queda como borrador. Publicar una declaración modificada reemplaza a la publicada; `--all` muestra también las declaraciones reemplazadas. Declare solo aquello en lo que los usuarios puedan confiar en las tareas habituales de la app.

## Disponibilidad por países o regiones

```bash
# Ver en qué países o regiones está disponible la app
ascelerate apps availability <bundle-id>

# Mostrar los nombres completos de los países
ascelerate apps availability <bundle-id> --verbose

# Hacer que países o regiones estén disponibles o no
ascelerate apps availability <bundle-id> --add CHN,RUS
ascelerate apps availability <bundle-id> --remove CHN
```

## Precios de la app

```bash
# Precio base, precios fijados manualmente y cambios previstos (--all: todos los países o regiones; --json)
ascelerate apps pricing <bundle-id>
ascelerate apps pricing tiers <bundle-id> --territory USA

# Precio base, ahora o a partir de una fecha (en la moneda del país o región base; 0 para gratis)
ascelerate apps pricing set <bundle-id> --price 0.99
ascelerate apps pricing set <bundle-id> --price 1.99 --start-date 2026-12-01

# Precios fijados manualmente: un país o región, conservar los precios actuales de Apple o devolvérselos a Apple
ascelerate apps pricing override <bundle-id> --territory FRA --price 0.99
ascelerate apps pricing keep <bundle-id> --territories all
ascelerate apps pricing remove <bundle-id> --territories FRA,DEU

# Cambio de precio temporal (una oferta) y eliminación de un cambio previsto
ascelerate apps pricing sale <bundle-id> --territories all --price 0.49 --start-date 2026-12-20 --end-date 2026-12-27
ascelerate apps pricing cancel <bundle-id> --territory USA --start-date 2026-12-01

# Copiar una programación de precios a otra app (el formato de iap pricing export)
ascelerate apps pricing export <bundle-id> --output prices.json
ascelerate apps pricing import <other-bundle-id> --file prices.json
```

Apple calcula los precios de los demás países o regiones a partir del precio base y puede ajustarlos cuando cambian los impuestos o los tipos de cambio; un precio fijado manualmente se mantiene tal cual. Para varios países o regiones, `sale` toma el precio en la moneda del país o región base y asigna a los demás los precios equivalentes de Apple; al terminar, vuelve a aplicarse el precio anterior de cada país o región. `import` reemplaza la programación completa.

## Declaraciones de cifrado

```bash
# Ver las declaraciones de cifrado existentes
ascelerate apps encryption <bundle-id>

# Crear una nueva declaración de cifrado
ascelerate apps encryption <bundle-id> --create --description "Uses HTTPS for API communication"
ascelerate apps encryption <bundle-id> --create --description "Uses AES encryption" --proprietary-crypto --third-party-crypto
```

## EULA

```bash
# Ver el EULA actual (o comprobar que se aplica el EULA estándar de Apple)
ascelerate apps eula <bundle-id>

# Establecer un EULA personalizado a partir de un archivo de texto
ascelerate apps eula <bundle-id> --file eula.txt

# Eliminar el EULA personalizado (se vuelve al EULA estándar de Apple)
ascelerate apps eula <bundle-id> --delete
```

## Periodo de gracia de las suscripciones

El periodo de gracia permite que los suscriptores conserven el acceso durante un breve plazo tras un pago de renovación fallido, mientras Apple vuelve a intentar el cobro. La configuración se aplica a toda la app.

```bash
# Ver la configuración actual
ascelerate apps subscription-grace-period <bundle-id>

# Activarlo en producción con un plazo de 16 días, aplicado a todas las renovaciones
ascelerate apps subscription-grace-period <bundle-id> \
  --opt-in true --duration SIXTEEN_DAYS --renewal-type ALL_RENEWALS

# Solo para pruebas en sandbox (en producción sigue desactivado)
ascelerate apps subscription-grace-period <bundle-id> \
  --sandbox-opt-in true --duration THREE_DAYS --renewal-type ALL_RENEWALS
```

Valores válidos de `--duration`: `THREE_DAYS`, `SIXTEEN_DAYS`, `TWENTY_EIGHT_DAYS`. Valores válidos de `--renewal-type`: `ALL_RENEWALS`, `PAID_TO_PAID_ONLY`.

El periodo de gracia no puede estar activado en producción sin estarlo en sandbox: al activar `--opt-in` también se activa en sandbox, con un plazo de 16 días para todas las renovaciones salvo que indique otros valores. Al desactivarlo en ambos se borran la duración y el tipo de renovación.

## Compra simplificada

La compra simplificada permite a los clientes comprar las suscripciones de la app fuera de ella, por ejemplo en su página de producto del App Store. Está activada de forma predeterminada y se aplica a todas las suscripciones de la app. Apple solo permite desactivarla en una app cuya última compilación aprobada use la API `PurchaseIntent` de StoreKit; en ese caso, los clientes se suscriben desde la propia app.

```bash
# Ver
ascelerate apps streamlined-purchasing <bundle-id>

# Desactivar
ascelerate apps streamlined-purchasing <bundle-id> --enabled false
```
