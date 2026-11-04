---
sidebar_position: 22
title: ユーザ
---

# ユーザ

チームのメンバーと保留中の招待です。役割、表示できる App、証明書、ID、プロファイルへのアクセスを扱います。メンバーは**メールアドレス**または ID で、App はバンドル ID またはエイリアスで指定します。役割の変更やメンバーの削除には Admin のキーが必要です。

## 一覧

```bash
ascelerate users
ascelerate users info someone@example.com
ascelerate users invitations
```

`users` は全員の役割、表示できる App の数、証明書、ID、プロファイルへのアクセスを一覧表示します。`info` は 1 人の詳細を App とともに表示します。`invitations` はまだ承認されていない招待を有効期限とともに一覧表示します。3 つとも `--json` を使えます。

## 変更

```bash
ascelerate users update someone@example.com --roles developer,marketing
ascelerate users update someone@example.com --apps com.example.app,myalias
ascelerate users update someone@example.com --all-apps --provisioning true
ascelerate users remove someone@example.com
```

`--roles` は役割を置き換えます（`admin`、`finance`、`sales`、`marketing`、`app-manager`、`developer`、`access-to-reports`、`customer-support`、`create-apps` など）。`--apps` は表示できる App を置き換え、`--all-apps` はすべての App を表示できるようにします。各コマンドは変更点を表示し、確認してから保存します。`remove` はメンバーをただちにチームから削除します。

## 招待

```bash
ascelerate users invite --email someone@example.com --first-name Ada --last-name Lovelace --roles developer --apps com.example.app
ascelerate users cancel-invitation someone@example.com
```

App Store Connect は招待を作成するとすぐにメールを送ります。`--apps` を指定しないとすべての App を表示できます。`--provisioning` は証明書、ID、プロファイルへのアクセスを与えます。
