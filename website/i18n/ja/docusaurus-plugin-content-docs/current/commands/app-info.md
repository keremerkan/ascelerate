---
sidebar_position: 5
title: アプリ情報とカテゴリ
---

# アプリ情報とカテゴリ

## 表示

```bash
# アプリ情報、カテゴリ、ロケールごとのメタデータを表示
ascelerate apps app-info view <bundle-id>

# 利用可能なすべてのカテゴリIDを一覧表示（bundle ID不要）
ascelerate apps app-info view --list-categories
```

## 更新

```bash
# 単一ロケールのローカライゼーションフィールドを更新
ascelerate apps app-info update <bundle-id> --name "My App" --subtitle "Best app ever"
ascelerate apps app-info update <bundle-id> --locale de-DE --name "Meine App"

# カテゴリを更新（ローカライゼーションフラグと組み合わせ可能）
ascelerate apps app-info update <bundle-id> --primary-category UTILITIES
ascelerate apps app-info update <bundle-id> --primary-category GAMES_ACTION --secondary-category ENTERTAINMENT
```

## エクスポート

```bash
ascelerate apps app-info export <bundle-id>
ascelerate apps app-info export <bundle-id> --output app-infos.json
```

## インポート

```bash
ascelerate apps app-info import <bundle-id> --file app-infos.json
```

## JSONフォーマット

```json
{
  "en-US": {
    "name": "My App",
    "subtitle": "Best app ever",
    "privacyPolicyURL": "https://example.com/privacy",
    "privacyChoicesURL": "https://example.com/choices"
  }
}
```

JSONに含まれるフィールドのみが更新されます。省略されたフィールドは変更されません。

:::note
`app-info update` および `app-info import` コマンドは、AppInfoが編集可能な状態（`PREPARE_FOR_SUBMISSION` または `WAITING_FOR_REVIEW`）である必要があります。
:::

## 年齢制限

```bash
# 最新バージョンの年齢制限宣言を表示
ascelerate apps app-info age-rating <bundle-id>
ascelerate apps app-info age-rating <bundle-id> --version 2.1.0

# JSONファイルから年齢制限を更新
ascelerate apps app-info age-rating <bundle-id> --file age-rating.json
```

JSONファイルはAPIと同じフィールド名を使用します。ファイルに含まれるフィールドのみが更新されます：

```json
{
  "isAdvertising": false,
  "isUserGeneratedContent": true,
  "violenceCartoonOrFantasy": "INFREQUENT_OR_MILD",
  "alcoholTobaccoOrDrugUseOrReferences": "NONE"
}
```

強度フィールドは `NONE`、`INFREQUENT_OR_MILD`、`FREQUENT_OR_INTENSE` を受け付けます。ブールフィールドは `true`/`false` を受け付けます。

## ルーティングアプリカバレッジ

```bash
# 現在のルーティングカバレッジステータスを表示
ascelerate apps routing-coverage <bundle-id>

# .geojsonファイルをアップロード
ascelerate apps routing-coverage <bundle-id> --file coverage.geojson
```
