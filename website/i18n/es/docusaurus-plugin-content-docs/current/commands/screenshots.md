---
sidebar_position: 12
title: Capturas de pantalla
---

# Capturas de pantalla

Tome las capturas de pantalla del App Store directamente desde los simuladores de iOS/iPadOS mediante pruebas de interfaz. Sustituye a [fastlane snapshot](https://docs.fastlane.tools/actions/snapshot/).

## Inicio rápido

```bash
ascelerate screenshot init                  # Crea la configuración y el helper en ascelerate/
ascelerate screenshot                       # Toma las capturas de pantalla
```

## Configuración con un agente de programación con IA

Para tomar capturas hacen falta un target de pruebas de interfaz, el helper de capturas, un modo de capturas con contenido de demostración en la app, las propias pruebas y la configuración. Un agente de programación puede prepararlo todo:

```bash
ascelerate screenshot setup-prompt          # Muestra las instrucciones de configuración
ascelerate screenshot setup-prompt --copy   # Las copia en el portapapeles
```

Pegue las instrucciones en un agente de programación que trabaje en el proyecto (Claude Code, Codex, Cursor, el asistente de programación de Xcode…). Parten de lo que el proyecto ya tiene (proyectos, esquemas, targets de pruebas de interfaz, localizaciones, configuración, versión del helper, simuladores instalados), así que al volver a ejecutar el comando verá lo que falta. También tratan los marcos de dispositivo, que usted descarga de los [recursos de diseño](https://developer.apple.com/design/resources/) de Apple (Product Bezels).

`--design` muestra en su lugar las instrucciones para un generador de diseños: una pequeña app web en `app-store-screenshots/` que convierte las capturas enmarcadas en imágenes para el App Store con titulares en todos los idiomas, exportadas para `ascelerate apps media upload` (consulte [Capturas y vistas previas](media.md#designing-app-store-images)).

## Comandos

### Ejecutar

```bash
ascelerate screenshot                       # Toma las capturas de pantalla
ascelerate screenshot run                   # Igual que el anterior
ascelerate screenshot --json-events         # Progreso como eventos JSON Lines en stdout
```

Siempre usa `ascelerate/screenshot.yml` del directorio actual.

`--json-events` está pensado para otras herramientas que siguen una ejecución: stdout contiene un objeto JSON por línea (`start`, `build`, `language`, `device` con pasos como `testing`, `passed`, `failed` y `collected`, y `finished` con todos los resultados), y el progreso legible pasa a stderr.

### Init

```bash
ascelerate screenshot init
```

Crea `ascelerate/screenshot.yml` y `ascelerate/ScreenshotHelper.swift` en el directorio `ascelerate/`. Pide confirmación antes de escribir (`-y` la omite). No sobrescribe archivos existentes.

### Crear el helper

```bash
ascelerate screenshot create-helper         # Genera ScreenshotHelper.swift
ascelerate screenshot create-helper -o CustomHelper.swift
ascelerate screenshot create-helper -o UITests/ScreenshotHelper.swift -y   # Sobrescribe sin preguntar
```

### Enmarcar

```bash
ascelerate screenshot frame                    # Enmarca las capturas con marcos de dispositivo
```

Enmarca las capturas de pantalla tomadas con imágenes de marcos de dispositivo. Usa los ajustes `frameDevice` y `deviceBezel` de la configuración. Puede ejecutarse por separado después de tomar las capturas.

### Doctor

```bash
ascelerate screenshot doctor                   # Comprueba la configuración y el entorno
ascelerate screenshot doctor --json            # Lo mismo en JSON
```

Valida la configuración de capturas y el entorno: comprueba el archivo de configuración, la existencia del proyecto o workspace, la disponibilidad de xcodebuild y simctl, los simuladores, la versión del archivo helper, los archivos de marcos de dispositivo y los directorios de salida. Muestra una lista de comprobación con indicadores de correcto, error o advertencia. Con `--json` muestra la configuración (esquema, dispositivos, idiomas, directorio de salida) y cada comprobación con su estado (`pass`, `warn` o `fail`).

## Configuración (`ascelerate/screenshot.yml`)

```yaml
workspace: MyApp.xcworkspace
# project: MyApp.xcodeproj               # Use project en lugar de workspace
scheme: AppUITests
devices:
  - simulator: iPhone 17 Pro Max
    # frameDevice: true
    # deviceBezel: ./bezels/iPhone 17 Pro Max.png
  - simulator: iPad Pro 13-inch (M5)
    # frameDevice: true
    # deviceBezel: ./bezels/iPad Pro 13-inch (M5).png
languages:
  - en-US
  - de-DE
outputDirectory: ./screenshots
# framedOutputDirectory: ./screenshots/framed
clearPreviousScreenshots: true
eraseSimulator: false
localizeSimulator: true
overrideStatusBar: true
darkMode: false
disableAnimations: true
waitAfterBoot: 0
# waitAfterEraseAndReboot: 30           # Espera adicional para las alertas del sistema del primer arranque
# statusBarArguments: "--time '9:41' --dataNetwork wifi"
# testWithoutBuilding: true               # Omite la compilación y usa el xctestrun existente
# cleanBuild: false
# headless: false                         # No abre las ventanas de los simuladores (DeviceHub / Simulator.app)
# helperPath: AppUITests/ScreenshotHelper.swift
# launchArguments:
#   - -ui_testing
# configuration: Debug                    # Configuración de compilación
# testplan: MyTestPlan                    # Nombre del plan de pruebas de Xcode
# numberOfRetries: 0                     # Reintenta los idiomas fallidos (borra y reinicia el simulador)
# stopAfterFirstError: false             # Detiene todos los dispositivos al primer fallo
# reinstallApp: false                    # Elimina y reinstala la app antes de las pruebas
# disableAssetDownloads: false           # Desactiva mobileassetd (sin descargas de recursos de Siri, teclado y ML; también bloquea los recursos de ML en el dispositivo)
# xcargs: SWIFT_ACTIVE_COMPILATION_CONDITIONS=SCREENSHOTS
```

## Uso en las pruebas de interfaz

Añada `ScreenshotHelper.swift` a su target de pruebas de interfaz:

```swift
override func setUp() {
    setupScreenshots(app)
    app.launch()
}

func testScreenshots() {
    screenshot("01-home")
    app.buttons["Settings"].tap()
    screenshot("02-settings")
}
```

Su app puede detectar el modo de capturas así:

```swift
if ProcessInfo.processInfo.arguments.contains("-ASC_SCREENSHOT") {
    // Mostrar datos de demostración, ocultar la interfaz de depuración, etc.
}
```

El helper también ofrece `disableAnimationsIfNeeded()` para desactivar las animaciones cuando `disableAnimations` está activado en la configuración:

```swift
override func setUp() {
    setupScreenshots(app)
    disableAnimationsIfNeeded()
    app.launch()
}
```

### iPhone Duo

En el simulador del iPhone Duo (Xcode 27.1 o posterior), `setHinge(.open)` despliega el dispositivo y `setHinge(.closed)` lo pliega; después espera a que el sistema pase la app a la pantalla correspondiente, de modo que el siguiente `screenshot()` capture esa pantalla. El simulador siempre arranca plegado.

```swift
func testScreenshots() {
    screenshot("01-folded")
    setHinge(.open)
    screenshot("02-unfolded")
}
```

Desplegado el dispositivo, muchas apps organizan su interfaz como en el iPad, pero `UIDevice.current.userInterfaceIdiom` sigue indicando `.phone` en el ejecutor de pruebas. Para elegir el camino correcto en sus pruebas, compruebe `ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4"`.

:::caution
No existe una API oficial para la bisagra. El helper envía el mismo evento de entrada que el control deslizante de la bisagra de Device Hub, así que una futura versión de Xcode podría dejarlo sin efecto.
:::

## Cómo funciona

1. Compila una vez con `build-for-testing` (o lo omite si `testWithoutBuilding: true`)
2. Para cada idioma: arranca todos los simuladores, silencia el aviso «Ready for Apple Intelligence» de iOS 26 (y `mobileassetd` si se ha indicado `disableAssetDownloads`), localiza los simuladores y sustituye la barra de estado
3. Ejecuta las pruebas en paralelo en todos los dispositivos
4. Si se ha indicado `numberOfRetries` y algún dispositivo falla: borra los simuladores fallidos, los vuelve a localizar, los reinicia y lo reintenta
5. Reúne las capturas de pantalla de la caché de cada dispositivo en el directorio de salida
6. Enmarca las capturas con marcos de dispositivo (si `frameDevice` está activado)
7. Los errores se omiten y la ejecución continúa; los registros de error se guardan en la salida

## Salida

```
screenshots/
├── en-US/
│   ├── iPhone 17 Pro Max-01-home.png
│   ├── iPhone 17 Pro Max-02-settings.png
│   └── iPad Pro 13-inch (M5)-01-home.png
└── de-DE/
    └── ...
```

## Marcos de dispositivo

Enmarque las capturas de pantalla tomadas con marcos de dispositivos de Apple.

:::info
Los marcos de dispositivo no se incluyen con ascelerate: descárguelos de [Apple Product Bezels](https://developer.apple.com/design/resources/#product-bezels) (requiere una cuenta de Apple Developer). La descarga es un archivo DMG que contiene los marcos en PNG de todos los dispositivos actuales.
:::

### Configuración

1. Descargue el DMG de Product Bezels de [Apple Design Resources](https://developer.apple.com/design/resources/#product-bezels)
2. Extraiga los archivos PNG de los marcos a una carpeta de su proyecto (por ejemplo, `./bezels/`)
3. Active el enmarcado para cada dispositivo en la configuración:

```yaml
devices:
  - simulator: iPhone 17 Pro Max
    frameDevice: true
    deviceBezel: ./bezels/iPhone 17 Pro Max.png
  - simulator: iPad Pro 13-inch (M5)
    frameDevice: false
```

Un dispositivo puede indicar varios marcos. Cada captura se enmarca con el marco cuya área de pantalla coincide con su tamaño, de modo que las capturas plegadas de un iPhone Duo reciben el marco cerrado y las desplegadas, el marco abierto:

```yaml
devices:
  - simulator: iPhone Duo
    frameDevice: true
    deviceBezel:
      - ./bezels/iPhone Duo - Outer Closed Portrait.png
      - ./bezels/iPhone Duo - Inner Open Landscape.png
```

Las capturas en horizontal usan un marco horizontal si hay uno en la lista; si no, el marco vertical girado.

### Salida

Las capturas enmarcadas se guardan en `framedOutputDirectory` (de forma predeterminada, `{outputDirectory}/framed`):

```
screenshots/framed/
├── en-US/
│   └── iPhone 17 Pro Max-01-home.png
└── de-DE/
    └── ...
```

Solo se enmarcan los dispositivos con `frameDevice: true`. El enmarcado se ejecuta automáticamente después de cada idioma durante `screenshot run`, o por separado con `screenshot frame`.

## Opciones

| Opción | Descripción |
|---|---|
| `clearPreviousScreenshots` | Vacía la carpeta del idioma antes de reunir las capturas (solo si todos los dispositivos terminan correctamente) |
| `eraseSimulator` | Borra el simulador antes de cada idioma |
| `localizeSimulator` | Configura el idioma y la región del simulador para cada idioma |
| `overrideStatusBar` | Sustituye la barra de estado (9:41, cobertura completa, Wi-Fi) |
| `statusBarArguments` | Argumentos personalizados de `xcrun simctl status_bar` |
| `darkMode` | Activa el modo oscuro en los simuladores |
| `disableAnimations` | Desactiva las animaciones durante las pruebas |
| `waitAfterBoot` | Segundos de espera tras arrancar el simulador (predeterminado: 0) |
| `waitAfterEraseAndReboot` | Segundos de espera adicionales cuando el simulador está recién preparado: el primer idioma de la ejecución, o siempre que se haya borrado el simulador (con `eraseSimulator: true` o en un reintento). Da tiempo a que aparezcan las alertas del sistema del primer arranque antes de las capturas. (El aviso «Ready for Apple Intelligence» de iOS 26 se suprime automáticamente y no necesita espera). |
| `testWithoutBuilding` | Omite la compilación y usa el archivo xctestrun existente |
| `cleanBuild` | Ejecuta `clean` antes de compilar |
| `headless` | No abre las ventanas de los simuladores (DeviceHub en Xcode 27, Simulator.app en versiones anteriores) |
| `helperPath` | Ruta de ScreenshotHelper.swift para comprobar su versión |
| `launchArguments` | Argumentos de arranque adicionales que se pasan a la app |
| `configuration` | Configuración de compilación (por ejemplo, Debug o Release) |
| `testplan` | Nombre del plan de pruebas de Xcode |
| `numberOfRetries` | Número de reintentos de los idiomas fallidos: borra el simulador, lo vuelve a localizar, lo reinicia y repite las pruebas. Solo reintenta los dispositivos que fallaron. Los resultados reintentados se marcan en la tabla de resumen. |
| `stopAfterFirstError` | Detiene todos los dispositivos tras el primer fallo |
| `reinstallApp` | Elimina y reinstala la app antes de ejecutar las pruebas |
| `disableAssetDownloads` | Desactiva `mobileassetd` en el simulador para que deje de descargar gigabytes de recursos de Siri, del teclado y de ML en los simuladores recién borrados. También bloquea los recursos de ML en el dispositivo que algunas apps necesitan (por ejemplo, el reconocimiento de texto), así que déjelo desactivado si sus capturas dependen de ellos. Se aplica en cada preparación, ya que un borrado lo restablece. |
| `xcargs` | Argumentos adicionales que se pasan a `xcodebuild` |
| `frameDevice` | Activa el enmarcado con marco de dispositivo para este dispositivo (por dispositivo) |
| `deviceBezel` | Ruta del archivo PNG del marco del dispositivo, o una lista de rutas; cada captura usa el marco que se ajusta a su tamaño (por dispositivo) |
| `framedOutputDirectory` | Directorio de salida de las capturas enmarcadas (predeterminado: `{outputDirectory}/framed`) |
