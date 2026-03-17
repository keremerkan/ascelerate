---
sidebar_position: 2
title: ビルド
---

# ビルド

## ビルド一覧

```bash
ascelerate builds list
ascelerate builds list --bundle-id <bundle-id>
ascelerate builds list --bundle-id <bundle-id> --version 2.1.0
```

## アーカイブ

```bash
ascelerate builds archive
ascelerate builds archive --scheme MyApp --output ./archives
```

`archive` コマンドは、カレントディレクトリの `.xcworkspace` または `.xcodeproj` を自動検出し、スキームが1つしかない場合は自動的に解決します。

## バリデーション

```bash
ascelerate builds validate MyApp.ipa
```

## アップロード

```bash
ascelerate builds upload MyApp.ipa
```

`.ipa`、`.pkg`、`.xcarchive` ファイルを受け付けます。`.xcarchive` が指定された場合、アップロード前に自動的に `.ipa` にエクスポートします。

## 処理の待機

```bash
ascelerate builds await-processing <bundle-id>
ascelerate builds await-processing <bundle-id> --build-version 903
```

最近アップロードされたビルドがAPIに表示されるまで数分かかることがあります。コマンドはプログレスインジケーターを表示しながら、ビルドが見つかり処理が完了するまでポーリングします。

## バージョンへのビルドの添付

```bash
# インタラクティブにビルドを選択して添付
ascelerate apps build attach <bundle-id>
ascelerate apps build attach <bundle-id> --version 2.1.0

# 最新のビルドを自動的に添付
ascelerate apps build attach-latest <bundle-id>

# バージョンから添付されたビルドを削除
ascelerate apps build detach <bundle-id>
```

`build attach-latest` は、最新のビルドがまだ処理中の場合に待機するか確認します。`--yes` を指定すると自動的に待機します。
