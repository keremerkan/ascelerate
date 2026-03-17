---
sidebar_position: 3
title: エイリアス
---

# エイリアス

毎回完全なbundle IDを入力する代わりに、短いエイリアスを作成できます：

```bash
# エイリアスを追加（インタラクティブなアプリ選択）
ascelerate alias add myapp

# bundle IDの代わりにエイリアスを使用
ascelerate apps info myapp
ascelerate apps versions myapp
ascelerate apps localizations view myapp

# すべてのエイリアスを一覧表示
ascelerate alias list

# エイリアスを削除
ascelerate alias remove myapp
```

エイリアスは `~/.ascelerate/aliases.json` に保存されます。ドットを含まない引数はエイリアスとして検索されます。実際のbundle ID（常にドットを含む）はそのまま使用できます。

:::tip
エイリアスはすべてのアプリ、IAP、サブスクリプション、ビルドコマンドで使用できます。プロビジョニングコマンド（`devices`、`certs`、`bundle-ids`、`profiles`）は異なる識別子ドメインを使用するため、エイリアスを解決しません。
:::
