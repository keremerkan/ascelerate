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

`configure` では、オプションの**ベンダー番号**も入力を求められます（App Store Connect → お支払いと財務レポート）。これは[売上レポートと財務レポート](../commands/reports.md)にのみ必要で、`vendorNumber` フィールドとして保存されます。スキップして後で追加することも、コマンドごとに `--vendor-number` で渡すこともできます。

[Apple Ads](../commands/ads.md) を利用するには別の認証情報が必要です。`ascelerate ads configure` で設定すると、同じファイルの `ads` セクションに保存されます。`configure` を再度実行しても、この認証情報は保持されます。

### 1回の実行だけ別のキーを使う

別のチームや CI など、別のキーでコマンドを実行するには、3つの環境変数をすべて設定します。その実行では `config.json` より優先され、ファイルは変更されません。

```bash
export ASCELERATE_KEY_ID=KEY_ID
export ASCELERATE_ISSUER_ID=ISSUER_ID
export ASCELERATE_PRIVATE_KEY_PATH=~/keys/AuthKey_KEY_ID.p8
ascelerate apps list
```

`builds archive` と `builds upload` はこのキーを `xcodebuild` にも渡します (`-authenticationKeyPath`, `-authenticationKeyID`, `-authenticationKeyIssuerID`)。そのため、プロファイルは Xcode にサインインしている Apple アカウントではなく、このキーで取得されます。この場合、キーには証明書・ID・プロファイルを管理する権限が必要です。実行で使われるキーは `ascelerate configure --show` で確認できます。

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
