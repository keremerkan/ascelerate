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
ascelerate builds list --bundle-id <bundle-id> --platform macos
```

出力には、各ビルドのアプリバージョン、プラットフォーム、ビルド番号、処理状態、アップロード日が表示されます。

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

`.ipa`、`.pkg`、`.xcarchive` ファイルを受け付けます。`.xcarchive` が指定された場合、アーカイブのプラットフォームを検出し、アップロード前に自動的に `.ipa`（iOS ファミリー）または `.pkg`（macOS）にエクスポートします。該当するプラットフォームは altool に渡されます。

## 処理の待機

```bash
ascelerate builds await-processing <bundle-id>
ascelerate builds await-processing <bundle-id> --build-version 903
ascelerate builds await-processing <bundle-id> --build-version 903 --platform macos
```

最近アップロードされたビルドがAPIに表示されるまで数分かかることがあります。コマンドはプログレスインジケーターを表示しながら、ビルドが見つかり処理が完了するまでポーリングします。

## バージョンへのビルドの添付

```bash
# インタラクティブにビルドを選択して添付
ascelerate apps build attach <bundle-id>
ascelerate apps build attach <bundle-id> --version 2.1.0

# 最新のビルドを自動的に添付
ascelerate apps build attach-latest <bundle-id>
ascelerate apps build attach-latest <bundle-id> --platform macos

# バージョンから添付されたビルドを削除
ascelerate apps build detach <bundle-id>
```

`build attach-latest` は、最新のビルドがまだ処理中の場合に待機するか確認します。`--yes` を指定すると自動的に待機します。

ビルドの検索はプラットフォームを考慮して行われます。ユニバーサル購入のアプリではiOSとmacOSのビルドが同じビルド番号を持つことがあるため、添付コマンドは対象バージョンのプラットフォームに該当するビルドのみを対象とします。
