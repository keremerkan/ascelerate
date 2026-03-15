---
sidebar_position: 3
title: エイリアス
---

# エイリアス

毎回完全なbundle IDを入力する代わりに、短いエイリアスを作成できます：

```bash
# エイリアスを追加（インタラクティブなアプリ選択）
asc alias add myapp

# bundle IDの代わりにエイリアスを使用
asc apps info myapp
asc apps versions myapp
asc apps localizations view myapp

# すべてのエイリアスを一覧表示
asc alias list

# エイリアスを削除
asc alias remove myapp
```

エイリアスは `~/.asc/aliases.json` に保存されます。ドットを含まない引数はエイリアスとして検索されます。実際のbundle ID（常にドットを含む）はそのまま使用できます。

:::tip
エイリアスはすべてのアプリ、IAP、サブスクリプション、ビルドコマンドで使用できます。プロビジョニングコマンド（`devices`、`certs`、`bundle-ids`、`profiles`）は異なる識別子ドメインを使用するため、エイリアスを解決しません。
:::
