---
sidebar_position: 7
title: Suscripciones
---

# Suscripciones

## Listar y consultar

```bash
ascelerate sub groups <bundle-id>
ascelerate sub list <bundle-id>
ascelerate sub info <bundle-id> <product-id>
```

Los tres comandos aceptan `--json` para obtener una salida legible por máquinas ([convenciones](../guides/automation.md#json-output)); `info` indica la advertencia de precios ausentes con el booleano `hasPricing`.

## Crear, actualizar y eliminar suscripciones

```bash
ascelerate sub create <bundle-id> --name "Monthly" --product-id <product-id> --period ONE_MONTH --group-id <group-id>
ascelerate sub update <bundle-id> <product-id> --name "Monthly Plan"
ascelerate sub delete <bundle-id> <product-id>
```

## Grupos de suscripciones

```bash
ascelerate sub create-group <bundle-id> --name "Premium"
ascelerate sub update-group <bundle-id> --name "Premium Plus"
ascelerate sub delete-group <bundle-id>
```

## Enviar a revisión

```bash
ascelerate sub submit <bundle-id> <product-id>
```

Un producto puede enviarse siempre que tenga una versión pendiente, es decir, una versión en el estado Prepare for Submission, Ready for Review o en un estado de rechazo. Esto incluye los productos aprobados que se han modificado desde su última aprobación. Si no hay ninguna versión pendiente, el comando se detiene antes de enviar ninguna solicitud. `sub info` muestra la versión pendiente cuando la hay.

## Localizaciones de suscripciones

```bash
ascelerate sub localizations view <bundle-id> <product-id>
ascelerate sub localizations export <bundle-id> <product-id>
ascelerate sub localizations import <bundle-id> <product-id> --file sub-de.json
```

## Localizaciones de grupos

```bash
ascelerate sub group-localizations view <bundle-id>
ascelerate sub group-localizations export <bundle-id>
ascelerate sub group-localizations import <bundle-id> --file group-de.json
```

Los comandos de importación crean automáticamente, previa confirmación, los idiomas que faltan, de modo que puede añadir idiomas nuevos sin pasar por App Store Connect.

## Precios

Los precios de las suscripciones se definen por país o región. A diferencia de las compras dentro de la app, no existe la equiparación automática: cada país o región al que quiera ponerle precio necesita su propio registro. La CLI fija el precio en un único país o región, o bien lo extiende a todos usando los niveles de precio equivalentes de Apple en cada moneda local.

```bash
# Mostrar los precios actuales por país o región (avisa si no hay ninguno)
ascelerate sub pricing show <bundle-id> <product-id>

# Mostrarlos en JSON (precio, moneda, fecha de inicio e indicador de precio conservado por país o región)
ascelerate sub pricing show <bundle-id> <product-id> --json

# Listar los niveles de precio disponibles en un país o región
ascelerate sub pricing tiers <bundle-id> <product-id> --territory USA

# Fijar el precio en un único país o región
ascelerate sub pricing set <bundle-id> <product-id> --price 4.99 --territory USA

# Extender un precio a todos los países o regiones (un POST por país o región)
ascelerate sub pricing set <bundle-id> <product-id> --price 4.99 --equalize-all-territories
```

### Cambios de precio y suscriptores actuales

Apple trata de forma distinta los cambios de precio para los suscriptores actuales según su sentido. `sub pricing set` obtiene el precio actual de cada país o región afectado, clasifica el cambio y aplica el comportamiento adecuado:

- **Bajada**: los suscriptores actuales pasan automáticamente al precio más bajo. En modo interactivo se muestra una advertencia y se pide confirmación. En modo `--yes` debe añadir `--confirm-decrease` para confirmar el impacto en los ingresos; `--yes` por sí solo no basta.
- **Subida**: debe elegir explícitamente qué ocurre con los suscriptores actuales. El comando falla si no se indica una de estas opciones:
  - `--preserve-current`: mantiene a los suscriptores actuales con su precio anterior
  - `--no-preserve-current`: aplica el nuevo precio a los suscriptores actuales (tras el periodo de notificación de Apple)
- **País o región nuevo** (sin precio previo): no hay suscriptores actuales, así que no hace falta ninguna de estas opciones.
- **Sin cambios**: se omite sin aviso.

Las mismas reglas se aplican en conjunto con `--equalize-all-territories`. Si el cambio supone una subida en alguno de los países o regiones, la opción sobre el precio actual es obligatoria para todos ellos. Si alguno supone una bajada en modo `--yes`, `--confirm-decrease` es obligatoria.

```bash
# Subida de precio global habitual: de 4,99 $ a 9,99 $ en todos los países o regiones,
# manteniendo a los suscriptores actuales con el precio anterior
ascelerate sub pricing set myapp com.example.monthly \
  --price 9.99 --territory USA --equalize-all-territories \
  --preserve-current
```

### Copiar precios entre productos

```bash
# Exportar a JSON el precio actual de cada país o región
ascelerate sub pricing export <bundle-id> <product-id> --output prices.json

# Aplicarlo a otra suscripción, de la misma app o de otra
ascelerate sub pricing import <other-bundle-id> <other-product-id> --file prices.json
```

El archivo guarda los precios para el cliente con el código de cada país o región como clave (los precios conservados para suscriptores actuales y los programados para el futuro no se exportan). Al importar, cada precio se busca por su precio para el cliente entre los niveles de precio de la suscripción *de destino*, de modo que el mismo archivo sirve para distintos productos y apps. La importación solo modifica los países o regiones incluidos en el archivo, omite los que ya tienen el precio indicado y aplica las mismas reglas de seguridad para subidas y bajadas que `set`, incluidas `--preserve-current`/`--no-preserve-current` y `--confirm-decrease`.

Los errores transitorios de App Store Connect (HTTP 429/5xx) durante las escrituras en varios países o regiones se reintentan automáticamente: primero en el momento, con esperas crecientes, y después en una segunda pasada al final de la ejecución. Los países o regiones que siguen fallando aparecen en el informe final y el comando termina con un código distinto de cero. Si vuelve a ejecutar el mismo comando, solo se reintentan esos, ya que los países o regiones ya actualizados se omiten por no tener cambios.

## Disponibilidad

Cada suscripción tiene su propia disponibilidad por país o región, independiente de la de la app. De forma predeterminada, una suscripción hereda los países o regiones de su app; en cuanto ejecuta `sub availability` con cambios, la suscripción pasa a tener una lista propia.

```bash
# Ver los países o regiones actuales de la suscripción
ascelerate sub availability <bundle-id> <product-id>

# Editar la lista de países o regiones (cada edición sustituye la lista completa)
ascelerate sub availability <bundle-id> <product-id> --add CHN,RUS
ascelerate sub availability <bundle-id> <product-id> --remove ITA
ascelerate sub availability <bundle-id> <product-id> --available-in-new-territories true
ascelerate sub availability <bundle-id> <product-id> --plan monthly --add DEU,FRA
```

Las suscripciones anuales también pueden venderse como **mensuales con compromiso de 12 meses** (facturadas cada mes; no disponible en Estados Unidos ni en Singapur). Ese plan de facturación tiene su propia lista de países o regiones: añada `--plan monthly` para verla o editarla. Sin `--plan`, el comando gestiona el plan habitual de pago por adelantado.

## Ofertas introductorias

Las ofertas introductorias se dirigen a **suscriptores nuevos**: pruebas gratuitas y descuentos de bienvenida.

```bash
ascelerate sub intro-offer list <bundle-id> <product-id>

# Prueba gratuita (sin precio; --periods y --duration fijan la duración de la prueba)
ascelerate sub intro-offer create <bundle-id> <product-id> \
  --mode FREE_TRIAL --duration ONE_WEEK --periods 1 --territories all

# Descuento de pago por uso (3 meses a 0,99 $/mes, solo en EE. UU.)
ascelerate sub intro-offer create <bundle-id> <product-id> \
  --mode PAY_AS_YOU_GO --duration ONE_MONTH --periods 3 \
  --territories USA --price 0.99

# Actualizar solo la fecha de finalización (el resto de campos requiere eliminar y volver a crear)
ascelerate sub intro-offer update <bundle-id> <product-id> <offer-id> --end-date 2026-12-31

ascelerate sub intro-offer delete <bundle-id> <product-id> <offer-id>
```

Modos: `FREE_TRIAL`, `PAY_AS_YOU_GO`, `PAY_UP_FRONT`. `--territories` es obligatoria: códigos de países o regiones como `USA,TUR`, o `all`. Apple guarda una oferta por país o región, y ascelerate las crea en una sola solicitud; omite los países o regiones donde la oferta se solaparía con una existente o que ya tienen una oferta futura. El `--price` de una oferta de pago está en la moneda del primer país o región; los demás reciben el precio equivalente de Apple. `--price` es obligatoria en los dos modos de pago y no se admite con `FREE_TRIAL`.

## Ofertas promocionales

Las ofertas promocionales se dirigen a **suscriptores actuales** y suelen usarse en flujos de venta adicional dentro de la app. Para que los clientes puedan canjearla, el código de la oferta (el valor de `--code`) debe incluirse en una carga firmada que su servidor genera en tiempo de ejecución.

```bash
ascelerate sub promo-offer list <bundle-id> <product-id>
ascelerate sub promo-offer info <bundle-id> <product-id> <offer-id>

# Crear: mismo esquema de un único país o región, o --equalize-all-territories
ascelerate sub promo-offer create <bundle-id> <product-id> \
  --name "Loyalty 50%" --code LOYALTY50 \
  --mode PAY_AS_YOU_GO --duration ONE_MONTH --periods 3 \
  --price 4.99 --territory USA --equalize-all-territories

# Actualizar solo los precios (el resto de campos requiere eliminar y volver a crear)
ascelerate sub promo-offer update <bundle-id> <product-id> <offer-id> \
  --price 5.99 --equalize-all-territories

ascelerate sub promo-offer delete <bundle-id> <product-id> <offer-id>
```

## Códigos de oferta

Los códigos de oferta son códigos canjeables para suscripciones y los hay de dos tipos:

- **Códigos de un solo uso**: Apple genera N códigos únicos en un lote (de forma asíncrona). Cada uno solo puede canjearse una vez.
- **Códigos personalizados**: una cadena que define el desarrollador y que puede canjearse N veces.

```bash
ascelerate sub offer-code list <bundle-id> <product-id>
ascelerate sub offer-code info <bundle-id> <product-id> <offer-code-id>

# Crear un código de oferta (con todos los atributos propios de una oferta)
ascelerate sub offer-code create <bundle-id> <product-id> \
  --name "Launch Free Month" \
  --eligibility NEW \
  --offer-eligibility STACK_WITH_INTRO_OFFERS \
  --mode FREE_TRIAL --duration ONE_MONTH --periods 1 \
  --price 0 --territory USA --equalize-all-territories

ascelerate sub offer-code toggle <bundle-id> <product-id> <offer-code-id> --active true

# Generar códigos de un solo uso (asíncrono)
ascelerate sub offer-code gen-codes <bundle-id> <product-id> <offer-code-id> \
  --count 500 --expires 2026-12-31

# Obtener los códigos una vez completada la generación
ascelerate sub offer-code view-codes <one-time-use-batch-id> --output codes.txt

# Añadir un código personalizado definido por el desarrollador
ascelerate sub offer-code add-custom-codes <bundle-id> <product-id> <offer-code-id> \
  --code SUBPROMO --count 1000 --expires 2026-12-31
```

Requisitos de los clientes para los códigos de oferta de suscripciones: `NEW`, `EXISTING`, `EXPIRED`. Compatibilidad con la oferta introductoria: `STACK_WITH_INTRO_OFFERS` o `REPLACE_INTRO_OFFERS`.

## Enviar un grupo de suscripciones a revisión

Los grupos de suscripciones se revisan junto con la siguiente versión de la app. `sub submit-group` es el equivalente de `sub submit` para grupos.

```bash
ascelerate sub submit-group <bundle-id>
```

El grupo necesita su propia versión pendiente (por ejemplo, localizaciones del grupo modificadas); de lo contrario, el comando se detiene antes de enviar ninguna solicitud.

## Imágenes promocionales

Suba las imágenes promocionales que se muestran junto a la suscripción en el App Store.

```bash
ascelerate sub images list <bundle-id> <product-id>
ascelerate sub images upload <bundle-id> <product-id> ./hero.png
ascelerate sub images delete <bundle-id> <product-id> <image-id>
```

## Captura de pantalla para App Review

Cada suscripción puede tener como máximo una captura de pantalla para App Review. Al subir una nueva, se sustituye la existente.

```bash
ascelerate sub review-screenshot view <bundle-id> <product-id>
ascelerate sub review-screenshot upload <bundle-id> <product-id> ./review.png
ascelerate sub review-screenshot delete <bundle-id> <product-id>
```

Las subidas de imágenes y capturas siguen el proceso de subida de archivos de Apple en tres pasos (reserva, PUT de los fragmentos y confirmación con MD5). La CLI realiza los tres pasos con una sola llamada a `upload`.

## Ofertas de recuperación (aún no implementadas)

Las ofertas de recuperación (ofertas para suscriptores que se han dado de baja) aún no están implementadas. En la especificación de la API de Apple, los precios de una oferta de recuperación (`WinBackOfferPriceInlineCreate`) carecen de las relaciones `territory` y `subscriptionPricePoint` que sí tienen los precios de todos los demás tipos de oferta, por lo que no es posible construir una solicitud de creación válida. Volveremos a revisarlo cuando Apple actualice la especificación.
