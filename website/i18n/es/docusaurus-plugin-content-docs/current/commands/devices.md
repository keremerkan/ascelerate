---
sidebar_position: 8
title: Dispositivos
---

# Dispositivos

Todos los comandos de dispositivos admiten el modo interactivo: los argumentos son opcionales. Si se omiten, el comando pregunta mediante listas numeradas.

## Listar

```bash
ascelerate devices list
ascelerate devices list --platform IOS --status ENABLED
```

## Detalles

```bash
# Selector interactivo
ascelerate devices info

# Por nombre o UDID
ascelerate devices info "My iPhone"
```

## Registrar

```bash
# Preguntas interactivas
ascelerate devices register

# Modo no interactivo
ascelerate devices register --name "My iPhone" --udid 00008101-XXXXXXXXXXXX --platform IOS
```

## Actualizar

```bash
# Selector interactivo y preguntas para la actualización
ascelerate devices update

# Cambiar el nombre de un dispositivo
ascelerate devices update "My iPhone" --name "Work iPhone"

# Desactivar un dispositivo
ascelerate devices update "My iPhone" --status DISABLED
```
