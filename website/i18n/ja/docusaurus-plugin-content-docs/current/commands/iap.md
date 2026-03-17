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
