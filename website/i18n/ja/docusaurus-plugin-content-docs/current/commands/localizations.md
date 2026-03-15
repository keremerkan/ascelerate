---
sidebar_position: 3
title: ローカライゼーション
---

# ローカライゼーション

App Storeバージョンのローカライゼーション（説明文、新機能、キーワードなど）を管理します。

## 表示

```bash
asc apps localizations view <bundle-id>
asc apps localizations view <bundle-id> --version 2.1.0 --locale en-US
```

## エクスポート

```bash
asc apps localizations export <bundle-id>
asc apps localizations export <bundle-id> --version 2.1.0 --output my-localizations.json
```

## 単一ロケールの更新

```bash
asc apps localizations update <bundle-id> --whats-new "Bug fixes" --locale en-US
```

## JSONからの一括更新

```bash
asc apps localizations import <bundle-id> --file localizations.json
```

## JSONフォーマット

エクスポートとインポートの両方で同じフォーマットが使用されます：

```json
{
  "en-US": {
    "description": "My app description.\n\nSecond paragraph.",
    "whatsNew": "- Bug fixes\n- New dark mode",
    "keywords": "productivity,tools,utility",
    "promotionalText": "Try our new features!",
    "marketingURL": "https://example.com",
    "supportURL": "https://example.com/support"
  },
  "de-DE": {
    "whatsNew": "- Fehlerbehebungen\n- Neuer Dunkelmodus"
  }
}
```

JSONに含まれるフィールドのみが更新されます。省略されたフィールドは変更されません。

:::note
編集可能な状態（`PREPARE_FOR_SUBMISSION` または `WAITING_FOR_REVIEW`）のバージョンのみローカライゼーションの更新を受け付けます。ただし `promotionalText` はどの状態でも更新可能です。
:::
