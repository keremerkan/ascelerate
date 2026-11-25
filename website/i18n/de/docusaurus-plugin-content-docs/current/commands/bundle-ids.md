---
sidebar_position: 10
title: Bundle IDs
---

# Bundle IDs

Alle Bundle ID-Befehle unterstützen den interaktiven Modus — Argumente sind optional.

## Auflisten

```bash
ascelerate bundle-ids list
ascelerate bundle-ids list --platform IOS
```

## Details

```bash
# Interaktive Auswahl
ascelerate bundle-ids info

# Nach Bezeichner
ascelerate bundle-ids info com.example.MyApp
```

## Registrieren

```bash
# Interaktive Eingabeaufforderungen
ascelerate bundle-ids register

# Nicht-interaktiv
ascelerate bundle-ids register --name "My App" --identifier com.example.MyApp --platform IOS
```

## Umbenennen

```bash
ascelerate bundle-ids update
ascelerate bundle-ids update com.example.MyApp --name "My Renamed App"
```

Der Bezeichner selbst ist unveränderlich — nur der Name kann geändert werden.

## Löschen

```bash
ascelerate bundle-ids delete
ascelerate bundle-ids delete com.example.MyApp
```

## Fähigkeiten

### Aktivieren

```bash
# Interaktive Auswahl (zeigt nur noch nicht aktivierte Fähigkeiten)
ascelerate bundle-ids enable-capability

# Nicht-interaktiv
ascelerate bundle-ids enable-capability com.example.MyApp --type PUSH_NOTIFICATIONS
```

### Deaktivieren

```bash
# Auswahl aus aktuell aktivierten Fähigkeiten
ascelerate bundle-ids disable-capability
ascelerate bundle-ids disable-capability com.example.MyApp
```

Nach dem Aktivieren oder Deaktivieren einer Fähigkeit bietet der Befehl an, die Bereitstellungsprofile der Bundle-ID neu zu erstellen (nötig, damit die Änderung wirkt). Jedes wird mit seinen eigenen Zertifikaten, die noch bestehen und nicht abgelaufen sind, und seinen eigenen aktivierten, passenden Geräten neu erstellt; ein Profil ohne eines davon wird übersprungen, bevor etwas gelöscht wird. `--yes` beantwortet nur die Änderung der Fähigkeit: Mit `--regenerate-profiles` werden die Profile ohne Rückfrage neu erstellt. Unter `--yes` braucht `disable-capability` die Option `--type`.

:::note
Einige Fähigkeiten (z.B. App Groups, iCloud, Associated Domains) erfordern nach dem Aktivieren zusätzliche Konfiguration im [Apple Developer Portal](https://developer.apple.com/account/resources).
:::
