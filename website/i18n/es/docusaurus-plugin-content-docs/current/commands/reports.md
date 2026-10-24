---
sidebar_position: 16
title: Informes
---

# Informes

Descargue informes de Ventas y tendencias, informes financieros e informes de App Analytics. Los informes de ventas y financieros llegan de Apple como TSV comprimido con gzip: `ascelerate` los descomprime y muestra un resumen (o guarda el archivo en bruto). App Analytics se obtiene mediante el flujo asíncrono de solicitudes de informes de Apple.

:::note Número de proveedor
`reports sales` y `reports finance` necesitan su **número de proveedor** (App Store Connect → Pagos e informes financieros, p. ej. `80012345`). Guárdelo una vez con `ascelerate configure` o indique `--vendor-number` en cada comando. `reports analytics` no lo necesita.
:::

## Ventas

Unidades (descargas), ingresos y actividad de compras dentro de la app y suscripciones. De forma predeterminada muestra un resumen agrupado por app y tipo de producto; añada `--raw` para mostrar el TSV o `--output` para guardarlo.

```bash
ascelerate reports sales
ascelerate reports sales --frequency WEEKLY
ascelerate reports sales --frequency MONTHLY --date 2026-05
ascelerate reports sales --frequency YEARLY --date 2025 --bundle-id com.example.App
ascelerate reports sales --frequency DAILY --date 2026-06-20 --output sales.tsv
```

- `--frequency`: `DAILY`, `WEEKLY`, `MONTHLY` o `YEARLY` (de forma predeterminada, `DAILY`).
- `--date`: `YYYY-MM-DD` para los informes diarios y semanales (en los semanales, el domingo en que termina la semana), `YYYY-MM` para los mensuales y `YYYY` para los anuales. De forma predeterminada, el último periodo completo.
- `--type`: tipo de informe (de forma predeterminada, `SALES`); otros son `SUBSCRIPTION`, `SUBSCRIBER`, `SUBSCRIPTION_EVENT`, `INSTALLS` y `PRE_ORDER`.
- `--sub-type`: `SUMMARY` (predeterminado), `DETAILED`, `SUMMARY_TERRITORY`, `SUMMARY_CHANNEL`, `SUMMARY_INSTALL_TYPE`.
- `--bundle-id`: limita el resumen a una sola app (o alias).
- `--vendor-number`: sustituye el número de proveedor configurado.
- `--output` / `--raw`: guarda el TSV en bruto en un archivo o lo muestra en lugar del resumen.

El resumen agrupa las unidades por título e **identificador de tipo de producto**. Esto resulta útil porque un mismo informe mezcla primeras descargas (`1*`/`3*`), actualizaciones (`7*`) y compras dentro de la app (`IA*`). Use `--raw` para ver todos los datos.

## Informes financieros

Unidades e ingresos del desarrollador de un periodo fiscal, por región.

```bash
ascelerate reports finance --date 2026-05 --region US
ascelerate reports finance --date 2026-05 --region US --type FINANCE_DETAIL --output finance.tsv
```

- `--date`: periodo fiscal en formato `YYYY-MM`, donde el mes es el **periodo fiscal de Apple (01–12)**, no un mes natural. Obligatorio.
- `--region`: código de región, p. ej. `US`, `EU`, `GB`, `JP`, `AU`, `WW` (todo el mundo). Obligatorio.
- `--type`: `FINANCIAL` (predeterminado) o `FINANCE_DETAIL`.
- `--vendor-number`, `--output`, `--raw`: como en el apartado anterior.

El resumen suma la cantidad por título y los ingresos por moneda.

## App Analytics

Datos de los informes de App Analytics: descargas, impresiones, visitas a la página de producto, sesiones y más. Apple los genera de forma asíncrona: el comando busca (o crea, tras pedir confirmación) una solicitud de informe para la app y después descarga los segmentos del informe.

```bash
ascelerate reports analytics <bundle-id>
ascelerate reports analytics <bundle-id> --category APP_USAGE --granularity WEEKLY
ascelerate reports analytics <bundle-id> --report-name "App Store Discovery and Engagement Detailed" --output ./analytics
```

- `--category`: `APP_STORE_ENGAGEMENT` (predeterminado), `APP_USAGE`, `COMMERCE`, `FRAMEWORK_USAGE`, `PERFORMANCE`.
- `--granularity`: `DAILY` (predeterminado), `WEEKLY`, `MONTHLY`.
- `--report-name`: elige un informe concreto cuando una categoría contiene varios.
- `--processing-date`: la instancia que se descarga (`YYYY-MM-DD`); de forma predeterminada, la más reciente.
- `--ongoing`: usa una solicitud de informe continua en lugar de una instantánea puntual.
- `--output`: carpeta para los archivos de segmentos descargados (de forma predeterminada, `./<app>-analytics`).

Una instantánea recién creada no está disponible de inmediato, porque Apple necesita tiempo para generarla. Vuelva a ejecutar el comando al cabo de unos minutos para descargar los segmentos.

:::info Valoraciones
La API de App Store Connect no ofrece el recuento total de valoraciones ni la media o la distribución de estrellas, solo las reseñas individuales (consulte [Reseñas de clientes](./reviews.md)). Para las cifras de descargas e ingresos, use los informes anteriores.
:::
