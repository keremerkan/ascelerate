---
sidebar_position: 16
title: Reports
---

# Reports

Download Sales & Trends, Financial, and App Analytics reports. Sales and Finance reports come back as Apple's gzipped TSV — `ascelerate` decompresses them and prints a summary (or saves the raw file). App Analytics is fetched through Apple's asynchronous report-request flow.

:::note Vendor number
`reports sales` and `reports finance` need your **vendor number** (App Store Connect → Payments and Financial Reports, e.g. `80012345`). Save it once with `ascelerate configure`, or pass `--vendor-number` per command. `reports analytics` doesn't need it.
:::

## Sales

Units (downloads), proceeds, and IAP/subscription activity. Defaults to a parsed summary grouped by app and product type; add `--raw` to print the TSV or `--output` to save it.

```bash
ascelerate reports sales
ascelerate reports sales --frequency WEEKLY
ascelerate reports sales --frequency MONTHLY --date 2026-05
ascelerate reports sales --frequency YEARLY --date 2025 --bundle-id com.example.App
ascelerate reports sales --frequency DAILY --date 2026-06-20 --output sales.tsv
```

- `--frequency` — `DAILY`, `WEEKLY`, `MONTHLY`, or `YEARLY` (default `DAILY`).
- `--date` — `YYYY-MM-DD` for daily/weekly (weekly = the Sunday ending the week), `YYYY-MM` for monthly, `YYYY` for yearly. Defaults to the most recent completed period.
- `--type` — report type (default `SALES`); others include `SUBSCRIPTION`, `SUBSCRIBER`, `SUBSCRIPTION_EVENT`, `INSTALLS`, `PRE_ORDER`.
- `--sub-type` — `SUMMARY` (default), `DETAILED`, `SUMMARY_TERRITORY`, `SUMMARY_CHANNEL`, `SUMMARY_INSTALL_TYPE`.
- `--bundle-id` — filter the summary to a single app (or alias).
- `--vendor-number` — override the configured vendor number.
- `--output` / `--raw` — save the raw TSV to a file, or print it instead of a summary.

The summary groups units by title and **product type identifier** — useful because a single report mixes first-time downloads (`1*`/`3*`), updates (`7*`), and in-app purchases (`IA*`). Use `--raw` for the full data.

## Finance

Units and partner proceeds for a fiscal period, by region.

```bash
ascelerate reports finance --date 2026-05 --region US
ascelerate reports finance --date 2026-05 --region US --type FINANCE_DETAIL --output finance.tsv
```

- `--date` — fiscal period as `YYYY-MM`, where the month is Apple's **fiscal period (01–12)**, not a calendar month. Required.
- `--region` — region code, e.g. `US`, `EU`, `GB`, `JP`, `AU`, `WW` (worldwide). Required.
- `--type` — `FINANCIAL` (default) or `FINANCE_DETAIL`.
- `--vendor-number`, `--output`, `--raw` — as above.

The summary totals quantity by title and proceeds by currency.

## Analytics

App Analytics report data — downloads, impressions, product page views, sessions, and more. Apple generates these asynchronously: the command finds (or creates, with confirmation) a report request for the app, then downloads the report's segments.

```bash
ascelerate reports analytics <bundle-id>
ascelerate reports analytics <bundle-id> --category APP_USAGE --granularity WEEKLY
ascelerate reports analytics <bundle-id> --report-name "App Store Discovery and Engagement Detailed" --output ./analytics
```

- `--category` — `APP_STORE_ENGAGEMENT` (default), `APP_USAGE`, `COMMERCE`, `FRAMEWORK_USAGE`, `PERFORMANCE`.
- `--granularity` — `DAILY` (default), `WEEKLY`, `MONTHLY`.
- `--report-name` — pick a specific report when a category contains several.
- `--processing-date` — the instance to download (`YYYY-MM-DD`); defaults to the most recent.
- `--ongoing` — use an ongoing report request instead of a one-time snapshot.
- `--output` — directory for the downloaded segment files (default `./<app>-analytics`).

A freshly created snapshot isn't ready immediately — Apple needs time to generate it. Re-run the command after a few minutes to download the segments.

:::info Ratings
The App Store Connect API doesn't expose aggregate rating counts or the star-rating average/histogram — only individual reviews (see [Customer Reviews](./reviews.md)). For download and revenue figures, use the reports above.
:::
