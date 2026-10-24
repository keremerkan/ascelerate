---
sidebar_position: 2
title: Configuración
---

# Configuración

## 1. Cree una clave de API

Vaya a [App Store Connect > Usuarios y acceso > Integraciones > API de App Store Connect](https://appstoreconnect.apple.com/access/integrations/api) y genere una clave nueva. Descargue el archivo de clave privada `.p8`.

## 2. Configure ascelerate

```bash
ascelerate configure
```

El comando le pedirá el **ID de la clave**, el **ID del emisor** y la ruta de su archivo `.p8`. La clave privada se copia en `~/.ascelerate/` con permisos de archivo estrictos (acceso solo para el propietario).

La configuración se guarda en `~/.ascelerate/config.json`:

```json
{
    "keyId": "KEY_ID",
    "issuerId": "ISSUER_ID",
    "privateKeyPath": "/Users/.../.ascelerate/AuthKey_XXXXXXXXXX.p8"
}
```

`configure` también le pide un **número de proveedor** opcional (App Store Connect → Pagos e informes financieros). Solo se necesita para los [informes de ventas y financieros](../commands/reports.md) y se guarda en el campo `vendorNumber`. Puede omitirlo y añadirlo más tarde, o indicar `--vendor-number` en cada comando.

Para [Apple Ads](../commands/ads.md), ascelerate necesita credenciales aparte, que `ascelerate ads configure` configura y guarda en una sección `ads` del mismo archivo. Si vuelve a ejecutar `configure`, se conservan.

### Una clave para una sola ejecución

Para ejecutar un comando con otra clave, por ejemplo para otro equipo o en CI, defina las tres variables de entorno. Para esa ejecución tienen prioridad sobre `config.json`, y el archivo no se modifica:

```bash
export ASCELERATE_KEY_ID=KEY_ID
export ASCELERATE_ISSUER_ID=ISSUER_ID
export ASCELERATE_PRIVATE_KEY_PATH=~/keys/AuthKey_KEY_ID.p8
ascelerate apps list
```

`builds archive` y `builds upload` también pasan esta clave a `xcodebuild` (`-authenticationKeyPath`, `-authenticationKeyID`, `-authenticationKeyIssuerID`), de modo que los perfiles se obtienen con la clave y no con el Apple ID con el que se ha iniciado sesión en Xcode. Para ello, la clave debe tener permiso para gestionar certificados, identificadores y perfiles. `ascelerate configure --show` indica qué clave utiliza una ejecución.

## 3. Compruebe que funciona

Ejecute un comando sencillo para comprobar que todo funciona:

```bash
ascelerate apps list
```

Si sus credenciales son correctas, verá una lista con todas sus apps.

## Límite de solicitudes

La API de App Store Connect tiene una cuota de 3600 solicitudes por hora, contadas en una ventana móvil. Puede consultar su uso actual en cualquier momento:

```bash
ascelerate rate-limit
```

```
Hourly limit: 3600 requests (rolling window)
Used:         57
Remaining:    3543 (98%)
```
