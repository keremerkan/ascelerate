---
sidebar_position: 2
title: セットアップ
---

# セットアップ

## 1. APIキーの作成

[App Store Connect > ユーザとアクセス > 統合 > App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api) にアクセスして、新しいキーを生成してください。`.p8` 秘密鍵ファイルをダウンロードします。

## 2. 設定

```bash
ascelerate configure
```

**Key ID**、**Issuer ID**、および `.p8` ファイルのパスを入力するよう求められます。秘密鍵は厳格なファイル権限（所有者のみアクセス可能）で `~/.ascelerate/` にコピーされます。

設定は `~/.ascelerate/config.json` に保存されます：

```json
{
    "keyId": "KEY_ID",
    "issuerId": "ISSUER_ID",
    "privateKeyPath": "/Users/.../.ascelerate/AuthKey_XXXXXXXXXX.p8"
}
```

## 3. 確認

簡単なコマンドを実行して、すべてが正常に動作することを確認します：

```bash
ascelerate apps list
```

認証情報が正しければ、すべてのアプリの一覧が表示されます。

## レートリミット

App Store Connect APIには、1時間あたり3600リクエストのローリングクォータがあります。現在の使用状況はいつでも確認できます：

```bash
ascelerate rate-limit
```

```
Hourly limit: 3600 requests (rolling window)
Used:         57
Remaining:    3543 (98%)
```
