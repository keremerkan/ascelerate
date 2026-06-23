---
sidebar_position: 16
title: レポート
---

# レポート

売上とトレンド、財務、App Analyticsのレポートをダウンロードします。売上レポートと財務レポートはAppleのgzip圧縮されたTSVとして返されます — `ascelerate` はこれらを展開して概要を表示します（または生ファイルを保存します）。App Analyticsは、Appleの非同期レポートリクエストフローを通じて取得されます。

:::note ベンダー番号
`reports sales` と `reports finance` には**ベンダー番号**が必要です（App Store Connect → お支払いと財務レポート、例：`80012345`）。`ascelerate configure` で一度保存するか、コマンドごとに `--vendor-number` で渡してください。`reports analytics` には不要です。
:::

## Sales

ユニット数（ダウンロード）、収益、App内課金／サブスクリプションのアクティビティ。デフォルトでは、アプリと製品タイプごとにグループ化された解析済みの概要を表示します。TSVを出力するには `--raw`、保存するには `--output` を追加します。

```bash
ascelerate reports sales
ascelerate reports sales --frequency WEEKLY
ascelerate reports sales --frequency MONTHLY --date 2026-05
ascelerate reports sales --frequency YEARLY --date 2025 --bundle-id com.example.App
ascelerate reports sales --frequency DAILY --date 2026-06-20 --output sales.tsv
```

- `--frequency` — `DAILY`、`WEEKLY`、`MONTHLY`、`YEARLY`（デフォルト `DAILY`）。
- `--date` — 日次／週次は `YYYY-MM-DD`（週次は週の最終日である日曜日）、月次は `YYYY-MM`、年次は `YYYY`。デフォルトは直近の完了済み期間です。
- `--type` — レポートタイプ（デフォルト `SALES`）。その他に `SUBSCRIPTION`、`SUBSCRIBER`、`SUBSCRIPTION_EVENT`、`INSTALLS`、`PRE_ORDER` などがあります。
- `--sub-type` — `SUMMARY`（デフォルト）、`DETAILED`、`SUMMARY_TERRITORY`、`SUMMARY_CHANNEL`、`SUMMARY_INSTALL_TYPE`。
- `--bundle-id` — 概要を単一のアプリ（またはエイリアス）に絞り込みます。
- `--vendor-number` — 設定済みのベンダー番号を上書きします。
- `--output` / `--raw` — 生のTSVをファイルに保存するか、概要の代わりに出力します。

概要はユニットをタイトルと**製品タイプ識別子**でグループ化します。1つのレポートに初回ダウンロード（`1*`/`3*`）、アップデート（`7*`）、App内課金（`IA*`）が混在するため便利です。完全なデータには `--raw` を使用してください。

## Finance

会計期間ごと、地域ごとのユニット数とパートナー収益。

```bash
ascelerate reports finance --date 2026-05 --region US
ascelerate reports finance --date 2026-05 --region US --type FINANCE_DETAIL --output finance.tsv
```

- `--date` — `YYYY-MM` 形式の会計期間。月はカレンダー上の月ではなく、Appleの**会計期間（01〜12）**です。必須。
- `--region` — 地域コード。例：`US`、`EU`、`GB`、`JP`、`AU`、`WW`（全世界）。必須。
- `--type` — `FINANCIAL`（デフォルト）または `FINANCE_DETAIL`。
- `--vendor-number`、`--output`、`--raw` — 上記と同じ。

概要はタイトルごとに数量を、通貨ごとに収益を集計します。

## Analytics

App Analyticsのレポートデータ — ダウンロード、インプレッション、製品ページの表示回数、セッションなど。Appleはこれらを非同期で生成します。コマンドはアプリのレポートリクエストを検索（または確認のうえ作成）し、レポートのセグメントをダウンロードします。

```bash
ascelerate reports analytics <bundle-id>
ascelerate reports analytics <bundle-id> --category APP_USAGE --granularity WEEKLY
ascelerate reports analytics <bundle-id> --report-name "App Store Discovery and Engagement Detailed" --output ./analytics
```

- `--category` — `APP_STORE_ENGAGEMENT`（デフォルト）、`APP_USAGE`、`COMMERCE`、`FRAMEWORK_USAGE`、`PERFORMANCE`。
- `--granularity` — `DAILY`（デフォルト）、`WEEKLY`、`MONTHLY`。
- `--report-name` — カテゴリに複数のレポートが含まれる場合に、特定のレポートを選択します。
- `--processing-date` — ダウンロードするインスタンス（`YYYY-MM-DD`）。デフォルトは最新。
- `--ongoing` — 1回限りのスナップショットではなく、継続的なレポートリクエストを使用します。
- `--output` — ダウンロードしたセグメントファイルのディレクトリ（デフォルト `./<app>-analytics`）。

新しく作成されたスナップショットはすぐには利用できません — Appleが生成するのに時間がかかります。セグメントをダウンロードするには、数分後にコマンドを再実行してください。

:::info 評価
App Store Connect APIは、集計された評価数や星評価の平均／ヒストグラムを公開していません — 個々のレビューのみです（[カスタマーレビュー](./reviews.md)を参照）。ダウンロード数や収益の数値には、上記のレポートを使用してください。
:::
