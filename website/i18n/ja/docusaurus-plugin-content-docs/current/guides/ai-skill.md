---
sidebar_position: 3
title: AIコーディングスキル
---

# AIコーディングスキル

ascにはスキルファイルが付属しており、AIコーディングエージェント（Claude Code、Cursor、Windsurf、GitHub Copilot）にすべてのコマンド、JSONフォーマット、ワークフローに関する完全な知識を提供します。

## バイナリからインストール（Claude Codeのみ）

```bash
ascelerate install-skill
```

ascは実行時に古いスキルを検出し、アップグレード後に更新を促します。削除するには：

```bash
ascelerate install-skill --uninstall
```

## npxでインストール（すべてのAIコーディングエージェント対応）

```bash
npx ascelerate-skill
```

インタラクティブなメニューが表示され、お使いのエージェントを選択して適切なディレクトリにスキルをインストールします。スキルファイルはGitHubから取得されるため、常に最新です。

削除するには：

```bash
npx ascelerate-skill --uninstall
```

## スキルで可能になること

スキルをインストールすると、AIコーディングエージェントは以下のことが可能になります：

- あらゆるascコマンドを代わりに実行
- リリースプロセス用のワークフローファイルを構築
- 複数言語のローカライゼーションを管理
- アーカイブからアップロード、提出までの完全なパイプラインを処理
- プロビジョニングプロファイル、証明書、デバイスの操作
