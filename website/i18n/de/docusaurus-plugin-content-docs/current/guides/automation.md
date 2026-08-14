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

## JSON-Ausgabe {#json-output}

Lesebefehle unterstützen `--json` für maschinenlesbare Ausgabe, die sich direkt mit `jq`, in Skripten und von KI-Agenten weiterverarbeiten lässt:

```bash
ascelerate apps list --json
ascelerate apps info <bundle-id> --json
ascelerate apps versions <bundle-id> --json
ascelerate apps review preflight <bundle-id> --json
ascelerate apps review status <bundle-id> --json
ascelerate builds list --bundle-id <bundle-id> --json
ascelerate testflight builds <bundle-id> --json
ascelerate testflight status <bundle-id> --json
ascelerate reviews list <bundle-id> --json
ascelerate reviews info <review-id> --json
ascelerate iap list <bundle-id> --json
ascelerate iap info <bundle-id> <product-id> --json
ascelerate iap pricing show <bundle-id> <product-id> --json
ascelerate sub groups <bundle-id> --json
ascelerate sub list <bundle-id> --json
ascelerate sub info <bundle-id> <product-id> --json
ascelerate sub pricing show <bundle-id> <product-id> --json
ascelerate rate-limit --json
```

Ausgabekonventionen:

- Listenbefehle geben auf oberster Ebene ein JSON-**Array** aus; Detailbefehle ein einzelnes **Objekt**.
- Enum-Werte sind rohe API-Konstanten (`WAITING_FOR_REVIEW`, `IOS`), Datumsangaben sind ISO 8601, und jede Ressource enthält ihre `id`.
- Null-Felder werden weggelassen; leere Ergebnisse ergeben `[]` — niemals Fließtext.
- Warnungen werden zu booleschen Werten: `iap info` und `sub info` geben `"hasPricing": false` statt einer Warnmeldung aus.
- `--json` impliziert den nicht-interaktiven Modus: Befehle, die sonst nachfragen würden (etwa um zwischen Plattformen zu unterscheiden), brechen stattdessen mit einem Fehler ab — übergeben Sie `--platform` oder andere Flags, um Eindeutigkeit herzustellen.
- Fehler gehen an stderr, sodass stdout immer gültiges JSON ist.

Beispiel — unbeantwortete Rezensionen zählen:

```bash
ascelerate reviews list <bundle-id> --json | jq '[.[] | select(.response == null)] | length'
```

## Exit-Codes

Befehle beenden sich bei Fehlern mit einem Exit-Code ungleich Null, sodass sie sicher in Skripten mit `set -e` oder `&&`-Verkettung verwendet werden können. Der `preflight`-Befehl gibt speziell einen Exit-Code ungleich Null zurück, wenn eine Prüfung fehlschlägt, sodass Sie Einreichungen davon abhängig machen können:

```bash
ascelerate apps review preflight <bundle-id> && ascelerate apps review submit <bundle-id>
```

Mit `--json` gibt `preflight` einen strukturierten Bericht aus (`{"passed": false, "checks": [{"group", "name", "passed", "detail"}]}`) und behält dabei das gleiche Exit-Code-Verhalten bei — ideal für CI-Gates, die melden müssen, *welche* Prüfung fehlgeschlagen ist.
