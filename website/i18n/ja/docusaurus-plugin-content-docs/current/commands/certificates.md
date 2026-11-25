---
sidebar_position: 9
title: 証明書
---

# 証明書

すべての証明書コマンドはインタラクティブモードに対応しています。引数はオプションです。

## 一覧

```bash
ascelerate certs list
ascelerate certs list --type DISTRIBUTION
```

## 詳細

```bash
# インタラクティブな選択
ascelerate certs info

# シリアル番号または表示名で指定
ascelerate certs info "Apple Distribution: Example Inc"
```

## 作成

```bash
# インタラクティブなタイプ選択、RSAキーペアとCSRを自動生成
ascelerate certs create

# タイプを指定
ascelerate certs create --type DISTRIBUTION

# 独自のCSRを使用
ascelerate certs create --type DEVELOPMENT --csr my-request.pem
```

証明書を要求する前に、秘密鍵が書き込まれ（本人だけが読み取り可能）、出力フォルダが確認されます。要求が失敗した場合、鍵は削除されます。`--csr` から作成した証明書も保存されます（`--output` がない場合は `<シリアル番号>.cer`）。キーチェーンへの読み込み後、コマンドはローカルファイルの削除を提案します。`--output` または `--yes` を付けた場合は、`--delete-local-files` を指定しない限りファイルは残ります。

`--csr` を指定しない場合、コマンドはRSAキーペアとCSRを自動生成し、ログインキーチェーンにすべてをインポートします。

## 失効

```bash
# インタラクティブな選択
ascelerate certs revoke

# シリアル番号で指定
ascelerate certs revoke ABC123DEF456
```
