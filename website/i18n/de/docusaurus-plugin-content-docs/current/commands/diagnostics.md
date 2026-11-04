---
sidebar_position: 16
title: Diagnose
---

# Diagnose

Was der Organizer von Xcode zeigt, von den Geräten der Nutzer, die Analysedaten mit Entwicklern teilen: die häufigsten Hänger, langsamen Starts und Schreibvorgänge eines Builds mit ihren Aufrufstapeln sowie die Leistungs- und Energiemetriken der App über ihre Versionen. Ohne `--build` der Build der Version im App Store.

## Signaturen

```bash
ascelerate diagnostics <bundle-id>
ascelerate diagnostics <bundle-id> --type hangs --build 2041
```

Die Signaturen des Builds für Hänger, Starts und Schreibvorgänge, je Typ nach Gewicht sortiert, mit ihrem Trend gegenüber früheren Versionen. `--type` nimmt `hangs`, `launches` oder `disk-writes` (mehrere durch Kommas getrennt).

## Logs

```bash
ascelerate diagnostics logs <signature-id>
ascelerate diagnostics logs <signature-id> --frames 0
```

Jedes erfasste Ereignis mit Gerät, Betriebssystem und App-Version, dann seine Aufrufstapel; der Frame, dem App Store Connect die Schuld gibt, ist mit ▶ markiert. `--frames` begrenzt die Frames pro Aufrufstapel (standardmäßig 40, 0 für alle).

## Metriken

```bash
ascelerate diagnostics metrics <bundle-id>
ascelerate diagnostics metrics <bundle-id> --type launch,hang --all
```

Jede Metrik (Startzeit, Hängerrate, Spitzenspeicher, Schreibvorgänge, Akku, Beendigungen, Animation, Speicherplatz) pro App-Version, für alle Geräte beim typischen (50.) und 90. Perzentil; `--all` ergänzt jedes Gerätemodell. Apples Regressionen und steigende Trends stehen zuerst. `--build` zeigt die Metriken eines Builds.

Alle drei unterstützen `--json`.
