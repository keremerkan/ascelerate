---
sidebar_position: 2
title: Automatisierung & CI/CD
---

# Automatisierung & CI/CD

Die meisten Befehle, die eine Bestätigung verlangen, unterstützen `--yes` / `-y` zum Überspringen von Abfragen, wodurch sie für CI/CD-Pipelines und Skripte geeignet sind.

```bash
ascelerate apps build attach-latest <bundle-id> --yes
ascelerate apps review submit <bundle-id> --yes
```

:::warning
Bei Verwendung von `--yes` mit Provisioning-Befehlen müssen alle erforderlichen Argumente explizit angegeben werden — der interaktive Modus ist deaktiviert.
:::

## Xcode-Signierung in CI

Sowohl `builds archive` als auch der Export von Archiv zu IPA übergeben `-allowProvisioningUpdates` an `xcodebuild`. Ohne dieses Flag verwendet `xcodebuild` nur lokal zwischengespeicherte Provisioning-Profile und lädt keine aktualisierten Profile aus dem Developer Portal herunter.

Für CI-Umgebungen ohne Xcode-GUI-Anmeldung übergeben Sie Authentifizierungs-Flags:

```bash
ascelerate builds archive \
  --authentication-key-path /path/to/AuthKey.p8 \
  --authentication-key-id YOUR_KEY_ID \
  --authentication-key-issuer-id YOUR_ISSUER_ID
```

## Exit-Codes

Befehle beenden sich bei Fehlern mit einem Exit-Code ungleich Null, sodass sie sicher in Skripten mit `set -e` oder `&&`-Verkettung verwendet werden können. Der `preflight`-Befehl gibt speziell einen Exit-Code ungleich Null zurück, wenn eine Prüfung fehlschlägt, sodass Sie Einreichungen davon abhängig machen können:

```bash
ascelerate apps review preflight <bundle-id> && asc apps review submit <bundle-id>
```
