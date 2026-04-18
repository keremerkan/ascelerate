---
sidebar_position: 6
title: アプリ内課金
---

# アプリ内課金

## 一覧

```bash
ascelerate iap list <bundle-id>
ascelerate iap list <bundle-id> --type consumable --state approved
```

フィルター値は大文字小文字を区別しません。タイプ：`CONSUMABLE`、`NON_CONSUMABLE`、`NON_RENEWING_SUBSCRIPTION`。状態：`APPROVED`、`MISSING_METADATA`、`READY_TO_SUBMIT`、`WAITING_FOR_REVIEW`、`IN_REVIEW` など。

## 詳細

```bash
ascelerate iap info <bundle-id> <product-id>
```

## プロモートされた課金アイテム

```bash
ascelerate iap promoted <bundle-id>
```

## 作成、更新、削除

```bash
ascelerate iap create <bundle-id> --name "100 Coins" --product-id <product-id> --type CONSUMABLE
ascelerate iap update <bundle-id> <product-id> --name "100 Gold Coins"
ascelerate iap delete <bundle-id> <product-id>
```

## 審査への提出

```bash
ascelerate iap submit <bundle-id> <product-id>
```

## ローカライゼーション

```bash
ascelerate iap localizations view <bundle-id> <product-id>
ascelerate iap localizations export <bundle-id> <product-id>
ascelerate iap localizations import <bundle-id> <product-id> --file iap-de.json
```

インポートコマンドは、存在しないロケールを確認のうえ自動的に作成するため、App Store Connectにアクセスせずに新しい言語を追加できます。

## 価格設定

`iap pricing` は価格スケジュールの読み書きを行います。スケジュールには単一のベース地域 — Appleが他のすべての地域の価格を自動均等化するために使用する地域 — と、ゼロ個以上の地域別手動価格が含まれます。

```bash
# 現在の価格スケジュールを表示（未設定の場合は警告）
ascelerate iap pricing show <bundle-id> <product-id>

# ある地域で利用可能な価格層を一覧表示
ascelerate iap pricing tiers <bundle-id> <product-id> --territory USA
```

### ベース地域の価格設定

```bash
ascelerate iap pricing set <bundle-id> <product-id> --price 4.99
ascelerate iap pricing set <bundle-id> <product-id> --price 4.99 --base-territory GBR
```

`--base-territory` のデフォルトは既存のベース地域（新規スケジュールの場合はUSA）です。スケジュールに地域別手動価格が含まれている場合、`set` はそれらをいずれも新しいベース地域からの自動均等化に戻すかどうかを尋ねるインタラクティブなメニューを表示します。確認なしですべての手動価格を削除するには、`--remove-all-overrides` を指定してください。

### 地域別の手動価格

```bash
# 手動価格を追加または更新
ascelerate iap pricing override <bundle-id> <product-id> --price 5.99 --territory FRA

# 手動価格を削除（地域はベース地域からの自動均等化に戻ります）
ascelerate iap pricing remove <bundle-id> <product-id> --territory FRA
```

`override` および `remove` はベース以外の地域でのみ動作します。ベース地域の価格を変更するには `set` を使用してください。

アプリ内課金に価格スケジュールがない場合、`iap info` および `iap pricing show` の両方で警告が表示されます。同じ状態は `apps review preflight` でも提出を妨げる問題として表示されます。

## 地域別の利用可否

各アプリ内課金は、アプリとは独立した独自の地域別利用可否を持ちます。デフォルトではアプリ内課金はアプリの地域を継承しますが、`iap availability` で変更を加えると、アプリ内課金に明示的なリストが作成されます。

```bash
# 現在のアプリ内課金固有の地域を表示
ascelerate iap availability <bundle-id> <product-id>

# 地域リストを編集（POSTはリスト全体を置き換えます）
ascelerate iap availability <bundle-id> <product-id> --add CHN,RUS
ascelerate iap availability <bundle-id> <product-id> --remove ITA
ascelerate iap availability <bundle-id> <product-id> --available-in-new-territories true
```

## オファーコード

オファーコードは、アプリ内課金で一度限りの割引を利用できる引換コードです。同じオファーコードリソースの下で2種類のバリエーションがあります：

- **ワンタイムユースコード**：Appleが非同期でN個の一意のコードをバッチで生成します。各コードは一度しか使用できません。
- **カスタムコード**：開発者が指定する文字列（例：`PROMO2026`）。N回まで使用可能です。

```bash
# アプリ内課金のすべてのオファーコードを一覧表示
ascelerate iap offer-code list <bundle-id> <product-id>

# オファーコードの詳細とコードバッチ数を表示
ascelerate iap offer-code info <bundle-id> <product-id> <offer-code-id>

# 割引価格のオファーコードを作成（全地域に自動均等化）
ascelerate iap offer-code create <bundle-id> <product-id> \
  --name "Launch Promo" \
  --eligibility NON_SPENDER,ACTIVE_SPENDER \
  --price 0.99 --territory USA --equalize-all-territories

# アクティブ化または無効化
ascelerate iap offer-code toggle <bundle-id> <product-id> <offer-code-id> --active true

# ワンタイムユースコードのバッチを生成（コードは非同期で生成されます）
ascelerate iap offer-code gen-codes <bundle-id> <product-id> <offer-code-id> \
  --count 100 --expires 2026-12-31

# 生成完了後に実際のコード値を取得
ascelerate iap offer-code view-codes <one-time-use-batch-id> --output codes.txt

# 開発者指定のカスタムコードを追加
ascelerate iap offer-code add-custom-codes <bundle-id> <product-id> <offer-code-id> \
  --code PROMO2026 --count 1000 --expires 2026-12-31
```

アプリ内課金オファーコードの顧客対象：`NON_SPENDER`、`ACTIVE_SPENDER`、`CHURNED_SPENDER`。

## プロモーション画像

App Storeでアプリ内課金と並んで表示されるプロモーション画像をアップロードします。

```bash
ascelerate iap images list <bundle-id> <product-id>
ascelerate iap images upload <bundle-id> <product-id> ./hero.png
ascelerate iap images delete <bundle-id> <product-id> <image-id>
```

アップロードはAppleの3ステップフローを使用します：`fileSize` と `fileName` で予約し、ファイルチャンクを署名付きURLにPUT送信し、ファイルのMD5でPATCHしてコミットします。CLIは単一の `upload` 呼び出しで3つのステップすべてを処理します。

## App Reviewスクリーンショット

各アプリ内課金は最大1つのApp Reviewスクリーンショット（Appleの審査担当者に表示）を持つことができます。アップロードすると既存のスクリーンショットが置き換えられます。

```bash
ascelerate iap review-screenshot view <bundle-id> <product-id>
ascelerate iap review-screenshot upload <bundle-id> <product-id> ./review.png
ascelerate iap review-screenshot delete <bundle-id> <product-id>
```
