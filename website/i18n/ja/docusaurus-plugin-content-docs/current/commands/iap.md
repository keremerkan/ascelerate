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
ascelerate iap pricing set <bundle-id> <product-id> --price 4.99 --base-region GBR
```

`--base-region` のデフォルトは既存のベース地域（新規スケジュールの場合はUSA）です。スケジュールに地域別手動価格が含まれている場合、`set` はそれらをいずれも新しいベース地域からの自動均等化に戻すかどうかを尋ねるインタラクティブなメニューを表示します。確認なしですべての手動価格を削除するには、`--remove-all-overrides` を指定してください。

### 地域別の手動価格

```bash
# 手動価格を追加または更新
ascelerate iap pricing override <bundle-id> <product-id> --price 5.99 --territory FRA

# 手動価格を削除（地域はベース地域からの自動均等化に戻ります）
ascelerate iap pricing remove <bundle-id> <product-id> --territory FRA
```

`override` および `remove` はベース以外の地域でのみ動作します。ベース地域の価格を変更するには `set` を使用してください。

アプリ内課金に価格スケジュールがない場合、`iap info` および `iap pricing show` の両方で警告が表示されます。同じ状態は `apps review preflight` でも提出を妨げる問題として表示されます。
