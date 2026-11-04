---
sidebar_position: 7
title: Sandbox-Tester
---

# Sandbox-Tester

Die Apple Accounts, die In-App-Käufe und Abonnements in der Sandbox kaufen. Ein Tester wird über seinen **Apple Account** (E-Mail-Adresse) oder seine ID angegeben. Tester anlegen und löschen geht nur in App Store Connect (Benutzer und Zugriff > Sandbox); die API bietet das nicht.

## Auflisten

```bash
ascelerate sandbox-testers
ascelerate sandbox-testers --json
```

Für jeden Tester: Apple Account, Name, Storefront, wie schnell seine Abonnements verlängert werden, ob seine Käufe unterbrochen werden und ob er Apple Pay verwenden kann.

## Ändern

```bash
ascelerate sandbox-testers update tester@example.com --renewal-rate 3m
ascelerate sandbox-testers update tester@example.com --territory DEU --interrupt-purchases true
```

`--territory` legt die Storefront fest (ein dreistelliger Ländercode). `--interrupt-purchases` unterbricht Käufe für einen zusätzlichen Schritt, etwa das Akzeptieren von Bedingungen oder das Aktualisieren der Zahlungsdaten. `--renewal-rate` legt fest, wie schnell ein Monatsabonnement für den Tester verlängert wird: `1h`, `30m`, `15m`, `5m` oder `3m` (andere Laufzeiten entsprechend). Der Befehl zeigt die Änderungen und fragt vorher nach.

## Kaufverlauf löschen

```bash
ascelerate sandbox-testers clear-history tester@example.com other@example.com
ascelerate sandbox-testers clear-history --all
```

Vergisst die In-App-Käufe und Abonnements der Tester, sodass sie von vorn gekauft werden können. Der Befehl fragt vorher nach.
