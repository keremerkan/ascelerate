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

`configure` fragt außerdem nach einer optionalen **Vendor-Nummer** (App Store Connect → Zahlungen und Finanzberichte). Sie wird nur für [Sales- und Finanzberichte](../commands/reports.md) benötigt und als Feld `vendorNumber` gespeichert; Sie können sie überspringen und später hinzufügen oder pro Befehl mit `--vendor-number` übergeben.

Für [Apple Ads](../commands/ads.md) benötigt ascelerate eigene Zugangsdaten, die `ascelerate ads configure` einrichtet und in einem Abschnitt `ads` derselben Datei speichert. Ein erneuter Aufruf von `configure` behält sie bei.

### Ein Schlüssel für einen einzelnen Aufruf

Um einen Befehl mit einem anderen Schlüssel auszuführen (für ein anderes Team oder in CI), setzen Sie alle drei Umgebungsvariablen. Sie haben für diesen Aufruf Vorrang vor `config.json`; die Datei bleibt unverändert:

```bash
export ASCELERATE_KEY_ID=KEY_ID
export ASCELERATE_ISSUER_ID=ISSUER_ID
export ASCELERATE_PRIVATE_KEY_PATH=~/keys/AuthKey_KEY_ID.p8
ascelerate apps list
```

`builds archive` und `builds upload` geben diesen Schlüssel auch an `xcodebuild` weiter (`-authenticationKeyPath`, `-authenticationKeyID`, `-authenticationKeyIssuerID`), sodass Profile mit dem Schlüssel statt mit der in Xcode angemeldeten Apple-ID geladen werden. Dafür muss der Schlüssel Zertifikate, IDs und Profile verwalten dürfen. `ascelerate configure --show` zeigt, welchen Schlüssel ein Aufruf verwendet.

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
