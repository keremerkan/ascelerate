---
sidebar_position: 1
title: ワークフロー
---

# ワークフロー

ワークフローファイルを使用して、複数のコマンドを1回の自動実行にまとめます：

```bash
ascelerate run-workflow release.txt
ascelerate run-workflow release.txt --yes   # すべてのプロンプトをスキップ（CI/CD向け）
ascelerate run-workflow                     # .workflow/.txtファイルからインタラクティブに選択
```

ワークフローファイルは、1行に1つのコマンドを記述するプレーンテキストファイルです（`ascelerate` プレフィックスは不要）。`#` で始まる行はコメント、空行は無視されます。`.workflow` と `.txt` の両方の拡張子に対応しています。

## 例

サンプルアプリのバージョン2.1.0を提出する `release.txt`：

```
# MyApp v2.1.0 のリリースワークフロー

# App Store Connectで新しいバージョンを作成
apps create-version com.example.MyApp 2.1.0

# ビルド、バリデーション、アップロード
builds archive --scheme MyApp
builds validate --latest --bundle-id com.example.MyApp
builds upload --latest --bundle-id com.example.MyApp

# ビルドの処理完了を待機
builds await-processing com.example.MyApp

# ローカライゼーションを更新してビルドを添付
apps localizations import com.example.MyApp --file localizations.json
apps build attach-latest com.example.MyApp

# 審査に提出
apps review submit com.example.MyApp
```

## 確認動作

`--yes` を指定しない場合、ワークフローの開始前に確認が求められ、各コマンドは通常どおりプロンプトを表示します（例：審査への提出前など）。`--yes` を指定すると、すべてのプロンプトがスキップされ、完全な無人実行が可能になります。

## ワークフローを確認する

```bash
ascelerate run-workflow release.txt --check          # every step parses; nothing runs
ascelerate run-workflow release.txt --check --json   # each step's line, command and error
```

`--check` は何も実行せずに各ステップの引数とオプションを解析し、解析できないステップをファイル内の行番号とともに一覧表示します。

## 別のプログラムから実行を追跡する

```bash
ascelerate run-workflow release.txt --json-events
```

`--json-events` を付けると、stdout には 1 行に 1 つの JSON イベントが出力され、ステップ自身の出力を含む読みやすい出力はすべて stderr に送られます。イベントは `workflow`（ステップとその行）、`step`（`running`、続いて `succeeded`、エラー付きの `failed`、または `dry-run`）、`finished`、そしてステップが尋ねる質問ごとの `prompt`（`kind`：`confirm`、`choice`、`choices`、`text`、`message`、`options`）です。ステップはその後、stdin から 1 行で回答を読み取ります（`y` または `n`、1 から始まる選択肢の番号、またはテキスト）。ワークフローは事前に確認されません。実行するプログラムがすでに確認しているためです。ネストされたワークフローのイベントには `depth` が付きます。単独で実行したときに独自のイベントを出力するステップ（`builds archive`、`builds upload`、`screenshot`）は、ここではそのイベントを出力せず、進行状況は stderr に送られます。ただし、`--api` でのアップロードの進行状況は、そのステップの `progress` イベント（`index`、`bytes` のうちの `sent`）として出力されます。`ascelerate settings --xcodebuild-output full` で変更しない限り、ステップのxcodebuild出力は簡潔（警告とエラーのみ）になります。

## ネスト

ワークフローは他のワークフローを呼び出すことができます（ワークフローファイル内で `run-workflow` を使用）。循環参照は検出されて防止されます。

## ビルドパイプラインとの統合

`builds upload` は内部変数を設定するため、後続の `await-processing` と `build attach-latest` はアップロードしたばかりのビルドを自動的にターゲットにします。これにより、APIの反映の遅延による競合状態を回避できます。
