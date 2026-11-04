---
sidebar_position: 22
title: Benutzer
---

# Benutzer

Die Personen des Teams und offene Einladungen: ihre Rollen, die Apps, die sie sehen, und ob sie Zertifikate, IDs & Profile verwenden dürfen. Personen werden über ihre **E-Mail-Adresse** oder ID angegeben, Apps über Bundle-ID oder Alias. Rollen ändern oder jemanden entfernen erfordert einen Admin-Schlüssel.

## Auflisten

```bash
ascelerate users
ascelerate users info someone@example.com
ascelerate users invitations
```

`users` listet alle mit ihren Rollen, der Anzahl der Apps, die sie sehen, und ihrem Zugriff auf Zertifikate, IDs & Profile; `info` zeigt eine Person mit ihren Apps. `invitations` listet die noch nicht angenommenen Einladungen mit ihrem Ablaufdatum. Alle drei unterstützen `--json`.

## Ändern

```bash
ascelerate users update someone@example.com --roles developer,marketing
ascelerate users update someone@example.com --apps com.example.app,myalias
ascelerate users update someone@example.com --all-apps --provisioning true
ascelerate users remove someone@example.com
```

`--roles` ersetzt die Rollen (`admin`, `finance`, `sales`, `marketing`, `app-manager`, `developer`, `access-to-reports`, `customer-support`, `create-apps`, …). `--apps` ersetzt die Apps, die die Person sieht; `--all-apps` gibt ihr alle Apps. Jeder Befehl zeigt die Änderungen und fragt vorher nach. `remove` entfernt die Person sofort aus dem Team.

## Einladen

```bash
ascelerate users invite --email someone@example.com --first-name Ada --last-name Lovelace --roles developer --apps com.example.app
ascelerate users cancel-invitation someone@example.com
```

App Store Connect verschickt die Einladung, sobald sie erstellt ist. Ohne `--apps` sieht die Person alle Apps; `--provisioning` gibt Zugriff auf Zertifikate, IDs & Profile.
