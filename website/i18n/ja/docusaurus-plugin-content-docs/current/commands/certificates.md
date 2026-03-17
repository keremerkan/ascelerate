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

`--csr` を指定しない場合、コマンドはRSAキーペアとCSRを自動生成し、ログインキーチェーンにすべてをインポートします。

## 失効

```bash
# インタラクティブな選択
ascelerate certs revoke

# シリアル番号で指定
ascelerate certs revoke ABC123DEF456
```
