---
sidebar_position: 7
title: サブスクリプション
---

# サブスクリプション

## 一覧と詳細

```bash
ascelerate sub groups <bundle-id>
ascelerate sub list <bundle-id>
ascelerate sub info <bundle-id> <product-id>
```

## サブスクリプションの作成、更新、削除

```bash
ascelerate sub create <bundle-id> --name "Monthly" --product-id <product-id> --period ONE_MONTH --group-id <group-id>
ascelerate sub update <bundle-id> <product-id> --name "Monthly Plan"
ascelerate sub delete <bundle-id> <product-id>
```

## サブスクリプショングループ

```bash
ascelerate sub create-group <bundle-id> --name "Premium"
ascelerate sub update-group <bundle-id> --name "Premium Plus"
ascelerate sub delete-group <bundle-id>
```

## 審査への提出

```bash
ascelerate sub submit <bundle-id> <product-id>
```

## サブスクリプションのローカライゼーション

```bash
ascelerate sub localizations view <bundle-id> <product-id>
ascelerate sub localizations export <bundle-id> <product-id>
ascelerate sub localizations import <bundle-id> <product-id> --file sub-de.json
```

## グループのローカライゼーション

```bash
ascelerate sub group-localizations view <bundle-id>
ascelerate sub group-localizations export <bundle-id>
ascelerate sub group-localizations import <bundle-id> --file group-de.json
```

インポートコマンドは、存在しないロケールを確認のうえ自動的に作成するため、App Store Connectにアクセスせずに新しい言語を追加できます。

## 価格設定

サブスクリプションの価格設定は地域ごとに行われます。アプリ内課金のような自動均等化の概念はないため、価格を設定したい各地域に独自のレコードが必要です。CLIでは単一の地域の価格を設定するか、Appleの現地通貨価格層を使用してすべての地域に価格を展開することができます。

```bash
# 現在の地域別価格を表示（存在しない場合は警告）
ascelerate sub pricing show <bundle-id> <product-id>

# ある地域で利用可能な価格層を一覧表示
ascelerate sub pricing tiers <bundle-id> <product-id> --territory USA

# 単一地域の価格を設定
ascelerate sub pricing set <bundle-id> <product-id> --price 4.99 --territory USA

# すべての地域に価格を展開（地域ごとに1回のPOST）
ascelerate sub pricing set <bundle-id> <product-id> --price 4.99 --equalize-all-territories
```

### 価格変更と既存サブスクライバー

Appleは、価格変更の方向によって既存サブスクライバーへの扱いを変えます。`sub pricing set` は影響を受ける各地域の現在の価格を取得し、変更を分類して、適切な動作を強制します。

- **値下げ**: 既存サブスクライバーは自動的に低い価格に移行します。インタラクティブな実行では警告とともに確認を求めます。`--yes` モードでは、収益への影響を確認するために `--confirm-decrease` を追加する必要があります — `--yes` だけでは不十分です。
- **値上げ**: 既存サブスクライバーをどのように扱うかを明示的に選択する必要があります。以下のいずれかが設定されない限り、コマンドはエラーになります：
  - `--preserve-current` — 既存サブスクライバーを以前の価格のまま維持
  - `--no-preserve-current` — Appleの通知期間後に既存サブスクライバーに新しい価格を適用
- **新規地域**（既存価格なし）: 考慮すべき既存サブスクライバーはなく、フラグは任意です。
- **変更なし**: 何もせずスキップされます。

`--equalize-all-territories` でも同じルールが集約的に適用されます。展開先の地域のいずれかが値上げの場合、保持フラグはすべてに対して必要です。`--yes` モードで値下げが含まれる場合、`--confirm-decrease` が必要です。

```bash
# 標準的なグローバル値上げ: すべての地域で $4.99 → $9.99、
# 既存サブスクライバーは旧価格のまま
ascelerate sub pricing set myapp com.example.monthly \
  --price 9.99 --territory USA --equalize-all-territories \
  --preserve-current
```
