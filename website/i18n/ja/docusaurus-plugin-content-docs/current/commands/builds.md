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

出力には、各ビルドのアプリバージョン、プラットフォーム、ビルド番号、処理状態、アップロード日が表示されます。機械可読な出力には `--json` を追加してください（[規約](../guides/automation.md#json-output)）。

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

App Store 配布用プロファイルで署名された `.xcarchive`（手動署名のプロジェクト）は、アプリと拡張機能それぞれのインストール済み App Store プロファイルでエクスポートされるため、Xcode がプロファイルを新たに作成することはありません。それ以外のアーカイブは自動署名でエクスポートされます。ファイルを指定した場合、`--bundle-id` は別のアプリを含むファイルを、エクスポートや送信の前に拒否します。

### App Store Connect API を使ったアップロード

```bash
ascelerate builds upload MyApp.ipa --api
ascelerate builds upload --latest --bundle-id com.example.MyApp --api
```

`--api` を指定すると、altool の代わりに App Store Connect API のビルドアップロードを使ってビルドを送信します。認証には、他のコマンドと同じ API キーを使用します。`.ipa` または Mac の `.pkg`（あるいは先にエクスポートされる `.xcarchive`）を受け付け、中に含まれるアプリからバージョンとビルド番号を読み取り、ファイルをチャンクに分けて 1 つずつアップロードし（ターミナルではプログレスバーを表示します。[チャンク単位のアップロード](../guides/automation.md#upload-chunks)を参照）、App Store Connect がファイルを受け付けるまで待機します。Apple がファイルを拒否した場合は、Apple のエラーコードと説明を表示してコマンドが失敗します。警告はアップロードが成功した後に表示されます。その後の処理は通常どおり進みます（[処理の待機](#await-processing)を参照）。

現時点では、引き続き altool がデフォルトです。

### 他のツール向けの進行状況

```bash
ascelerate builds archive --scheme MyApp --json-events
ascelerate builds upload MyApp.ipa --api --json-events
```

`--json-events` を指定すると、どちらのコマンドも標準出力に 1 行につき 1 つの JSON オブジェクトを出力し（`step`、アーカイブのパスを含む `archived`、`uploading`、`progress`、`processing`、Apple の警告を含む `finished`）、xcodebuild の出力を含む読みやすい出力は標準エラー出力に移ります。`screenshot run --json-events` と同じ方式です。アーカイブ時には、xcodebuild は警告とエラーのみを出力します。

## アップロード履歴

```bash
ascelerate builds uploads <bundle-id>
ascelerate builds uploads <bundle-id> --platform macos --limit 20
ascelerate builds uploads <bundle-id> --delete-stale
```

アプリの最近のアップロードを、altool、Xcode、`--api` のどれで行われたかにかかわらず一覧表示します。各アップロードの状態（Awaiting Upload、Processing、Complete、Failed）と、Apple が付加したエラーや警告も表示されます。アップロードがいつまでもビルドにならない場合は、ここを確認してください。機械可読な出力には `--json` を追加してください。

悪いタイミングで接続が切れると、届くことのないファイルを待ち続けるアップロードレコードが残ることがあります。`--api` によるアップロードは、成功した後に同じビルドのそうしたレコードを削除します。`--delete-stale` は残っているレコードを削除します。対象は、同じビルドの別のアップロードが先に進んでいるのにまだファイルを待っているレコードと、1日以上ファイルを待っているレコードです。進行中のアップロードが削除されることはありません。

## 処理の待機 {#await-processing}

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
