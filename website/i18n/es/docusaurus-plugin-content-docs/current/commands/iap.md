---
sidebar_position: 6
title: Compras dentro de la app
---

# Compras dentro de la app

## Listar

```bash
ascelerate iap list <bundle-id>
ascelerate iap list <bundle-id> --type consumable --state approved
```

Los valores de los filtros no distinguen entre mayúsculas y minúsculas. Tipos: `CONSUMABLE`, `NON_CONSUMABLE`, `NON_RENEWING_SUBSCRIPTION`. Estados: `APPROVED`, `MISSING_METADATA`, `READY_TO_SUBMIT`, `WAITING_FOR_REVIEW`, `IN_REVIEW`, etc.

## Detalles

```bash
ascelerate iap info <bundle-id> <product-id>
```

`iap list` e `iap info` aceptan `--json` para obtener una salida legible por máquinas ([convenciones](../guides/automation.md#json-output)); `info` indica la advertencia de precios ausentes con el booleano `hasPricing`.

## Compras promocionadas

Promocione compras dentro de la app o suscripciones en la página de producto de su app en el App Store. Se muestran en el orden de visualización.

```bash
ascelerate iap promoted list <bundle-id>
ascelerate iap promoted add <bundle-id> <product-id> --visible-for-all true --enabled true
ascelerate iap promoted reorder <bundle-id> com.example.a,com.example.b
ascelerate iap promoted toggle <bundle-id> <product-id> --enabled false
ascelerate iap promoted remove <bundle-id> <product-id>
```

`reorder` recibe los identificadores de producto en el orden deseado; los que omita se conservan y se colocan detrás de los indicados.

## Crear, actualizar y eliminar

```bash
ascelerate iap create <bundle-id> --name "100 Coins" --product-id <product-id> --type CONSUMABLE
ascelerate iap update <bundle-id> <product-id> --name "100 Gold Coins"
ascelerate iap delete <bundle-id> <product-id>
```

## Enviar a revisión

```bash
ascelerate iap submit <bundle-id> <product-id>
```

Un producto puede enviarse siempre que tenga una versión pendiente, es decir, una versión en el estado Prepare for Submission, Ready for Review o en un estado de rechazo. Esto incluye los productos aprobados que se han modificado desde su última aprobación. Si no hay ninguna versión pendiente, el comando se detiene antes de enviar ninguna solicitud. `iap info` muestra la versión pendiente cuando la hay.

## Localizaciones

```bash
ascelerate iap localizations view <bundle-id> <product-id>
ascelerate iap localizations export <bundle-id> <product-id>
ascelerate iap localizations import <bundle-id> <product-id> --file iap-de.json
```

El comando de importación crea automáticamente, previa confirmación, los idiomas que faltan, de modo que puede añadir idiomas nuevos sin pasar por App Store Connect.

## Precios

`iap pricing` lee y escribe la programación de precios. La programación tiene un único país o región base (el que Apple utiliza para equiparar automáticamente los precios en todos los demás países o regiones), además de ninguno, uno o varios precios manuales por país o región.

```bash
# Mostrar la programación de precios actual (avisa si aún no hay ninguna)
ascelerate iap pricing show <bundle-id> <product-id>

# Listar todos los niveles de precio disponibles en un país o región
ascelerate iap pricing tiers <bundle-id> <product-id> --territory USA
```

`pricing show` acepta `--json`: devuelve el país o región base y cada precio con su país o región y su moneda.

### Fijar el precio del país o región base

```bash
ascelerate iap pricing set <bundle-id> <product-id> --price 4.99
ascelerate iap pricing set <bundle-id> <product-id> --price 4.99 --base-territory GBR
```

De forma predeterminada, `--base-territory` toma el país o región base actual (o USA en una programación nueva). Si la programación tiene precios manuales por país o región, `set` muestra un menú interactivo que permite devolver cualquiera de ellos a la equiparación automática a partir de la nueva base. Para eliminar todos los precios manuales sin que se le pregunte, use `--remove-all-overrides`.

### Precios manuales por país o región

```bash
# Añadir o actualizar un precio manual
ascelerate iap pricing override <bundle-id> <product-id> --price 5.99 --territory FRA

# Quitar el precio manual (el país o región vuelve a equipararse automáticamente a partir de la base)
ascelerate iap pricing remove <bundle-id> <product-id> --territory FRA
```

`override` y `remove` solo actúan sobre países o regiones que no son la base. Para cambiar el precio del país o región base, use `set`.

Si una compra dentro de la app no tiene programación de precios, tanto `iap info` como `iap pricing show` muestran una advertencia, y el comando `apps review preflight` la señala como un impedimento para el envío.

### Copiar precios entre productos

```bash
# Exportar a JSON la programación (país o región base y todos los precios manuales)
ascelerate iap pricing export <bundle-id> <product-id> --output prices.json

# Aplicarla a otra compra dentro de la app, de la misma app o de otra
ascelerate iap pricing import <other-bundle-id> <other-product-id> --file prices.json
```

El archivo guarda los precios para el cliente con el código de cada país o región como clave. Al importar, cada precio se busca por su precio para el cliente entre los niveles de precio del producto *de destino*, de modo que el mismo archivo sirve para distintos productos y apps. La importación sustituye la programación por completo: los países o regiones que no figuran en el archivo vuelven a la equiparación automática, y si la programación actual ya coincide con el archivo, el comando no hace nada. Los errores transitorios de App Store Connect (HTTP 429/5xx) se reintentan automáticamente.

## Disponibilidad

Cada compra dentro de la app tiene su propia disponibilidad por país o región, independiente de la de la app. De forma predeterminada, una compra dentro de la app hereda los países o regiones de su app; en cuanto ejecuta `iap availability` con cambios, la compra pasa a tener una lista propia.

```bash
# Ver los países o regiones actuales de la compra dentro de la app
ascelerate iap availability <bundle-id> <product-id>

# Editar la lista de países o regiones (un POST que sustituye la lista completa)
ascelerate iap availability <bundle-id> <product-id> --add CHN,RUS
ascelerate iap availability <bundle-id> <product-id> --remove ITA
ascelerate iap availability <bundle-id> <product-id> --available-in-new-territories true
```

## Códigos de oferta

Los códigos de oferta son códigos canjeables que dan un descuento puntual en una compra dentro de la app. Los hay de dos tipos, que se gestionan con el mismo recurso de código de oferta:

- **Códigos de un solo uso**: Apple genera N códigos únicos en un lote. Cada uno solo puede canjearse una vez. Los códigos se generan de forma asíncrona.
- **Códigos personalizados**: una cadena que define el desarrollador (p. ej., `PROMO2026`) y que puede canjearse N veces.

```bash
# Listar todos los códigos de oferta de una compra dentro de la app
ascelerate iap offer-code list <bundle-id> <product-id>

# Mostrar los detalles y el número de códigos por lote de un código de oferta
ascelerate iap offer-code info <bundle-id> <product-id> <offer-code-id>

# Crear un código de oferta con un precio rebajado (equiparado automáticamente en todos los países o regiones)
ascelerate iap offer-code create <bundle-id> <product-id> \
  --name "Launch Promo" \
  --eligibility NON_SPENDER,ACTIVE_SPENDER \
  --price 0.99 --territory USA --equalize-all-territories

# Activar o desactivar
ascelerate iap offer-code toggle <bundle-id> <product-id> <offer-code-id> --active true

# Generar un lote de códigos de un solo uso (se generan de forma asíncrona)
ascelerate iap offer-code gen-codes <bundle-id> <product-id> <offer-code-id> \
  --count 100 --expires 2026-12-31

# Obtener los códigos una vez completada la generación
ascelerate iap offer-code view-codes <one-time-use-batch-id> --output codes.txt

# Añadir un código personalizado definido por el desarrollador
ascelerate iap offer-code add-custom-codes <bundle-id> <product-id> <offer-code-id> \
  --code PROMO2026 --count 1000 --expires 2026-12-31
```

Requisitos de los clientes para los códigos de oferta de compras dentro de la app: `NON_SPENDER`, `ACTIVE_SPENDER`, `CHURNED_SPENDER`.

## Imágenes promocionales

Suba las imágenes promocionales que se muestran junto a la compra dentro de la app en el App Store.

```bash
ascelerate iap images list <bundle-id> <product-id>
ascelerate iap images upload <bundle-id> <product-id> ./hero.png
ascelerate iap images delete <bundle-id> <product-id> <image-id>
```

Las subidas siguen el proceso de Apple en tres pasos: reserva con `fileSize` y `fileName`, PUT de los fragmentos del archivo a URL prefirmadas y, por último, un PATCH con el MD5 del archivo para confirmarlo. La CLI realiza los tres pasos con una sola llamada a `upload`.

## Captura de pantalla para App Review

Cada compra dentro de la app puede tener como máximo una captura de pantalla para App Review (la que ven los revisores de Apple). Al subir una nueva, se sustituye la existente.

```bash
ascelerate iap review-screenshot view <bundle-id> <product-id>
ascelerate iap review-screenshot upload <bundle-id> <product-id> ./review.png
ascelerate iap review-screenshot delete <bundle-id> <product-id>
```
