---
sidebar_position: 21
title: Apple Ads
---

# Apple Ads

Gestione sus campañas de Apple Ads (antes Search Ads) desde la línea de comandos mediante la API Apple Ads Platform: informes de rendimiento, campañas, grupos de anuncios, palabras clave y palabras clave negativas, pujas y presupuestos, las recomendaciones de Apple y sus datos de investigación de palabras clave. Las apps se emparejan con las de App Store Connect, así que `--app` acepta los mismos Bundle ID y [alias](../getting-started/aliases.md) que el resto de comandos. Las campañas y los grupos de anuncios se indican por su **nombre** (sin distinguir mayúsculas de minúsculas) o su ID; si el nombre no existe, se muestran los válidos.

Todos los comandos que modifican algo piden confirmación antes (`-y` la omite), y `--dry-run` muestra las solicitudes exactas sin enviarlas ([simulación](../guides/automation.md#dry-run)). Los cambios gastan dinero real, así que pruébelos primero con `--dry-run`. Los importes se expresan en la moneda de la cuenta publicitaria.

## Configuración

Apple Ads usa sus propias credenciales, independientes de su clave de API de App Store Connect:

1. En Apple Ads, vaya a **Configuración de la cuenta → Gestión de usuarios** (Account Settings → User Management), invite a un usuario con un rol de **API** (por ejemplo, API Account Manager) y acepte la invitación con la Cuenta de Apple de ese usuario.
2. Ejecute la configuración:

```bash
ascelerate ads configure
```

ascelerate crea el par de claves y muestra la clave pública. Inicie sesión en Apple Ads como el usuario de API, pegue la clave en **Configuración de la cuenta → API** (Account Settings → API) e introduzca el ID de cliente, el ID de equipo y el ID de clave que aparecen allí. A continuación, ascelerate muestra las cuentas publicitarias a las que tiene acceso el usuario y guarda la que usted elija en una sección `ads` de `~/.ascelerate/config.json`. `--new-key` crea un par de claves nuevo.

```bash
ascelerate ads accounts          # cuentas publicitarias y roles del usuario de API
```

## Informes

```bash
ascelerate ads reports campaigns --days 30
ascelerate ads reports campaigns --from 2026-09-01 --to 2026-09-30 --app myapp
ascelerate ads reports campaigns --campaign "MyApp US" --by device
ascelerate ads reports adgroups --campaign "MyApp US"
ascelerate ads reports ads --campaign "MyApp US"
ascelerate ads reports keywords --campaign "MyApp US"
ascelerate ads reports search-terms --app myapp --days 14
```

| Informe | Filas |
|---|---|
| `campaigns` | Campañas; `--by age gender device country region city` las desglosa |
| `adgroups` | Grupos de anuncios (por ejemplo, para comparar los grupos de una prueba) |
| `ads` | Anuncios, es decir, la página de producto a la que cada grupo de anuncios envía los toques |
| `keywords` | Palabras clave, con la puja sugerida por Apple |
| `search-terms` | Lo que la gente buscó realmente, la palabra clave que coincidió y si procedía de sus palabras clave o de Search Match |

Todos los informes aceptan `--days N` (incluido el día de hoy) o `--from`/`--to`, `--app`, `--campaign`, `--all` (incluye filas sin actividad) y `--json`. Las fechas están en la zona horaria de la cuenta publicitaria. Para tomar decisiones, compare días completos: las cifras de hoy todavía están llegando.

Cada fila muestra el gasto, las impresiones, los toques, las instalaciones, la tasa de toques (TTR), el coste medio por toque (CPT) y por instalación (CPI), y dos tasas de conversión:

- **CR (Tap)**: instalaciones tras un toque, divididas entre los toques. Indica lo bien que su página de producto convierte a quienes la tocaron.
- **CR (Total)**: todas las instalaciones, incluidas las instalaciones por visualización (personas que vieron el anuncio e instalaron la app más tarde sin tocarlo), divididas entre los toques. Puede superar el 100 %.

:::note
Apple solo conoce la edad, el sexo y la ubicación por debajo del nivel de país de los usuarios que han permitido los anuncios personalizados, así que esos desgloses aparecen casi por completo como «Unknown». Los desgloses por dispositivo están completos. Los términos de búsqueda que Apple oculta por privacidad aparecen como «(low volume)».
:::

## Campañas

```bash
ascelerate ads campaigns list --app myapp
ascelerate ads campaigns pause "MyApp US"
ascelerate ads campaigns resume "MyApp US"
ascelerate ads campaigns budget "MyApp US" --daily 120
ascelerate ads campaigns bid "MyApp US Max Conv" --amount 2.50
```

`list` muestra el estado de cada campaña, sus países, su presupuesto diario y su modo de puja (Manual CPT o Max Conversions). En una campaña Max Conversions, `bid` fija lo máximo que puede pagar en una sola subasta: establézcalo según lo que vale para usted una instalación, ya que un límite por debajo del coste por toque habitual en esa tienda deja a la campaña sin tráfico.

### Crear una campaña

```bash
ascelerate ads campaigns create --like "MyApp US" --name "MyApp US Max Conv" --max-conversions --bid 2.50 --daily 25
ascelerate ads campaigns create --app myapp --name "MyApp DE" --country DE --daily 20 --default-bid 1.00 --search-match off
```

La campaña se crea **en pausa**, junto con su grupo de anuncios: uno automatizado para Max Conversions, o uno manual con `--default-bid`. `--like` copia la app, los países y los ajustes de una campaña existente. `--enabled` la activa de inmediato.

```bash
ascelerate ads campaigns target-cpa --app myapp --country US
```

Muestra el coste por instalación objetivo que Apple sugiere para una nueva campaña Max Conversions.

:::tip
Las campañas de una misma app en la misma tienda no compiten entre sí: Apple solo deja entrar a una de ellas en cada subasta. Por eso, una campaña nueva junto a otra que ya está en marcha solo recibe el tráfico sobrante. Para probar una campaña nueva, desvíe el tráfico hacia ella, por ejemplo limitando la antigua al nombre de su marca.
:::

## Grupos de anuncios

```bash
ascelerate ads adgroups --campaign "MyApp US"
ascelerate ads adgroups create --campaign "MyApp US" --name "Exact" --search-match off
ascelerate ads adgroups create --campaign "MyApp US" --name "Adults" --like "US Ad Group" --min-age 25
ascelerate ads adgroups update "Exact" --campaign "MyApp US" --default-bid 1.20
ascelerate ads adgroups pause "Exact" --campaign "MyApp US"
ascelerate ads adgroups resume "Exact" --campaign "MyApp US"
```

`create` copia los precios, las pujas y la segmentación de un grupo de anuncios existente (`--like`, o el único grupo de la campaña) y lo crea **en pausa** salvo que indique `--enabled`. `--min-age`/`--max-age` segmentan edades de 18 a 64 años (sin `--max-age`, de 65 años en adelante). La segmentación por edad solo llega a los usuarios que han permitido los anuncios personalizados, y Apple no atribuye a la campaña en otras herramientas las instalaciones de los grupos de anuncios segmentados por edad, así que evalúe esos grupos con las cifras de Apple Ads.

## Palabras clave y palabras clave negativas

```bash
ascelerate ads keywords list --campaign "MyApp US"
ascelerate ads keywords add --campaign "MyApp US" --match exact --bid 1.50 "qr scanner" "barcode reader"
ascelerate ads keywords bid --campaign "MyApp US" --bid 1.25 "qr scanner"
ascelerate ads keywords pause --campaign "MyApp US" "barcode reader"
ascelerate ads keywords copy --campaign "MyApp US" --from "US Ad Group" --to "Exact"

ascelerate ads negatives list --campaign "MyApp US"
ascelerate ads negatives add --campaign "MyApp US" "free wifi"
ascelerate ads negatives add --campaign "MyApp US" --ad-group "Discovery" --match broad "wifi"
ascelerate ads negatives remove --campaign "MyApp US" "free wifi"
```

`--ad-group` elige el grupo de anuncios cuando una campaña tiene varios. Las palabras clave negativas se aplican a toda la campaña salvo que indique `--ad-group`, y son de concordancia exacta salvo con `--match broad`. `keywords add` omite las palabras clave que ya existen. Las campañas Max Conversions eligen sus propias pujas, así que las pujas por palabra clave no se les aplican.

## Qué cambiar

```bash
ascelerate ads opportunities --app myapp
ascelerate ads opportunities --campaign "MyApp US" --days 60 --min-taps 20 --brand "my app"
```

`opportunities` compara los términos de búsqueda de una campaña (de forma predeterminada, los últimos 30 días completos) con sus palabras clave y sus propias medias, y sugiere:

- **Añadir como palabra clave exacta**: un término de búsqueda que convierte, sin palabra clave exacta propia y con un buen coste por instalación.
- **Darle su propia puja**: un término que convierte gracias a la puja de otra palabra clave, con un coste más alto.
- **Excluir**: un término con un gasto real y sin instalaciones, o con un coste o una tasa de conversión mucho peores.

Las búsquedas del nombre de su app quedan fuera de las medias y nunca se sugieren como negativas; añada otras grafías de su marca con `--brand`. Trate los resultados como candidatos y compruebe que cada término es relevante para su app antes de actuar.

```bash
ascelerate ads recommendations
ascelerate ads recommendations apply <id>
ascelerate ads recommendations dismiss <id>
```

Las recomendaciones abiertas de Apple (cambios del presupuesto diario y del CPA objetivo), con el resultado esperado.

```bash
ascelerate ads history --app myapp --days 7
```

Todos los cambios de campañas, grupos de anuncios, palabras clave y palabras clave negativas de los últimos seis meses, incluidos los hechos en el sitio web de Apple Ads o por Apple, con los valores antiguos y nuevos. Resulta útil antes de interpretar un cambio en el rendimiento.

## Investigación de palabras clave

```bash
ascelerate ads keywords suggest --app myapp --seed "qr code" "barcode" --country US GB
ascelerate ads keywords popularity --app myapp --country US --term "qr code" "qr scanner"
ascelerate ads keywords popularity --genre PRODUCTIVITY_UTILITIES --country US --contains scanner
ascelerate ads insights impression-share --app myapp --country US --weeks 4
```

- `suggest` devuelve las palabras clave que Apple sugiere a partir de sus términos de partida, con su popularidad y dónde las segmenta ya.
- `popularity` muestra la popularidad de los términos de búsqueda en una tienda (de 1 a 100) y en la categoría de la app. Los términos que no figuran en la clasificación de la categoría se muestran aparte.
- `impression-share` muestra su cuota de impresiones de anuncios y su posición en los términos de búsqueda en los que aparecieron sus anuncios: una cuota baja en un término popular que convierte es margen para crecer, y una cuota inferior al 100 % en el nombre de su propia marca significa que la competencia puja por él.

Los datos de popularidad también son útiles para elegir las palabras clave del App Store (ASO).

## Anuncios y páginas de producto personalizadas

```bash
ascelerate ads product-pages --app myapp
ascelerate ads ads --campaign "MyApp US"
ascelerate ads ads create --campaign "MyApp US" --ad-group "Scanner" --product-page "Scanner Page" --enabled
ascelerate ads ads pause "Scanner Page ad" --campaign "MyApp US"
```

Un anuncio envía los toques de un grupo de anuncios a una página de producto. Los grupos de anuncios sin un anuncio propio usan la página de producto predeterminada. Para enviar las búsquedas de una necesidad concreta a una [página de producto personalizada](product-pages.md), deles su propio grupo de anuncios (`adgroups create`, `keywords add`) y cree un anuncio para él. Cada grupo de anuncios solo publica un anuncio a la vez, así que `--enabled` pausa el que estaba activo. Apple revisa los anuncios nuevos; `ads ads` muestra su estado de revisión.

## Uso con un agente de IA

La [skill de ascelerate](../guides/ai-skill.md) enseña a los agentes de programación con IA a leer estos informes y cuándo sugerir cambios, de modo que puede pedir a un agente que revise sus campañas de todas sus apps, encuentre palabras clave que añadir o excluir, o explique un cambio en el rendimiento. Todos los comandos aceptan `--json`, y se indica a los agentes que le muestren los cambios propuestos y usen `--dry-run` antes de enviar nada.
