---
sidebar_position: 2
title: Compilaciones
---

# Compilaciones

## Listar compilaciones

```bash
ascelerate builds list
ascelerate builds list --bundle-id <bundle-id>
ascelerate builds list --bundle-id <bundle-id> --version 2.1.0
ascelerate builds list --bundle-id <bundle-id> --platform macos
```

La salida muestra la versión de la app, la plataforma, el número de compilación, el estado de procesamiento y la fecha de subida de cada compilación. Añada `--json` para obtener una salida legible por máquinas ([convenciones](../guides/automation.md#json-output)).

## Archivar

```bash
ascelerate builds archive
ascelerate builds archive --scheme MyApp --output ./archives
```

El comando `archive` detecta automáticamente el `.xcworkspace` o el `.xcodeproj` del directorio actual y elige el esquema si solo hay uno.

Sin `--destination`, archiva para la plataforma del esquema (`generic/platform=macOS` en una app de macOS). Una app que se compila para varias plataformas se archiva para iOS, salvo que indique `--destination`.

## Archivos de Xcode

```bash
ascelerate builds archives
ascelerate builds archives --bundle-id com.example.MyApp --platform macos --limit 1 --json
```

Muestra los archivos de Xcode de su ubicación habitual (`~/Library/Developer/Xcode/Archives`), del más reciente al más antiguo, con su Bundle ID, versión, número de compilación, plataforma y fecha. `--bundle-id` y `--platform` acotan la lista; `--json` incluye además la ruta de cada archivo.

## Validar

```bash
ascelerate builds validate MyApp.ipa
```

## Subir

```bash
ascelerate builds upload MyApp.ipa
```

Acepta archivos `.ipa`, `.pkg` o `.xcarchive`. Si recibe un `.xcarchive`, detecta su plataforma y lo exporta automáticamente a `.ipa` (familia iOS) o `.pkg` (macOS) antes de subirlo, y pasa a altool la plataforma correspondiente.

```bash
ascelerate builds upload --latest --bundle-id com.example.MyApp --platform macos
```

Con `--latest`, sube el archivo más reciente de la ubicación de archivos de Xcode: el más reciente de una app con `--bundle-id`, y de una plataforma con `--platform` (una app que se vende en iOS y macOS con un mismo Bundle ID tiene archivos de ambas).

Un `.xcarchive` firmado con perfiles de suministro de distribución del App Store (un proyecto con firma manual) se exporta con los perfiles del App Store instalados de su app y sus extensiones, así que Xcode no crea ninguno; los demás archivos se exportan con firma automática. Si indica un archivo, `--bundle-id` rechaza uno que contenga otra app antes de exportar o enviar nada.

### Subir a través de la API de App Store Connect

```bash
ascelerate builds upload MyApp.ipa --api
ascelerate builds upload --latest --bundle-id com.example.MyApp --api
```

Con `--api`, la compilación se envía mediante las subidas de compilaciones de la API de App Store Connect en lugar de altool, con la misma clave de API que el resto de comandos. Acepta un `.ipa` o un `.pkg` de Mac (o un `.xcarchive`, que se exporta antes), lee la versión y el número de compilación de la app que contiene, sube el archivo por fragmentos con una barra de progreso en el terminal (de uno en uno; consulte [Fragmentos de subida](../guides/automation.md#upload-chunks)) y espera a que App Store Connect acepte el archivo. Si Apple lo rechaza, el comando falla con los códigos de error y las descripciones de Apple; las advertencias se muestran tras una subida correcta. Después, el procesamiento continúa como de costumbre (consulte [Esperar al procesamiento](#await-processing)).

Por ahora, altool sigue siendo la opción predeterminada.

### Progreso para otras herramientas

```bash
ascelerate builds archive --scheme MyApp --json-events
ascelerate builds upload MyApp.ipa --api --json-events
```

Con `--json-events`, ambos comandos escriben un objeto JSON por línea en stdout (`step`, `archived` con la ruta del archivo de Xcode, `uploading`, `progress`, `processing` y `finished` con las advertencias de Apple) y trasladan su salida legible, incluida la de xcodebuild, a stderr, igual que `screenshot run --json-events`. Al archivar, xcodebuild solo muestra entonces advertencias y errores.

## Historial de subidas

```bash
ascelerate builds uploads <bundle-id>
ascelerate builds uploads <bundle-id> --platform macos --limit 20
ascelerate builds uploads <bundle-id> --delete-stale
```

Muestra las subidas recientes de la app, tanto si se hicieron con altool como con Xcode o `--api`, con su estado (Awaiting Upload, Processing, Complete, Failed) y los errores y advertencias que Apple les adjuntó. Consúltelo cuando una subida no llegue a convertirse en una compilación. Añada `--json` para obtener una salida legible por máquinas.

Una conexión que se corta en mal momento puede dejar un registro de subida esperando un archivo que nunca llegará. Las subidas con `--api` eliminan esos registros de la misma compilación cuando terminan correctamente, y `--delete-stale` elimina los que queden: registros que siguen esperando un archivo mientras otra subida de la misma compilación ha avanzado, o que llevan más de un día esperando. Nunca se elimina una subida que todavía está en curso.

## Esperar al procesamiento {#await-processing}

```bash
ascelerate builds await-processing <bundle-id>
ascelerate builds await-processing <bundle-id> --build-version 903
ascelerate builds await-processing <bundle-id> --build-version 903 --platform macos
```

Las compilaciones recién subidas pueden tardar unos minutos en aparecer en la API, así que el comando consulta periódicamente, con un indicador de progreso, hasta que encuentra la compilación y esta termina de procesarse.

## Asociar una compilación a una versión

```bash
# Elegir y asociar una compilación de forma interactiva
ascelerate apps build attach <bundle-id>
ascelerate apps build attach <bundle-id> --version 2.1.0

# Asociar automáticamente la compilación más reciente
ascelerate apps build attach-latest <bundle-id>
ascelerate apps build attach-latest <bundle-id> --platform macos

# Quitar la compilación asociada a una versión
ascelerate apps build detach <bundle-id>
```

Si la compilación más reciente aún se está procesando, `build attach-latest` pregunta si desea esperar. Con `--yes`, espera automáticamente.

La búsqueda de compilaciones tiene en cuenta la plataforma: en las apps de compra universal, las compilaciones de iOS y macOS pueden compartir número de compilación, así que los comandos de asociación solo consideran las compilaciones de la misma plataforma que la versión de destino.
