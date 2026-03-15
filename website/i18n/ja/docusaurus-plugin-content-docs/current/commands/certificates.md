---
sidebar_position: 9
title: 証明書
---

# 証明書

すべての証明書コマンドはインタラクティブモードに対応しています。引数はオプションです。

## 一覧

```bash
asc certs list
asc certs list --type DISTRIBUTION
```

## 詳細

```bash
# インタラクティブな選択
asc certs info

# シリアル番号または表示名で指定
asc certs info "Apple Distribution: Example Inc"
```

## 作成

```bash
# インタラクティブなタイプ選択、RSAキーペアとCSRを自動生成
asc certs create

# タイプを指定
asc certs create --type DISTRIBUTION

# 独自のCSRを使用
asc certs create --type DEVELOPMENT --csr my-request.pem
```

`--csr` を指定しない場合、コマンドはRSAキーペアとCSRを自動生成し、ログインキーチェーンにすべてをインポートします。

## 失効

```bash
# インタラクティブな選択
asc certs revoke

# シリアル番号で指定
asc certs revoke ABC123DEF456
```
