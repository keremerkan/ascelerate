---
sidebar_position: 3
title: Skill para agentes de programación con IA
---

# Skill para agentes de programación con IA

ascelerate incluye un archivo de skill que da a los agentes de programación con IA (Claude Code, Grok Build, Cursor, Windsurf, GitHub Copilot) un conocimiento completo de todos los comandos, formatos JSON y workflows.

## Instalación con el binario

```bash
ascelerate install-skill          # instala o actualiza para cada agente detectado
ascelerate install-skill --all    # incluye todos los agentes compatibles (p. ej. Copilot)
```

Detecta automáticamente Claude Code, Grok Build (que lee de forma nativa la ruta de skills de Claude Code), Cursor y Windsurf (y GitHub Copilot con `--all`), instala o actualiza la skill para cada uno y, en cada ejecución, comprueba si hay skills desactualizadas para avisarle después de una actualización. Para eliminarla de todos los agentes:

```bash
ascelerate install-skill --uninstall
```

## Instalación con npx (cualquier agente de programación con IA)

```bash
npx ascelerate-skill
```

Muestra un menú interactivo para elegir su agente e instala la skill en el directorio correspondiente. Ambos instaladores descargan el archivo de skill de GitHub en la release que corresponde a su versión (`install-skill`: la del binario, `npx`: la del paquete), de modo que describe los comandos de esa release; si esa release no tiene ninguno, toman el de `main` y lo indican.

Para eliminarla:

```bash
npx ascelerate-skill --uninstall
```

## Qué permite la skill

Con la skill instalada, su agente de programación con IA puede:

- Ejecutar cualquier comando de ascelerate en su nombre
- Crear archivos de workflow para su proceso de publicación
- Gestionar localizaciones en varios idiomas
- Llevar a cabo todo el proceso de archivar, subir y enviar a revisión
- Trabajar con perfiles de suministro, certificados y dispositivos
