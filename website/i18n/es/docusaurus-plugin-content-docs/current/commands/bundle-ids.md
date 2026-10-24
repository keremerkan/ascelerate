---
sidebar_position: 10
title: Bundle IDs
---

# Bundle IDs

Todos los comandos de Bundle ID admiten el modo interactivo, así que los argumentos son opcionales.

## Listar

```bash
ascelerate bundle-ids list
ascelerate bundle-ids list --platform IOS
```

## Detalles

```bash
# Selector interactivo
ascelerate bundle-ids info

# Por identificador
ascelerate bundle-ids info com.example.MyApp
```

## Registrar

```bash
# Preguntas interactivas
ascelerate bundle-ids register

# No interactivo
ascelerate bundle-ids register --name "My App" --identifier com.example.MyApp --platform IOS
```

## Cambiar el nombre

```bash
ascelerate bundle-ids update
ascelerate bundle-ids update com.example.MyApp --name "My Renamed App"
```

El identificador en sí no se puede modificar; solo se puede cambiar el nombre.

## Eliminar

```bash
ascelerate bundle-ids delete
ascelerate bundle-ids delete com.example.MyApp
```

## Capacidades

### Activar

```bash
# Selectores interactivos (solo muestra las capacidades que aún no están activadas)
ascelerate bundle-ids enable-capability

# No interactivo
ascelerate bundle-ids enable-capability com.example.MyApp --type PUSH_NOTIFICATIONS
```

### Desactivar

```bash
# Elija entre las capacidades activadas actualmente
ascelerate bundle-ids disable-capability
ascelerate bundle-ids disable-capability com.example.MyApp
```

Después de activar o desactivar una capacidad, si existen perfiles de suministro para ese Bundle ID, el comando ofrece volver a generarlos (es necesario para que los cambios surtan efecto).

:::note
Algunas capacidades (p. ej. App Groups, iCloud, Associated Domains) requieren una configuración adicional en el [portal de Apple Developer](https://developer.apple.com/account/resources) después de activarlas.
:::
