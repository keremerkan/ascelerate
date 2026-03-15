---
sidebar_position: 2
title: ビルド
---

# ビルド

## ビルド一覧

```bash
asc builds list
asc builds list --bundle-id <bundle-id>
asc builds list --bundle-id <bundle-id> --version 2.1.0
```

## アーカイブ

```bash
asc builds archive
asc builds archive --scheme MyApp --output ./archives
```

`archive` コマンドは、カレントディレクトリの `.xcworkspace` または `.xcodeproj` を自動検出し、スキームが1つしかない場合は自動的に解決します。

## バリデーション

```bash
asc builds validate MyApp.ipa
```

## アップロード

```bash
asc builds upload MyApp.ipa
```

`.ipa`、`.pkg`、`.xcarchive` ファイルを受け付けます。`.xcarchive` が指定された場合、アップロード前に自動的に `.ipa` にエクスポートします。

## 処理の待機

```bash
asc builds await-processing <bundle-id>
asc builds await-processing <bundle-id> --build-version 903
```

最近アップロードされたビルドがAPIに表示されるまで数分かかることがあります。コマンドはプログレスインジケーターを表示しながら、ビルドが見つかり処理が完了するまでポーリングします。

## バージョンへのビルドの添付

```bash
# インタラクティブにビルドを選択して添付
asc apps build attach <bundle-id>
asc apps build attach <bundle-id> --version 2.1.0

# 最新のビルドを自動的に添付
asc apps build attach-latest <bundle-id>

# バージョンから添付されたビルドを削除
asc apps build detach <bundle-id>
```

`build attach-latest` は、最新のビルドがまだ処理中の場合に待機するか確認します。`--yes` を指定すると自動的に待機します。
