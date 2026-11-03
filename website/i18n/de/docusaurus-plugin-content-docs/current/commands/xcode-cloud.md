---
sidebar_position: 21
title: Xcode Cloud
---

# Xcode Cloud

Verfolgen und starten Sie Xcode-Cloud-Builds: Ihre Produkte, deren Workflows und jeden Build-Lauf mit seinen Aktionen, Problemen, Testergebnissen und Artefakten.

Ein **Produkt** entsteht in Xcode, wenn Sie zum ersten Mal ein Repository verbinden (**Integrate > Create Workflow**); über die API lässt sich keines anlegen. Danach funktioniert alles auf dieser Seite über die Befehlszeile. Ein Produkt wird über die **Bundle-ID** seiner App (oder einen Alias), seinen Namen oder seine ID angegeben, ein Workflow über seinen **Namen** oder seine ID und ein Build-Lauf über seine **Nummer** oder ID.

## Produkte

```bash
ascelerate xcode-cloud products
```

Listet die Produkte des Teams (Apps und Frameworks) mit ihrer Bundle-ID und ihrem Repository auf.

## Workflows

```bash
ascelerate xcode-cloud workflows <bundle-id>
ascelerate xcode-cloud workflows info <bundle-id> "Release"
ascelerate xcode-cloud workflows update <bundle-id> "Default" --manual-only
ascelerate xcode-cloud workflows update <bundle-id> "Release" --branch-changes "main,release/*" --xcode "Xcode 27.2" --clean false
ascelerate xcode-cloud workflows create <bundle-id> --like "Default" --name "TestFlight" --action archive:MyApp:ios --manual-branches main
ascelerate xcode-cloud workflows disable <bundle-id> "Nightly"
ascelerate xcode-cloud workflows enable <bundle-id> "Nightly"
ascelerate xcode-cloud workflows delete <bundle-id> "Old workflow"
```

`info` zeigt die Startbedingungen eines Workflows (Änderungen an Branches und Tags, Pull Requests, Zeitpläne und was von Hand gestartet werden darf), seine Aktionen (Build, Test, Analyse, Archivierung mit Scheme, Plattform und Distribution) sowie das Repository, das Projekt und die Xcode- und macOS-Versionen, die er verwendet. `update --manual-only` sorgt dafür, dass ein Workflow nicht mehr von selbst startet (Änderungen an Branches und Tags, Pull Requests, Zeitplan); was von Hand gestartet werden darf, bleibt. `update` ändert außerdem Name, Beschreibung, saubere Builds, „Restrict Editing“, die Xcode- und macOS-Version und jede Startbedingung: `--branch-changes`, `--tag-changes`, `--pull-requests` (mit `--pull-request-source`), `--manual-branches`, `--manual-tags` und `--manual-pull-requests` nehmen Namen (`release/*` für Namen, die damit beginnen), `any` oder `off`; dazu kommen `--auto-cancel` und `--remove-schedule`. Vor dem Speichern listet es die Änderungen auf und fragt nach. `--action TYP:SCHEMA[:PLATTFORM]` (mehrfach) ersetzt die Aktionen, `--distribution internal|app-store|none` legt die Verteilung eines Archivs fest. `create` legt einen Workflow als Kopie eines anderen an (`--like`, unnötig, wenn das Produkt nur einen hat) und nimmt dieselben Optionen. Umgebungsvariablen und Post-Actions gibt es in der API nicht; fügen Sie sie (etwa TestFlight-Gruppen) in App Store Connect hinzu. Ein deaktivierter Workflow startet keine Builds. Wenn Sie einen Workflow löschen, bleiben seine Build-Läufe erhalten.

## Build-Läufe

```bash
ascelerate xcode-cloud runs <bundle-id>                         # neueste zuerst
ascelerate xcode-cloud runs <bundle-id> --workflow "Release" --limit 50
ascelerate xcode-cloud runs info <bundle-id> 42                 # Details und Aktionen
ascelerate xcode-cloud runs issues <bundle-id> 42 [--errors]
ascelerate xcode-cloud runs tests <bundle-id> 42 [--failed]
ascelerate xcode-cloud runs logs <bundle-id> 42 [--action "Build - iOS"] [--show ci_post_clone.log]
ascelerate xcode-cloud runs artifacts <bundle-id> 42
ascelerate xcode-cloud runs artifacts <bundle-id> 42 --type LOG_BUNDLE --download ./logs
```

Jeder Lauf zeigt seinen Status, den gebauten Branch, Tag oder Pull Request, den Commit und die Dauer; `runs info` ergänzt seine Aktionen mit der Anzahl ihrer Fehler, Warnungen und fehlgeschlagenen Tests (Apple liefert keine Zahlen, daher werden sie aus den Problemen jeder Aktion gezählt). `issues` listet die Fehler und Warnungen jeder Aktion mit Datei und Zeile auf; `tests` listet die Testergebnisse pro Ziel (Gerät und Betriebssystem) auf, mit der Fehlermeldung jedes fehlgeschlagenen Tests. `logs` liest das Log-Paket jeder Aktion: die Logs des Post-Clone-Skripts, der Paketauflösung und von xcodebuild, aufgelistet mit ihrer Zeilenzahl oder mit `--show` ausgegeben. `artifacts` listet Logs, Archive, Result Bundles und Produkte auf; `--download` speichert sie (`--type` grenzt die Auswahl ein).

## Einen Build starten

```bash
ascelerate xcode-cloud start <bundle-id> "Release" --branch main
ascelerate xcode-cloud start <bundle-id> "Release" --tag v2.1
ascelerate xcode-cloud start <bundle-id> "PR checks" --pull-request 128
ascelerate xcode-cloud rerun <bundle-id> 42 [--clean]
```

`start` baut den Branch, den Tag oder den Pull Request, den Sie angeben; ohne Angabe baut Xcode Cloud das, was die Startbedingung des Workflows für einen manuellen Start zulässt. `rerun` baut den Commit eines früheren Laufs mit dessen Workflow erneut. `--clean` baut ohne Cache. Über die API lässt sich ein Build nicht abbrechen.

## Repositorys und Xcode-Versionen

```bash
ascelerate xcode-cloud repositories
ascelerate xcode-cloud xcode-versions
```

`xcode-versions` listet die Xcode-Versionen auf, die Xcode Cloud anbietet, jeweils mit den macOS-Versionen, auf denen sie laufen.

Alle Listen- und Info-Befehle akzeptieren `--json`.
