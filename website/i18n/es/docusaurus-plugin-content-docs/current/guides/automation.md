---
sidebar_position: 2
title: Automatización y CI/CD
---

# Automatización y CI/CD

La mayoría de los comandos que piden confirmación admiten `--yes` / `-y` para omitir las preguntas, lo que los hace aptos para pipelines de CI/CD y scripts.

```bash
ascelerate apps build attach-latest <bundle-id> --yes
ascelerate apps review submit <bundle-id> --yes
```

:::warning
Si usa `--yes` con los comandos de suministro, debe indicar explícitamente todos los argumentos necesarios, porque el modo interactivo queda desactivado.
:::

## Simulación {#dry-run}

Añada `--dry-run` para probar un comando o un workflow completo sin cambiar nada en App Store Connect. La opción funciona en cualquier posición de la línea de comandos, y definir `ASCELERATE_DRY_RUN=1` tiene el mismo efecto. Las lecturas se envían como siempre, de modo que las búsquedas y comprobaciones se hacen con sus datos reales, pero cada escritura se detiene antes de enviarse: ascelerate muestra en stderr su método, su ruta y su cuerpo JSON, e informa de que la solicitud no se ha enviado.

```bash
ascelerate apps localizations import <bundle-id> --file localizations.json --yes --dry-run
ascelerate run-workflow release.txt --yes --dry-run
ASCELERATE_DRY_RUN=1 ascelerate run-workflow release.txt --yes   # lo mismo, p. ej. para todo un job de CI
```

- Un comando se detiene en la primera escritura bloqueada o, si procesa los elementos uno a uno, informa de cada solicitud bloqueada como fallida.
- `media upload` da por hechas las escrituras bloqueadas y continúa, así que muestra las escrituras de todos los archivos; al final indica cuántos archivos se subirían.
- En `run-workflow`, un paso cuyas escrituras se han bloqueado no detiene el workflow, de modo que una sola ejecución muestra las escrituras de todos los pasos. Aun así, puede fallar un paso que dependa de algo que habría creado un paso anterior, como una versión nueva o una compilación subida.
- En un archivo de workflow, `--dry-run` en un solo paso se aplica únicamente a ese paso.
- `builds upload` omite la subida. `builds archive` y `builds validate` se ejecutan igualmente, ya que no cambian nada en App Store Connect.

## Límite de solicitudes de la API {#rate-limit}

App Store Connect permite 3600 solicitudes a la API por hora para su clave de API, contadas a lo largo de una hora móvil. Cuando un comando largo (una subida grande de contenido multimedia, una limpieza de la biblioteca multimedia, una importación de precios) las agota, ascelerate espera hasta que App Store Connect vuelva a admitir solicitudes, muestra la hora a la que continuará y después sigue. Pulse Ctrl-C si prefiere detenerlo.

En CI quizá prefiera que falle en lugar de esperar: defina `ASCELERATE_MAX_RATE_LIMIT_WAIT` con el número máximo de segundos que puede esperar una ejecución en total (`0` hace que falle en la primera solicitud limitada).

```bash
ASCELERATE_MAX_RATE_LIMIT_WAIT=600 ascelerate run-workflow release.txt --yes
```

`ascelerate rate-limit` muestra cuántas solicitudes quedan; nunca espera.

## Fragmentos de subida {#upload-chunks}

App Store Connect recibe los archivos subidos (capturas de pantalla, vistas previas de la app, compilaciones con `builds upload --api` y otro contenido multimedia) en fragmentos. ascelerate los envía de uno en uno, lo que deja ancho de banda para todo lo demás que use la conexión. Con una conexión rápida pero con mucha latencia hasta el almacenamiento de Apple, enviar varios a la vez puede terminar antes: defina `ASCELERATE_PARALLEL_CHUNKS` con el número de fragmentos que se enviarán simultáneamente.

```bash
ASCELERATE_PARALLEL_CHUNKS=4 ascelerate apps media upload <bundle-id> media/
```

## Firma de Xcode en CI

Tanto `builds archive` como la exportación del archivo de Xcode a IPA pasan `-allowProvisioningUpdates` a `xcodebuild`. Sin esta opción, `xcodebuild` solo usa los perfiles de suministro guardados localmente y no descarga versiones actualizadas del portal de Apple Developer.

En entornos de CI sin una sesión iniciada en Xcode, indique las opciones de autenticación:

```bash
ascelerate builds archive \
  --authentication-key-path /path/to/AuthKey.p8 \
  --authentication-key-id YOUR_KEY_ID \
  --authentication-key-issuer-id YOUR_ISSUER_ID
```

## Salida JSON {#json-output}

Los comandos de lectura admiten `--json` para obtener una salida legible por máquinas, lista para `jq`, scripts y agentes de IA:

```bash
ascelerate apps list --json
ascelerate apps info <bundle-id> --json
ascelerate apps versions <bundle-id> --json
ascelerate apps review preflight <bundle-id> --json
ascelerate apps review status <bundle-id> --json
ascelerate builds list --bundle-id <bundle-id> --json
ascelerate testflight builds <bundle-id> --json
ascelerate testflight status <bundle-id> --json
ascelerate reviews list <bundle-id> --json
ascelerate reviews info <review-id> --json
ascelerate iap list <bundle-id> --json
ascelerate iap info <bundle-id> <product-id> --json
ascelerate iap pricing show <bundle-id> <product-id> --json
ascelerate sub groups <bundle-id> --json
ascelerate sub list <bundle-id> --json
ascelerate sub info <bundle-id> <product-id> --json
ascelerate sub pricing show <bundle-id> <product-id> --json
ascelerate rate-limit --json
```

Convenciones de la salida:

- Los comandos de lista devuelven un **array** JSON en el nivel superior; los comandos de detalle devuelven un único **objeto**.
- Los valores enumerados son las constantes en bruto de la API (`WAITING_FOR_REVIEW`, `IOS`), las fechas están en ISO 8601 y cada recurso incluye su `id`.
- Los campos nulos se omiten y los resultados vacíos devuelven `[]`, nunca texto.
- Las advertencias se convierten en booleanos: `iap info` y `sub info` indican `"hasPricing": false` en lugar de mostrar un mensaje de advertencia.
- `--json` implica el modo no interactivo: los comandos que harían una pregunta (por ejemplo, para distinguir entre plataformas) terminan con un error. Indique `--platform` u otras opciones para resolver la ambigüedad.
- Los errores se envían a stderr, así que stdout siempre contiene JSON válido.

Ejemplo: contar las reseñas sin responder:

```bash
ascelerate reviews list <bundle-id> --json | jq '[.[] | select(.response == null)] | length'
```

## Códigos de salida

Los comandos terminan con un código distinto de cero cuando fallan, así que puede usarlos sin riesgo en scripts con `set -e` o encadenarlos con `&&`. En concreto, `preflight` termina con un código distinto de cero cuando falla alguna comprobación, de modo que puede condicionar los envíos a su resultado:

```bash
ascelerate apps review preflight <bundle-id> && ascelerate apps review submit <bundle-id>
```

Con `--json`, `preflight` devuelve un informe estructurado (`{"passed": false, "checks": [{"group", "name", "passed", "detail", "skipped"}]}`, donde `skipped` solo aparece en los productos que ha retirado de la venta, que cuentan como superados) y mantiene el mismo comportamiento de los códigos de salida. Es ideal para las comprobaciones de CI que deben indicar *qué* comprobación ha fallado.
