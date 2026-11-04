---
sidebar_position: 7
title: Testers de sandbox
---

# Testers de sandbox

Las cuentas de Apple que compran compras dentro de la app y suscripciones en el sandbox. Un tester se indica por su **cuenta de Apple** (correo electrónico) o su ID. Crear y eliminar testers se hace en App Store Connect (Usuarios y acceso > Sandbox); la API no lo ofrece.

## Listar

```bash
ascelerate sandbox-testers
ascelerate sandbox-testers --json
```

La cuenta de Apple, el nombre y la tienda de cada tester, con qué rapidez se renuevan sus suscripciones, si sus compras se interrumpen y si puede usar Apple Pay.

## Modificar

```bash
ascelerate sandbox-testers update tester@example.com --renewal-rate 3m
ascelerate sandbox-testers update tester@example.com --territory DEU --interrupt-purchases true
```

`--territory` fija la tienda (un código de territorio de tres letras). `--interrupt-purchases` detiene las compras para un paso adicional, como aceptar condiciones o actualizar el pago. `--renewal-rate` fija con qué rapidez se renueva una suscripción mensual para el tester: `1h`, `30m`, `15m`, `5m` o `3m` (otras duraciones en proporción). El comando muestra los cambios y pide confirmación.

## Borrar el historial de compras

```bash
ascelerate sandbox-testers clear-history tester@example.com other@example.com
ascelerate sandbox-testers clear-history --all
```

Olvida las compras dentro de la app y las suscripciones de los testers, para que se puedan comprar de nuevo desde el principio. Pide confirmación antes.
