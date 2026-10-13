---
sidebar_position: 19
title: フィーチャーのノミネーション
---

# フィーチャーのノミネーション

今後のリリース、大型アップデート、新しいコンテンツを Apple のエディトリアルチームに知らせて、App Store でのフィーチャーの候補として検討してもらいます。

## 一覧

```bash
ascelerate nominations
ascelerate nominations --app <bundle-id> --state draft
```

下書き、提出済み、アーカイブ済みのノミネーションを一覧表示します（`--state` で状態を1つに絞り込めます）。機械可読な出力には `--json` を追加してください。

## 作成

```bash
ascelerate nominations create --app <bundle-id> --type enhancements --name "Version 5" \
  --description "What's new and why it matters to users" --publish-start 2026-11-01 \
  --devices iphone,ipad --locales en-US,tr-TR
```

| オプション | 説明 |
|---|---|
| `--app` | 対象のアプリ（複数のアプリを対象とするノミネーションでは `--app` を繰り返します） |
| `--type` | `launch`、`enhancements`、`new-content` のいずれか |
| `--name`、`--description` | ノミネーションの内容。Apple のエディター向けに記述します |
| `--publish-start` | リリース日（`yyyy-MM-dd` または ISO 8601）。期間限定のコンテンツには `--publish-end` も指定します |
| `--devices` | デバイスファミリー：`iphone`、`ipad`、`mac`、`apple-tv`、`apple-watch`、`vision` |
| `--locales` | リリースがローカライズされているロケール |
| `--territories` | 最初にリリースする国または地域（デフォルト：すべて） |
| `--materials` | 補足資料（プレスキット、動画など）へのリンク。カンマ区切りで指定します |
| `--notes` | Apple へのメモ |
| `--pre-order` | アプリが予約注文に対応していることを示します |
| `--submit` | 下書きとして保存せず、すぐに提出します |

`--submit` を指定しない場合、ノミネーションは下書きとして保存され、内容を確認・変更できます。

## 更新、提出、アーカイブ、削除

```bash
ascelerate nominations update <id> --publish-start 2026-11-08
ascelerate nominations submit <id>
ascelerate nominations archive <id>
ascelerate nominations delete <id>
```

`update` は下書きを変更します。ノミネーションの ID は `nominations` で確認できます。フィーチャーするかどうかは Apple のエディターが判断するため、リリース日より十分前にノミネートしてください。
