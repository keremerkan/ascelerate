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

## ネスト

ワークフローは他のワークフローを呼び出すことができます（ワークフローファイル内で `run-workflow` を使用）。循環参照は検出されて防止されます。

## ビルドパイプラインとの統合

`builds upload` は内部変数を設定するため、後続の `await-processing` と `build attach-latest` はアップロードしたばかりのビルドを自動的にターゲットにします。これにより、APIの反映の遅延による競合状態を回避できます。
