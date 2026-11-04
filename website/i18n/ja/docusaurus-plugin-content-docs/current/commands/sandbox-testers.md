---
sidebar_position: 7
title: Sandbox テスター
---

# Sandbox テスター

Sandbox でアプリ内課金やサブスクリプションを購入する Apple アカウントです。テスターは **Apple アカウント**（メールアドレス）または ID で指定します。テスターの作成と削除は App Store Connect（ユーザとアクセス > Sandbox）で行います。API では行えません。

## 一覧

```bash
ascelerate sandbox-testers
ascelerate sandbox-testers --json
```

各テスターの Apple アカウント、名前、ストアフロント、サブスクリプションの更新間隔、購入の中断の有無、Apple Pay を使えるかどうかを表示します。

## 変更

```bash
ascelerate sandbox-testers update tester@example.com --renewal-rate 3m
ascelerate sandbox-testers update tester@example.com --territory DEU --interrupt-purchases true
```

`--territory` はストアフロント（3 文字の国・地域コード）を設定します。`--interrupt-purchases` は、規約への同意や支払い情報の更新などの追加ステップのために購入を中断します。`--renewal-rate` は、そのテスターの月額サブスクリプションの更新間隔を `1h`、`30m`、`15m`、`5m`、`3m` から設定します（ほかの期間はそれに比例します）。コマンドは変更点を表示し、確認してから保存します。

## 購入履歴の消去

```bash
ascelerate sandbox-testers clear-history tester@example.com other@example.com
ascelerate sandbox-testers clear-history --all
```

テスターのアプリ内課金とサブスクリプションの購入履歴を消去し、最初から購入し直せるようにします。実行前に確認します。
