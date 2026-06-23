---
sidebar_position: 16
title: Berichte
---

# Berichte

Laden Sie Sales-&-Trends-, Finanz- und App-Analytics-Berichte herunter. Sales- und Finanzberichte kommen als gzip-komprimiertes TSV von Apple — `ascelerate` entpackt sie und gibt eine Zusammenfassung aus (oder speichert die Rohdatei). App Analytics wird über Apples asynchronen Berichtsanfrage-Ablauf abgerufen.

:::note Vendor-Nummer
`reports sales` und `reports finance` benötigen Ihre **Vendor-Nummer** (App Store Connect → Zahlungen und Finanzberichte, z. B. `80012345`). Speichern Sie sie einmalig mit `ascelerate configure` oder übergeben Sie sie pro Befehl mit `--vendor-number`. `reports analytics` benötigt sie nicht.
:::

## Sales

Einheiten (Downloads), Erlöse und IAP-/Abo-Aktivität. Standardmäßig wird eine aufbereitete Zusammenfassung nach App und Produkttyp gruppiert ausgegeben; fügen Sie `--raw` hinzu, um das TSV auszugeben, oder `--output`, um es zu speichern.

```bash
ascelerate reports sales
ascelerate reports sales --frequency WEEKLY
ascelerate reports sales --frequency MONTHLY --date 2026-05
ascelerate reports sales --frequency YEARLY --date 2025 --bundle-id com.example.App
ascelerate reports sales --frequency DAILY --date 2026-06-20 --output sales.tsv
```

- `--frequency` — `DAILY`, `WEEKLY`, `MONTHLY` oder `YEARLY` (Standard `DAILY`).
- `--date` — `YYYY-MM-DD` für täglich/wöchentlich (wöchentlich = der Sonntag, der die Woche abschließt), `YYYY-MM` für monatlich, `YYYY` für jährlich. Standard ist der zuletzt abgeschlossene Zeitraum.
- `--type` — Berichtstyp (Standard `SALES`); weitere sind `SUBSCRIPTION`, `SUBSCRIBER`, `SUBSCRIPTION_EVENT`, `INSTALLS`, `PRE_ORDER`.
- `--sub-type` — `SUMMARY` (Standard), `DETAILED`, `SUMMARY_TERRITORY`, `SUMMARY_CHANNEL`, `SUMMARY_INSTALL_TYPE`.
- `--bundle-id` — beschränkt die Zusammenfassung auf eine einzelne App (oder einen Alias).
- `--vendor-number` — überschreibt die konfigurierte Vendor-Nummer.
- `--output` / `--raw` — speichert das rohe TSV in einer Datei oder gibt es statt einer Zusammenfassung aus.

Die Zusammenfassung gruppiert Einheiten nach Titel und **Produkttyp-Kennung** — nützlich, weil ein einzelner Bericht Erstdownloads (`1*`/`3*`), Updates (`7*`) und In-App-Käufe (`IA*`) mischt. Verwenden Sie `--raw` für die vollständigen Daten.

## Finance

Einheiten und Partnererlöse für einen Geschäftszeitraum, nach Region.

```bash
ascelerate reports finance --date 2026-05 --region US
ascelerate reports finance --date 2026-05 --region US --type FINANCE_DETAIL --output finance.tsv
```

- `--date` — Geschäftszeitraum als `YYYY-MM`, wobei der Monat Apples **Geschäftsperiode (01–12)** ist, nicht ein Kalendermonat. Erforderlich.
- `--region` — Regionscode, z. B. `US`, `EU`, `GB`, `JP`, `AU`, `WW` (weltweit). Erforderlich.
- `--type` — `FINANCIAL` (Standard) oder `FINANCE_DETAIL`.
- `--vendor-number`, `--output`, `--raw` — wie oben.

Die Zusammenfassung summiert die Menge nach Titel und die Erlöse nach Währung.

## Analytics

App-Analytics-Berichtsdaten — Downloads, Impressions, Produktseitenaufrufe, Sitzungen und mehr. Apple erstellt diese asynchron: Der Befehl findet (oder erstellt nach Bestätigung) eine Berichtsanfrage für die App und lädt dann die Segmente des Berichts herunter.

```bash
ascelerate reports analytics <bundle-id>
ascelerate reports analytics <bundle-id> --category APP_USAGE --granularity WEEKLY
ascelerate reports analytics <bundle-id> --report-name "App Store Discovery and Engagement Detailed" --output ./analytics
```

- `--category` — `APP_STORE_ENGAGEMENT` (Standard), `APP_USAGE`, `COMMERCE`, `FRAMEWORK_USAGE`, `PERFORMANCE`.
- `--granularity` — `DAILY` (Standard), `WEEKLY`, `MONTHLY`.
- `--report-name` — wählt einen bestimmten Bericht, wenn eine Kategorie mehrere enthält.
- `--processing-date` — die herunterzuladende Instanz (`YYYY-MM-DD`); standardmäßig die neueste.
- `--ongoing` — verwendet eine fortlaufende Berichtsanfrage statt einer einmaligen Momentaufnahme.
- `--output` — Verzeichnis für die heruntergeladenen Segmentdateien (Standard `./<app>-analytics`).

Eine frisch erstellte Momentaufnahme ist nicht sofort verfügbar — Apple braucht Zeit, um sie zu erstellen. Führen Sie den Befehl nach ein paar Minuten erneut aus, um die Segmente herunterzuladen.

:::info Bewertungen
Die App Store Connect API stellt keine aggregierten Bewertungszahlen oder den Sternebewertungs-Durchschnitt/das Histogramm bereit — nur einzelne Rezensionen (siehe [Kundenrezensionen](./reviews.md)). Für Download- und Umsatzzahlen verwenden Sie die obigen Berichte.
:::
