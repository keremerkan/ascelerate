---
sidebar_position: 22
title: Usuarios
---

# Usuarios

Las personas del equipo y las invitaciones pendientes: sus funciones, las apps que ven y si pueden usar Certificados, identificadores y perfiles. Las personas se indican por su **correo electrónico** o ID, las apps por bundle ID o alias. Cambiar funciones o quitar a alguien requiere una clave de administrador.

## Listar

```bash
ascelerate users
ascelerate users info someone@example.com
ascelerate users invitations
```

`users` muestra a todos con sus funciones, cuántas apps ven y su acceso a Certificados, identificadores y perfiles; `info` muestra a una persona con sus apps. `invitations` muestra las invitaciones aún no aceptadas, con su caducidad. Los tres aceptan `--json`.

## Modificar

```bash
ascelerate users update someone@example.com --roles developer,marketing
ascelerate users update someone@example.com --apps com.example.app,myalias
ascelerate users update someone@example.com --all-apps --provisioning true
ascelerate users remove someone@example.com
```

`--roles` reemplaza sus funciones (`admin`, `finance`, `sales`, `marketing`, `app-manager`, `developer`, `access-to-reports`, `customer-support`, `create-apps`, …). `--apps` reemplaza las apps que ve; `--all-apps` le da todas. Cada comando muestra los cambios y pide confirmación. `remove` quita a la persona del equipo de inmediato.

## Invitar

```bash
ascelerate users invite --email someone@example.com --first-name Ada --last-name Lovelace --roles developer --apps com.example.app
ascelerate users cancel-invitation someone@example.com
```

App Store Connect envía la invitación en cuanto se crea. Sin `--apps` la persona ve todas las apps; `--provisioning` da acceso a Certificados, identificadores y perfiles.
