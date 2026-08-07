---
sidebar_position: 17
title: TestFlight
---

# TestFlight

TestFlight のベータテストをエンドツーエンドで管理します。ベータグループ、テスター、ビルドの配信、What to Test のメモ、ベータ審査、テスターフィードバックに対応しています。

ビルドを対象とするコマンドは、デフォルトで期限切れでない最新のビルドを使用します。特定のビルドを対象にするには `--build <number>` を指定します。ユニバーサル購入のアプリが複数のプラットフォームで同じビルド番号を共有している場合は、`--platform` で対象を特定してください。

## ベータグループ

```bash
ascelerate testflight groups list <bundle-id>
ascelerate testflight groups info <bundle-id> "External Testers"
ascelerate testflight groups create <bundle-id> --name "Friends" --public-link --public-link-limit 100
ascelerate testflight groups update <bundle-id> "Friends" --public-link false
ascelerate testflight groups delete <bundle-id> "Friends"
```

`groups list` は、各グループの種類、公開リンク、テスター数の上限、フィードバック設定を表示します。`groups info` は、さらにグループのテスターと割り当てられたビルドを表示します。`create` では、チームメンバー向けの内部グループを作成する `--internal` と、すべてのビルドへの自動アクセスを付与する `--all-builds` を指定できます。外部グループでは、テスター数の上限（任意）付きの公開招待リンクを有効にできます。

グループ名は大文字・小文字を区別せずに照合されます。名前を省略すると、対話形式のリストから選択できます。

### ビルドの割り当て

```bash
# デフォルトでは期限切れでない最新のビルドが使用されます
ascelerate testflight groups add-build <bundle-id> "Friends"
ascelerate testflight groups add-build <bundle-id> "Friends" --build 123
ascelerate testflight groups remove-build <bundle-id> "Friends" --build 123
```

### 募集条件

公開リンクを使用するグループでは、デバイスファミリーと OS バージョンで参加を制限できます。

```bash
# 現在の条件と、Apple が受け付けるデバイス/OS の選択肢を表示
ascelerate testflight groups criteria view <bundle-id> "Friends" --options

# 条件を置き換え：FAMILY[:MIN[:MAX]]（境界値を含む）
ascelerate testflight groups criteria set <bundle-id> "Friends" --filter IPHONE:18.0 --filter IPAD:17.0:26

# すべての条件を削除
ascelerate testflight groups criteria clear <bundle-id> "Friends"
```

有効なデバイスファミリー：`IPHONE`、`IPAD`、`MAC`、`APPLE_TV`、`APPLE_WATCH`、`VISION`。

## テスター

```bash
ascelerate testflight testers list <bundle-id>
ascelerate testflight testers list <bundle-id> --group "Friends"

# 外部グループに追加すると TestFlight の招待が送信されます
ascelerate testflight testers add <bundle-id> --email tester@example.com --first-name Jane --group "Friends"

# 特定のグループから削除、またはアプリ全体から削除
ascelerate testflight testers remove <bundle-id> tester@example.com --group "Friends"
ascelerate testflight testers remove <bundle-id> tester@example.com

# 招待メールを再送信
ascelerate testflight testers invite <bundle-id> tester@example.com
```

`add` と `import` の `--group` には、カンマ区切りで複数のグループ名を指定できます。

### 一括インポート

```bash
ascelerate testflight testers import <bundle-id> --file testers.csv --group "Friends"
```

ファイルには1行につき1人のテスターを記述します：`email[,first name[,last name]]`（メールアドレス、名、姓の順）。空行、`#` で始まる行、先頭のヘッダー行はスキップされるため、App Store Connect の Web 画面がエクスポートする CSV 形式をそのまま使用できます。失敗した行は残りの処理を中断せず、最後にまとめて報告されます。

## ビルドと配信

```bash
# すべてのビルドと TestFlight の状態
ascelerate testflight builds <bundle-id>
ascelerate testflight builds <bundle-id> --platform ios --limit 50

# プレリリースバージョン
ascelerate testflight versions <bundle-id>

# 特定のビルドの詳細な状態
ascelerate testflight status <bundle-id> --build 123
```

`builds` は、各ビルドの処理状態、内部・外部テストの状態、有効期限を一覧表示します。`status` は、単一のビルドについて自動通知の設定とベータ審査の状態も表示します。

```bash
# ビルドを期限切れにする（テスターはインストールできなくなります）
ascelerate testflight expire <bundle-id> --build 123

# ビルドが利用可能になったことをテスターに通知
ascelerate testflight notify <bundle-id>

# ビルドの自動通知を有効化または無効化
ascelerate testflight auto-notify <bundle-id> --enabled false
```

## What to Test

テストメモはビルドごと、ロケールごとに保存されます。

```bash
ascelerate testflight whats-new view <bundle-id>

# 特定のロケールのみ。--locale を省略すると既存のすべてのロケールが対象になります
ascelerate testflight whats-new set <bundle-id> --text "新しいマップフィルターをお試しください" --locale ja
ascelerate testflight whats-new set <bundle-id> --text "新しいマップフィルターをお試しください"

# JSON によるエクスポートとインポート
ascelerate testflight whats-new export <bundle-id> --output notes.json
ascelerate testflight whats-new import <bundle-id> --file notes.json
```

JSON 形式は他のローカライゼーションコマンドと共通です。

```json
{
  "en-US": { "whatsNew": "Try the new map filters" },
  "ja": { "whatsNew": "新しいマップフィルターをお試しください" }
}
```

## ベータ審査

外部テストでは、ビルドごとにベータ審査が必要です。

```bash
ascelerate testflight submit <bundle-id> --build 123
ascelerate testflight status <bundle-id> --build 123
```

ベータ版アプリ情報と審査の詳細はアプリ単位で管理されます。

```bash
# ベータ版アプリの説明とフィードバックメール（ロケールごと）
ascelerate testflight app-info view <bundle-id>
ascelerate testflight app-info update <bundle-id> --locale ja --feedback-email me@example.com
ascelerate testflight app-info export <bundle-id> --output beta-app-info.json
ascelerate testflight app-info import <bundle-id> --file beta-app-info.json

# ベータ審査チーム向けの連絡先とデモアカウント
ascelerate testflight review-info <bundle-id>
ascelerate testflight review-info <bundle-id> --demo-account-name demo@example.com --demo-account-required true

# カスタムのベータ版使用許諾契約（--text "" で Apple の標準契約に戻ります）
ascelerate testflight eula <bundle-id>
ascelerate testflight eula <bundle-id> --file eula.txt
```

## テスターフィードバック

テスターが TestFlight から送信したクラッシュおよびスクリーンショットのフィードバックです。

```bash
ascelerate testflight feedback crashes list <bundle-id>
ascelerate testflight feedback crashes info <submission-id>
ascelerate testflight feedback crashes log <submission-id> --output crash.log
ascelerate testflight feedback crashes delete <submission-id>

ascelerate testflight feedback screenshots list <bundle-id>
ascelerate testflight feedback screenshots info <submission-id>
ascelerate testflight feedback screenshots download <bundle-id> [submission-id] --output feedback.zip
ascelerate testflight feedback screenshots delete <submission-id>
```

`list` は `--build` と `--platform` のフィルターを受け付けます。`info` は、モデル、OS バージョン、ロケール、接続の種類、バッテリー残量、空きディスク容量、テスターのコメントなど、デバイスの詳細な状況を表示します。`log` はクラッシュログを表示し、`--output` を指定するとファイルに保存します。`download` は送信されたスクリーンショットとコメントを1つの zip アーカイブにまとめます。送信 ID を省略すると、アプリの送信一覧がページ単位で表示され、その中から選択できます。スクリーンショットの URL は数日で期限切れになるため、保存しておきたいフィードバックは早めにダウンロードしてください。
