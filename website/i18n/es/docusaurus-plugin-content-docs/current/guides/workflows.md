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

## Anidamiento

Un workflow puede llamar a otros workflows (`run-workflow` dentro de un archivo de workflow). Las referencias circulares se detectan y se impiden.

## Integración con el proceso de compilación

`builds upload` guarda internamente el número de la compilación subida, de modo que los comandos `await-processing` y `build attach-latest` posteriores usan automáticamente esa compilación. Así se evitan problemas por el retraso con el que la API refleja los cambios.
