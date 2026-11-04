---
sidebar_position: 1
title: Workflows
---

# Workflows

Encadene varios comandos en una sola ejecución automatizada con un archivo de workflow:

```bash
ascelerate run-workflow release.txt
ascelerate run-workflow release.txt --yes   # omite todas las preguntas (CI/CD)
ascelerate run-workflow                     # elige de forma interactiva entre los archivos .workflow/.txt
```

Un archivo de workflow es un archivo de texto sin formato con un comando por línea (sin el prefijo `ascelerate`). Las líneas que empiezan por `#` son comentarios y las líneas en blanco se ignoran. Se admiten las extensiones `.workflow` y `.txt`.

## Ejemplo

`release.txt` para enviar la versión 2.1.0 de una app de ejemplo:

```
# Workflow de publicación de MyApp v2.1.0

# Crear la nueva versión en App Store Connect
apps create-version com.example.MyApp 2.1.0

# Compilar, validar y subir
builds archive --scheme MyApp
builds validate --latest --bundle-id com.example.MyApp
builds upload --latest --bundle-id com.example.MyApp

# Esperar a que termine el procesamiento de la compilación
builds await-processing com.example.MyApp

# Actualizar las localizaciones y asociar la compilación
apps localizations import com.example.MyApp --file localizations.json
apps build attach-latest com.example.MyApp

# Enviar a revisión
apps review submit com.example.MyApp
```

## Confirmaciones

Sin `--yes`, el workflow pide confirmación antes de empezar, y cada comando sigue preguntando donde lo haría normalmente (por ejemplo, antes de enviar a revisión). Con `--yes`, se omiten todas las preguntas y la ejecución es totalmente desatendida.

## Comprobar un workflow

```bash
ascelerate run-workflow release.txt --check          # every step parses; nothing runs
ascelerate run-workflow release.txt --check --json   # each step's line, command and error
```

`--check` analiza los argumentos y las opciones de cada paso sin ejecutar nada, y muestra los pasos que no se pueden analizar con su línea en el archivo.

## Seguir una ejecución desde otro programa

```bash
ascelerate run-workflow release.txt --json-events
```

Con `--json-events`, stdout lleva un evento JSON por línea y todo lo legible, incluida la salida de los propios pasos, va a stderr. Los eventos son `workflow` (los pasos y sus líneas), `step` (`running`, luego `succeeded`, `failed` con el error o `dry-run`), `finished` y `prompt` para cada pregunta que hace un paso: su `kind` (`confirm`, `choice`, `choices` o `text`), su `message` y sus `options`. Después, el paso lee la respuesta de stdin, una línea (`y` o `n`, el número de una opción desde 1, o el texto). El workflow no se confirma antes, porque ya lo hizo el programa que lo ejecuta. Los eventos de un workflow anidado llevan su `depth`. Los pasos que informan de eventos propios cuando se ejecutan solos (`builds archive`, `builds upload`, `screenshot`) no los añaden aquí; su progreso va a stderr, salvo el de una subida con `--api`, que llega como eventos `progress` de su paso (`index`, `sent` de `bytes`). La salida de xcodebuild de los pasos es reducida (advertencias y errores), salvo que `ascelerate settings --xcodebuild-output full` indique otra cosa.

## Anidamiento

Un workflow puede llamar a otros workflows (`run-workflow` dentro de un archivo de workflow). Las referencias circulares se detectan y se impiden.

## Integración con el proceso de compilación

`builds upload` guarda internamente el número de la compilación subida, de modo que los comandos `await-processing` y `build attach-latest` posteriores usan automáticamente esa compilación. Así se evitan problemas por el retraso con el que la API refleja los cambios.
