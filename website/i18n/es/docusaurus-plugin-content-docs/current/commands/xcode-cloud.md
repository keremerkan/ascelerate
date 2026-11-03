---
sidebar_position: 21
title: Xcode Cloud
---

# Xcode Cloud

Siga e inicie compilaciones de Xcode Cloud: sus productos, sus workflows y cada ejecución de compilación con sus acciones, problemas, resultados de pruebas y artefactos.

Un **producto** se crea en Xcode la primera vez que conecta un repositorio (**Integrate > Create Workflow**); la API no puede crearlo. A partir de ahí, todo lo que se describe aquí funciona desde la línea de comandos. Un producto se indica por el **Bundle ID** de su app (o un alias), su nombre o su ID; un workflow, por su **nombre** o su ID, y una ejecución de compilación, por su **número** o su ID.

## Productos

```bash
ascelerate xcode-cloud products
```

Muestra los productos del equipo (apps y frameworks) con su Bundle ID y su repositorio.

## Workflows

```bash
ascelerate xcode-cloud workflows <bundle-id>
ascelerate xcode-cloud workflows info <bundle-id> "Release"
ascelerate xcode-cloud workflows update <bundle-id> "Default" --manual-only
ascelerate xcode-cloud workflows update <bundle-id> "Release" --branch-changes "main,release/*" --xcode "Xcode 27.2" --clean false
ascelerate xcode-cloud workflows create <bundle-id> --like "Default" --name "TestFlight" --action archive:MyApp:ios --manual-branches main
ascelerate xcode-cloud workflows disable <bundle-id> "Nightly"
ascelerate xcode-cloud workflows enable <bundle-id> "Nightly"
ascelerate xcode-cloud workflows delete <bundle-id> "Old workflow"
```

`info` muestra las condiciones de inicio de un workflow (cambios en ramas y etiquetas, pull requests, programaciones y lo que se puede iniciar manualmente), sus acciones (compilar, probar, analizar y archivar, con esquema, plataforma y distribución) y el repositorio, el proyecto y las versiones de Xcode y macOS que utiliza. `update --manual-only` hace que un workflow deje de iniciarse por sí solo (cambios en ramas y etiquetas, pull requests, programación) y conserva lo que se puede iniciar manualmente. `update` también cambia el nombre, la descripción, las compilaciones limpias, “Restrict Editing”, las versiones de Xcode y macOS y cada condición de inicio: `--branch-changes`, `--tag-changes`, `--pull-requests` (con `--pull-request-source`), `--manual-branches`, `--manual-tags` y `--manual-pull-requests` aceptan nombres (`release/*` para los que empiezan así), `any` u `off`; además están `--auto-cancel` y `--remove-schedule`. Antes de guardar muestra los cambios y pide confirmación. `--action TIPO:ESQUEMA[:PLATAFORMA]` (repetible) reemplaza las acciones y `--distribution internal|app-store|none` fija la distribución de un archivo. `create` crea un workflow como copia de otro (`--like`, innecesario si el producto solo tiene uno) y acepta las mismas opciones. La API no tiene variables de entorno ni post-actions, así que añádalas (por ejemplo, grupos de TestFlight) en App Store Connect. Un workflow desactivado no inicia compilaciones. Al eliminar un workflow se conservan sus ejecuciones de compilación.

## Ejecuciones de compilación

```bash
ascelerate xcode-cloud runs <bundle-id>                         # las más recientes primero
ascelerate xcode-cloud runs <bundle-id> --workflow "Release" --limit 50
ascelerate xcode-cloud runs info <bundle-id> 42                 # detalles y acciones
ascelerate xcode-cloud runs issues <bundle-id> 42 [--errors]
ascelerate xcode-cloud runs tests <bundle-id> 42 [--failed]
ascelerate xcode-cloud runs logs <bundle-id> 42 [--action "Build - iOS"] [--show ci_post_clone.log]
ascelerate xcode-cloud runs artifacts <bundle-id> 42
ascelerate xcode-cloud runs artifacts <bundle-id> 42 --type LOG_BUNDLE --download ./logs
```

Cada ejecución muestra su estado, la rama, etiqueta o pull request compilados, el commit y cuánto tardó; `runs info` añade sus acciones con el número de errores, advertencias y pruebas fallidas (Apple no los envía, así que se cuentan a partir de los problemas de cada acción). Si un archivo se subió a App Store Connect, también muestra la compilación subida con su estado de procesamiento y de TestFlight. `issues` muestra los errores y advertencias de cada acción con su archivo y línea; `tests` muestra los resultados de las pruebas por destino (dispositivo y sistema operativo), con el mensaje de error de cada prueba fallida. `logs` lee el paquete de registros de cada acción: los del script post-clone, la resolución de paquetes y xcodebuild, listados con su número de líneas o mostrados con `--show`. `artifacts` muestra los registros, archivos, result bundles y productos; `--download` los guarda (`--type` acota la selección).

## Iniciar una compilación

```bash
ascelerate xcode-cloud start <bundle-id> "Release" --branch main
ascelerate xcode-cloud start <bundle-id> "Release" --tag v2.1
ascelerate xcode-cloud start <bundle-id> "PR checks" --pull-request 128
ascelerate xcode-cloud rerun <bundle-id> 42 [--clean]
```

`start` compila la rama, la etiqueta o el pull request que indique; si no indica ninguno, Xcode Cloud compila lo que la condición de inicio del workflow permite iniciar manualmente. `rerun` vuelve a compilar el commit de una ejecución anterior con su workflow. `--clean` compila sin la caché. La API no puede cancelar una compilación.

## Repositorios y versiones de Xcode

```bash
ascelerate xcode-cloud repositories
ascelerate xcode-cloud xcode-versions
```

`xcode-versions` muestra las versiones de Xcode que ofrece Xcode Cloud, con las versiones de macOS en las que se ejecuta cada una.

Todos los comandos de listado e información aceptan `--json`.
