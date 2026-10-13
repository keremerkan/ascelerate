---
sidebar_position: 21
title: Apple Ads
---

# Apple Ads

Manage Apple Ads (formerly Search Ads) campaigns from the command line through the Apple Ads Platform API: performance reports, campaigns, ad groups, keywords and negative keywords, bids and budgets, Apple's recommendations, and its keyword research data. Apps are matched with App Store Connect, so `--app` takes the same bundle IDs and [aliases](../getting-started/aliases.md) as every other command. Campaigns and ad groups are referenced by **name** (case-insensitive) or ID; a wrong name lists the valid ones.

Every command that changes something asks for confirmation first (`-y` skips it), and `--dry-run` prints the exact requests without sending them ([dry run](../guides/automation.md#dry-run)). Changes spend real money, so try them with `--dry-run` first. Amounts are in the ad account's currency.

## Setup

Apple Ads uses its own credentials, separate from your App Store Connect API key:

1. In Apple Ads, go to **Account Settings → User Management**, invite a user with an **API** role (for example API Account Manager), and accept the invitation with that user's Apple Account.
2. Run the setup:

```bash
ascelerate ads configure
```

ascelerate creates the key pair and prints the public key. Sign in to Apple Ads as the API user, paste the key in **Account Settings → API**, and enter the client ID, team ID, and key ID shown there. ascelerate then lists the ad accounts the user can access and stores the one you pick in an `ads` section of `~/.ascelerate/config.json`. `--new-key` creates a new key pair.

```bash
ascelerate ads accounts          # ad accounts and roles of the API user
```

## Reports

```bash
ascelerate ads reports campaigns --days 30
ascelerate ads reports campaigns --from 2026-09-01 --to 2026-09-30 --app myapp
ascelerate ads reports campaigns --campaign "MyApp US" --by device
ascelerate ads reports adgroups --campaign "MyApp US"
ascelerate ads reports ads --campaign "MyApp US"
ascelerate ads reports keywords --campaign "MyApp US"
ascelerate ads reports search-terms --app myapp --days 14
```

| Report | Rows |
|---|---|
| `campaigns` | Campaigns; `--by age gender device country region city` breaks them down |
| `adgroups` | Ad groups (for example to compare test groups) |
| `ads` | Ads, that is the product page each ad group sends taps to |
| `keywords` | Keywords, with Apple's suggested bid |
| `search-terms` | What people actually searched, the keyword that matched, and whether it came from your keywords or Search Match |

All reports take `--days N` (including today) or `--from`/`--to`, `--app`, `--campaign`, `--all` (include rows without activity), and `--json`. Dates are in the ad account's time zone. For decisions, compare complete days: today's numbers are still coming in.

Each row shows spend, impressions, taps, installs, tap-through rate (TTR), average cost per tap (CPT) and per install (CPI), and two conversion rates:

- **CR (Tap)**: installs after a tap, divided by taps. How well your product page converts people who tapped.
- **CR (Total)**: all installs, including view-through installs (people who saw the ad and installed later without tapping), divided by taps. It can exceed 100%.

:::note
Apple knows age, gender, and location below country only for users who allowed Personalized Ads, so those breakdowns come back almost entirely as "Unknown". Device breakdowns are complete. Search terms Apple withholds for privacy show as "(low volume)".
:::

## Campaigns

```bash
ascelerate ads campaigns list --app myapp
ascelerate ads campaigns pause "MyApp US"
ascelerate ads campaigns resume "MyApp US"
ascelerate ads campaigns budget "MyApp US" --daily 120
ascelerate ads campaigns bid "MyApp US Max Conv" --amount 2.50
```

`list` shows each campaign's status, countries, daily budget, and bidding (Manual CPT or Max Conversions). For a Max Conversions campaign, `bid` sets the most it may pay in a single auction: set it from what an install is worth to you, since a ceiling below the storefront's usual cost per tap starves the campaign.

### Create a campaign

```bash
ascelerate ads campaigns create --like "MyApp US" --name "MyApp US Max Conv" --max-conversions --bid 2.50 --daily 25
ascelerate ads campaigns create --app myapp --name "MyApp DE" --country DE --daily 20 --default-bid 1.00 --search-match off
```

The campaign is created **paused**, together with its ad group: an automated one for Max Conversions, or a manual one with `--default-bid`. `--like` copies an existing campaign's app, countries, and settings. `--enabled` starts it right away.

```bash
ascelerate ads campaigns target-cpa --app myapp --country US
```

Shows Apple's suggested target cost per install for a new Max Conversions campaign.

:::tip
An app's campaigns in the same storefront don't compete with each other: Apple lets only one of them into each auction. A new campaign next to a running one therefore gets only leftover traffic. To test a new campaign, move the traffic to it, for example by limiting the old one to your brand name.
:::

## Ad groups

```bash
ascelerate ads adgroups --campaign "MyApp US"
ascelerate ads adgroups create --campaign "MyApp US" --name "Exact" --search-match off
ascelerate ads adgroups create --campaign "MyApp US" --name "Adults" --like "US Ad Group" --min-age 25
ascelerate ads adgroups update "Exact" --campaign "MyApp US" --default-bid 1.20
ascelerate ads adgroups pause "Exact" --campaign "MyApp US"
ascelerate ads adgroups resume "Exact" --campaign "MyApp US"
```

`create` copies an existing ad group's pricing, bidding, and targeting (`--like`, or the campaign's only group) and is created **paused** unless `--enabled`. `--min-age`/`--max-age` target ages 18 to 64 (no `--max-age` means 65 and older). Age targeting reaches only users who allowed Personalized Ads, and Apple doesn't attribute installs from age-targeted ad groups to the campaign in other tools, so judge such groups on their Apple Ads numbers.

## Keywords & negative keywords

```bash
ascelerate ads keywords list --campaign "MyApp US"
ascelerate ads keywords add --campaign "MyApp US" --match exact --bid 1.50 "qr scanner" "barcode reader"
ascelerate ads keywords bid --campaign "MyApp US" --bid 1.25 "qr scanner"
ascelerate ads keywords pause --campaign "MyApp US" "barcode reader"
ascelerate ads keywords copy --campaign "MyApp US" --from "US Ad Group" --to "Exact"

ascelerate ads negatives list --campaign "MyApp US"
ascelerate ads negatives add --campaign "MyApp US" "free wifi"
ascelerate ads negatives add --campaign "MyApp US" --ad-group "Discovery" --match broad "wifi"
ascelerate ads negatives remove --campaign "MyApp US" "free wifi"
```

`--ad-group` picks the ad group when a campaign has several. Negative keywords are campaign-level unless `--ad-group` is given, and exact match unless `--match broad`. `keywords add` skips keywords that already exist. Max Conversions campaigns choose their own bids, so keyword bids don't apply to them.

## What to change

```bash
ascelerate ads opportunities --app myapp
ascelerate ads opportunities --campaign "MyApp US" --days 60 --min-taps 20 --brand "my app"
```

`opportunities` compares a campaign's search terms (last 30 complete days by default) with its keywords and its own averages, and suggests:

- **Add as exact keyword**: a converting search term without an exact keyword of its own, at a good cost per install.
- **Give its own bid**: a converting term that rides on another keyword's bid at a higher cost.
- **Exclude**: a term with real spend and no installs, or a much worse cost or conversion rate.

Searches for your app's name are left out of the averages and never suggested as negatives; add other spellings of your brand with `--brand`. Treat the results as candidates and check that each term is relevant to your app before acting.

```bash
ascelerate ads recommendations
ascelerate ads recommendations apply <id>
ascelerate ads recommendations dismiss <id>
```

Apple's open recommendations (daily budget and target CPA changes) with their expected outcome.

```bash
ascelerate ads history --app myapp --days 7
```

Every change to campaigns, ad groups, keywords, and negative keywords in the last six months, including ones made in the Apple Ads website or by Apple, with old and new values. Useful before reading a change in performance.

## Keyword research

```bash
ascelerate ads keywords suggest --app myapp --seed "qr code" "barcode" --country US GB
ascelerate ads keywords popularity --app myapp --country US --term "qr code" "qr scanner"
ascelerate ads keywords popularity --genre PRODUCTIVITY_UTILITIES --country US --contains scanner
ascelerate ads insights impression-share --app myapp --country US --weeks 4
```

- `suggest` returns Apple's keyword suggestions for your seed terms, with their popularity and where you already target them.
- `popularity` shows how popular search terms are in a storefront (1 to 100) and in the app's genre. Terms outside the genre's ranked list are listed separately.
- `impression-share` shows your share of ad impressions and your rank for the search terms your ads appeared on: a low share on a popular, converting term is room to grow, and a share below 100% on your own brand name means competitors bid on it.

The popularity data is useful for App Store keyword (ASO) choices too.

## Ads & custom product pages

```bash
ascelerate ads product-pages --app myapp
ascelerate ads ads --campaign "MyApp US"
ascelerate ads ads create --campaign "MyApp US" --ad-group "Scanner" --product-page "Scanner Page" --enabled
ascelerate ads ads pause "Scanner Page ad" --campaign "MyApp US"
```

An ad sends an ad group's taps to a product page. Ad groups without an ad of yours use the default product page. To send searches for a specific need to a [custom product page](product-pages.md), give them an ad group of their own (`adgroups create`, `keywords add`) and create an ad for it. Only one ad serves per ad group, so `--enabled` pauses the one serving before. Apple reviews new ads; `ads ads` shows their review state.

## Using it with an AI agent

The [ascelerate skill](../guides/ai-skill.md) teaches AI coding agents how to read these reports and when to suggest changes, so you can ask an agent to review your campaigns across apps, find keywords to add or exclude, or explain a change in performance. Every command takes `--json`, and agents are told to show you the proposed changes and use `--dry-run` before anything is sent.
