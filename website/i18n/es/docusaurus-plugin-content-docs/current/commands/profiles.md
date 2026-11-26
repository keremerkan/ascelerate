---
sidebar_position: 11
title: Perfiles de suministro
---

# Perfiles de suministro

Todos los comandos de perfiles admiten el modo interactivo, así que los argumentos son opcionales.

## Listar

```bash
ascelerate profiles list
ascelerate profiles list --type IOS_APP_STORE --state ACTIVE
```

## Detalles

```bash
ascelerate profiles info
ascelerate profiles info "My App Store Profile"
```

## Descargar

```bash
ascelerate profiles download
ascelerate profiles download "My App Store Profile" --output ./profiles/
```

## Crear

```bash
# Totalmente interactivo
ascelerate profiles create

# No interactivo
ascelerate profiles create --name "My Profile" --type IOS_APP_STORE --bundle-id com.example.MyApp --certificates all
```

`--certificates all` usa todos los certificados de la familia correspondiente (distribución, desarrollo o Developer ID). También puede indicar números de serie: `--certificates ABC123,DEF456`.

## Eliminar

```bash
ascelerate profiles delete
ascelerate profiles delete "My App Store Profile"
```

## Volver a emitir

Vuelva a emitir perfiles eliminándolos y creándolos de nuevo con los certificados más recientes de la familia correspondiente:

```bash
# Interactivo: elija entre todos los perfiles (muestra su estado)
ascelerate profiles reissue

# Volver a emitir un perfil concreto por su nombre
ascelerate profiles reissue "My Profile"

# Volver a emitir todos los perfiles no válidos
ascelerate profiles reissue --all-invalid

# Volver a emitir todos los perfiles, sea cual sea su estado
ascelerate profiles reissue --all

# Volver a emitir todos, con todos los dispositivos activados para desarrollo/ad hoc
ascelerate profiles reissue --all --all-devices

# Usar certificados concretos en lugar de detectarlos automáticamente
ascelerate profiles reissue --all --to-certs ABC123,DEF456
```

Sin `--to-certs`, cada perfil recibe todos los certificados que encajan con su tipo, no solo los que tenía. `--to-certs` indica certificados concretos por número de serie o nombre (un nombre debe corresponder a un solo certificado), y todos los perfiles deben poder contenerlos. Los perfiles de desarrollo y ad hoc conservan sus propios dispositivos activados, o reciben todos los dispositivos activados con `--all-devices`, en la medida en que encajen con la plataforma del perfil. Todo esto se comprueba antes de eliminar ningún perfil.

Los certificados caducados nunca entran en un perfil reemitido, con o sin `--to-certs`.

## Más opciones

Opciones que los ejemplos anteriores no muestran:

- `profiles create` `--devices`: nombres de dispositivos o UDID, separados por comas, o all (perfiles de desarrollo y ad hoc)
