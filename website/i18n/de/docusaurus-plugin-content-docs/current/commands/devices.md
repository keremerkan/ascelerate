---
sidebar_position: 8
title: Geräte
---

# Geräte

Alle Gerätebefehle unterstützen den interaktiven Modus — Argumente sind optional. Werden sie weggelassen, zeigt der Befehl nummerierte Listen zur Auswahl an.

## Auflisten

```bash
asc devices list
asc devices list --platform IOS --status ENABLED
```

## Details

```bash
# Interaktive Auswahl
asc devices info

# Nach Name oder UDID
asc devices info "My iPhone"
```

## Registrieren

```bash
# Interaktive Eingabeaufforderungen
asc devices register

# Nicht-interaktiv
asc devices register --name "My iPhone" --udid 00008101-XXXXXXXXXXXX --platform IOS
```

## Aktualisieren

```bash
# Interaktive Auswahl und Aktualisierungseingaben
asc devices update

# Ein Gerät umbenennen
asc devices update "My iPhone" --name "Work iPhone"

# Ein Gerät deaktivieren
asc devices update "My iPhone" --status DISABLED
```
