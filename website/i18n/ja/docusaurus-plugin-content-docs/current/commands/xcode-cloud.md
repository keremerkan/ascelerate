---
sidebar_position: 21
title: Xcode Cloud
---

# Xcode Cloud

Xcode Cloud のビルドを確認し、開始できます。対象は、プロダクト、そのワークフロー、そして各ビルド実行とそのアクション、問題、テスト結果、アーティファクトです。

**プロダクト**は、Xcode で初めてリポジトリを接続したときに作成されます（**Integrate > Create Workflow**）。API でプロダクトを作成することはできません。作成後は、このページの操作をすべてコマンドラインから行えます。プロダクトはアプリの **Bundle ID**（またはエイリアス）、名前、ID のいずれかで、ワークフローは**名前**または ID で、ビルド実行は**番号**または ID で指定します。

## プロダクト

```bash
ascelerate xcode-cloud products
```

チームのプロダクト（アプリとフレームワーク）を、Bundle ID とリポジトリとともに一覧表示します。

## ワークフロー

```bash
ascelerate xcode-cloud workflows <bundle-id>
ascelerate xcode-cloud workflows info <bundle-id> "Release"
ascelerate xcode-cloud workflows update <bundle-id> "Default" --manual-only
ascelerate xcode-cloud workflows disable <bundle-id> "Nightly"
ascelerate xcode-cloud workflows enable <bundle-id> "Nightly"
ascelerate xcode-cloud workflows delete <bundle-id> "Old workflow"
```

`info` は、ワークフローの開始条件（ブランチやタグの変更、プルリクエスト、スケジュール、手動で開始できる対象）、アクション（ビルド、テスト、解析、アーカイブと、それぞれのスキーム、プラットフォーム、配布方法）、使用するリポジトリ、プロジェクト、Xcode と macOS のバージョンを表示します。`update --manual-only` は、ワークフローが自動で開始しないようにします（ブランチやタグの変更、プルリクエスト、スケジュール）。手動で開始できる対象はそのまま残ります。無効にしたワークフローはビルドを開始しません。ワークフローを削除しても、そのビルド実行は残ります。

## ビルド実行

```bash
ascelerate xcode-cloud runs <bundle-id>                         # 新しい順
ascelerate xcode-cloud runs <bundle-id> --workflow "Release" --limit 50
ascelerate xcode-cloud runs info <bundle-id> 42                 # 詳細とアクション
ascelerate xcode-cloud runs issues <bundle-id> 42 [--errors]
ascelerate xcode-cloud runs tests <bundle-id> 42 [--failed]
ascelerate xcode-cloud runs artifacts <bundle-id> 42
ascelerate xcode-cloud runs artifacts <bundle-id> 42 --type LOG_BUNDLE --download ./logs
```

各ビルド実行には、状態、ビルドしたブランチ・タグ・プルリクエスト、コミット、所要時間、エラー・警告・失敗したテストの件数が表示されます。`issues` は各アクションのエラーと警告をファイルと行番号とともに一覧表示します。`tests` はテスト結果を実行先（デバイスと OS）ごとに一覧表示し、失敗したテストにはそれぞれ失敗メッセージを添えます。`artifacts` はログ、アーカイブ、結果バンドル、プロダクトを一覧表示します。`--download` でそれらを保存でき、`--type` で対象を絞り込めます。

## ビルドの開始

```bash
ascelerate xcode-cloud start <bundle-id> "Release" --branch main
ascelerate xcode-cloud start <bundle-id> "Release" --tag v2.1
ascelerate xcode-cloud start <bundle-id> "PR checks" --pull-request 128
ascelerate xcode-cloud rerun <bundle-id> 42 [--clean]
```

`start` は指定したブランチ、タグ、またはプルリクエストをビルドします。指定しない場合、Xcode Cloud はワークフローの開始条件で手動開始が許可されている対象をビルドします。`rerun` は以前のビルド実行のコミットを、同じワークフローで再度ビルドします。`--clean` を指定するとキャッシュを使わずにビルドします。API からビルドをキャンセルすることはできません。

## リポジトリと Xcode のバージョン

```bash
ascelerate xcode-cloud repositories
ascelerate xcode-cloud xcode-versions
```

`xcode-versions` は、Xcode Cloud で利用できる Xcode のバージョンを、それぞれが動作する macOS のバージョンとともに一覧表示します。

一覧表示と詳細表示のコマンドはすべて `--json` に対応しています。
