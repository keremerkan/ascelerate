---
sidebar_position: 15
title: カスタム製品ページ
---

# カスタム製品ページ

カスタム製品ページを作成・管理します。App Store の製品ページの代替バージョンで、独自のプロモーション用テキストとスクリーンショットを持ち、それぞれ固有のURLでアクセスできます。ページは**名前**またはIDで指定します。

## 一覧と確認

```bash
ascelerate product-pages list <bundle-id>
ascelerate product-pages info <bundle-id> <name-or-id>
```

`list` は各ページの名前、表示状態、共有可能な App Store URL（`ppid` を含む）、IDを表示します。`info` はページのバージョンとそのローカリゼーションも表示します。

## 作成

```bash
ascelerate product-pages create <bundle-id> --name "Summer Campaign" --locale en-US --promotional-text "期間限定オファー"
```

App Store Connect API では、ページを最初のバージョンと少なくとも1つのローカリゼーションとともに作成する必要があるため、`--locale` は必須です。他の言語は後から `product-pages localizations import` で追加します。

## 更新と削除

```bash
ascelerate product-pages update <bundle-id> "Summer Campaign" --name "Summer 2026" --visible false
ascelerate product-pages delete <bundle-id> "Summer Campaign"
```

`--visible` はページを App Store で公開するかどうかを切り替えます。

## ローカリゼーション

```bash
ascelerate product-pages localizations view <bundle-id> "Summer 2026"
ascelerate product-pages localizations export <bundle-id> "Summer 2026"
ascelerate product-pages localizations import <bundle-id> "Summer 2026" --file page-locales.json
```

各ローカリゼーションには、ページの編集可能なバージョンに適用される `promotionalText` が含まれます。

```json
{
  "en-US": { "promotionalText": "期間限定オファー" },
  "fr-FR": { "promotionalText": "Offre à durée limitée" }
}
```
