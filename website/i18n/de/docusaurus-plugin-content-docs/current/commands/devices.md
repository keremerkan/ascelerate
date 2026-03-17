---
sidebar_position: 8
title: Geräte
---

# Geräte

Alle Gerätebefehle unterstützen den interaktiven Modus — Argumente sind optional. Werden sie weggelassen, zeigt der Befehl nummerierte Listen zur Auswahl an.

## Auflisten

```bash
ascelerate devices list
ascelerate devices list --platform IOS --status ENABLED
```

## Details

```bash
# Interaktive Auswahl
ascelerate devices info

# Nach Name oder UDID
ascelerate devices info "My iPhone"
```

## Registrieren

```bash
# Interaktive Eingabeaufforderungen
ascelerate devices register

# Nicht-interaktiv
ascelerate devices register --name "My iPhone" --udid 00008101-XXXXXXXXXXXX --platform IOS
```

## Aktualisieren

```bash
# Interaktive Auswahl und Aktualisierungseingaben
ascelerate devices update

# Ein Gerät umbenennen
ascelerate devices update "My iPhone" --name "Work iPhone"

# Ein Gerät deaktivieren
ascelerate devices update "My iPhone" --status DISABLED
```
