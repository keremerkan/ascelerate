---
sidebar_position: 7
title: サブスクリプション
---

# サブスクリプション

## 一覧と詳細

```bash
asc sub groups <bundle-id>
asc sub list <bundle-id>
asc sub info <bundle-id> <product-id>
```

## サブスクリプションの作成、更新、削除

```bash
asc sub create <bundle-id> --name "Monthly" --product-id <product-id> --period ONE_MONTH --group-id <group-id>
asc sub update <bundle-id> <product-id> --name "Monthly Plan"
asc sub delete <bundle-id> <product-id>
```

## サブスクリプショングループ

```bash
asc sub create-group <bundle-id> --name "Premium"
asc sub update-group <bundle-id> --name "Premium Plus"
asc sub delete-group <bundle-id>
```

## 審査への提出

```bash
asc sub submit <bundle-id> <product-id>
```

## サブスクリプションのローカライゼーション

```bash
asc sub localizations view <bundle-id> <product-id>
asc sub localizations export <bundle-id> <product-id>
asc sub localizations import <bundle-id> <product-id> --file sub-de.json
```

## グループのローカライゼーション

```bash
asc sub group-localizations view <bundle-id>
asc sub group-localizations export <bundle-id>
asc sub group-localizations import <bundle-id> --file group-de.json
```

インポートコマンドは、存在しないロケールを確認のうえ自動的に作成するため、App Store Connectにアクセスせずに新しい言語を追加できます。
