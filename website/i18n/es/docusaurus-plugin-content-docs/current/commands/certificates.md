---
sidebar_position: 9
title: Certificados
---

# Certificados

Todos los comandos de certificados admiten el modo interactivo: los argumentos son opcionales.

## Listar

```bash
ascelerate certs list
ascelerate certs list --type DISTRIBUTION
```

## Detalles

```bash
# Selector interactivo
ascelerate certs info

# Por número de serie o nombre visible
ascelerate certs info "Apple Distribution: Example Inc"
```

## Crear

```bash
# Selector interactivo del tipo; genera automáticamente el par de claves RSA y la CSR
ascelerate certs create

# Indicar el tipo
ascelerate certs create --type DISTRIBUTION

# Usar su propia CSR
ascelerate certs create --type DEVELOPMENT --csr my-request.pem
```

Si no se indica `--csr`, el comando genera automáticamente un par de claves RSA y una solicitud de firma de certificado (CSR), y después lo importa todo en el llavero de inicio de sesión.

## Revocar

```bash
# Selector interactivo
ascelerate certs revoke

# Por número de serie
ascelerate certs revoke ABC123DEF456
```
