---
sidebar_position: 2
title: Einrichtung
---

# Einrichtung

## 1. API-Schlüssel erstellen

Gehen Sie zu [App Store Connect > Benutzer und Zugriff > Integrationen > App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api) und generieren Sie einen neuen Schlüssel. Laden Sie die `.p8`-Datei mit dem privaten Schlüssel herunter.

## 2. Konfigurieren

```bash
ascelerate configure
```

Dies fragt nach Ihrer **Key ID**, **Issuer ID** und dem Pfad zu Ihrer `.p8`-Datei. Der private Schlüssel wird mit strengen Dateiberechtigungen (nur Eigentümerzugriff) nach `~/.ascelerate/` kopiert.

Die Konfiguration wird unter `~/.ascelerate/config.json` gespeichert:

```json
{
    "keyId": "KEY_ID",
    "issuerId": "ISSUER_ID",
    "privateKeyPath": "/Users/.../.ascelerate/AuthKey_XXXXXXXXXX.p8"
}
```

## 3. Überprüfen

Führen Sie einen kurzen Befehl aus, um zu überprüfen, ob alles funktioniert:

```bash
ascelerate apps list
```

Wenn Ihre Zugangsdaten korrekt sind, sehen Sie eine Liste aller Ihrer Apps.

## Rate Limit

Die App Store Connect API hat ein rollierendes stündliches Limit von 3600 Anfragen. Sie können Ihren aktuellen Verbrauch jederzeit prüfen:

```bash
ascelerate rate-limit
```

```
Hourly limit: 3600 requests (rolling window)
Used:         57
Remaining:    3543 (98%)
```
