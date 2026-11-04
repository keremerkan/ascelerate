---
sidebar_position: 18
title: Game Center
---

# Game Center

アプリのアチーブメント、リーダーボード、リーダーボードセットを、言語、画像、並び順とともに管理します。それぞれ **ID**（ゲームが使う vendor identifier）、参照名、または Apple ID で指定します。

テキストと画像は**バージョン**に属します。新しいアチーブメント、リーダーボード、セットは Prepare for Submission のバージョン 1 から始まり、バージョンはアプリと一緒に App Review に送られます。公開済みのものを変更する場合、コマンドは確認のうえ、まず次のバージョンを作成します。

## Game Center をオンにする

```bash
ascelerate game-center <bundle-id>                      # オン・オフ、件数、デフォルトのリーダーボード
ascelerate game-center enable <bundle-id>
ascelerate game-center version <bundle-id> --enabled true   # App Store バージョンの Game Center スイッチ
```

App Store Connect API では、一度オンにしたアプリの Game Center をオフに戻せません。Bundle ID には Game Center の機能が必要です。`version` は準備中のバージョン、または `--version` で指定したバージョンを対象にします。

## アチーブメント

```bash
ascelerate game-center achievements <bundle-id> [--json]
ascelerate game-center achievements info <bundle-id> first.win
ascelerate game-center achievements create <bundle-id> --id first.win --name "First Win" --points 10 [--hidden] [--repeatable]
ascelerate game-center achievements update <bundle-id> first.win --points 20 --hidden false
ascelerate game-center achievements update <bundle-id> first.win --archived true
ascelerate game-center achievements delete <bundle-id> first.win
```

アプリのアチーブメントは合計 1,000 ポイントを分け合い、1 つあたり 1〜100 ポイントです。`--hidden` を付けると、プレイヤーが獲得するまで非表示になります。公開されたことのあるアチーブメントは削除できないため、代わりにアーカイブしてください。

## リーダーボード

```bash
ascelerate game-center leaderboards <bundle-id> [--json]
ascelerate game-center leaderboards create <bundle-id> --id high.score --name "High Score"
ascelerate game-center leaderboards create <bundle-id> --id weekly.time --name "Weekly Time" \
  --formatter elapsed-time-second --sort low --submission recent --min 0 --max 3600 \
  --recurrence-start 2026-12-07T00:00:00Z --recurrence-duration PT168H --recurrence-rule "FREQ=DAILY;INTERVAL=7"
ascelerate game-center leaderboards update <bundle-id> weekly.time --hidden true
ascelerate game-center leaderboards default <bundle-id> high.score
```

デフォルトでは、スコアは整数で、高いスコアが上位になり、各プレイヤーのベストスコアが使われます。`--formatter` には `integer`、`decimal-point-1-place`〜`decimal-point-3-place`、`elapsed-time-centisecond`、`elapsed-time-second`、`elapsed-time-minute`、または `money-dollar-decimal` などの通貨を指定できます。

定期リーダーボードは一定の間隔でリセットされます。期間は時間または分で指定し（`PT24H`、1 週間なら `PT168H`）、ルールは分・時間・日単位で繰り返します（`FREQ=DAILY;INTERVAL=7` で毎週リセット）。スコア範囲は `--min "" --max ""` でまとめてのみ消去できます。

最初のリーダーボードが、Game Center を開いたときに表示されるデフォルトになります。`default` で変更できます。

## リーダーボードセット

```bash
ascelerate game-center sets <bundle-id>
ascelerate game-center sets create <bundle-id> --id all.scores --name "All Scores" --leaderboards high.score,weekly.time
ascelerate game-center sets update <bundle-id> all.scores --leaderboards weekly.time,high.score
```

`--leaderboards` は、セットのリーダーボードを指定した順序で設定し、現在のものと置き換えます。

## 言語と画像

アチーブメント、リーダーボード、セットには同じ言語・画像コマンドがあります。`achievements` を `leaderboards` または `sets` に置き換えてください。

```bash
ascelerate game-center achievements localizations <bundle-id> first.win
ascelerate game-center achievements localizations set <bundle-id> first.win --locale en-US \
  --name "First Win" --before-earned "Win a round." --after-earned "You won a round."
ascelerate game-center achievements localizations export <bundle-id> first.win --output first-win.json
ascelerate game-center achievements localizations import <bundle-id> first.win --file first-win.json
ascelerate game-center achievements localizations delete <bundle-id> first.win --locale tr

ascelerate game-center achievements image upload <bundle-id> first.win --locale en-US icon.png
ascelerate game-center achievements image delete <bundle-id> first.win --locale en-US
```

アチーブメントに新しい言語を追加するには、名前と 2 つの説明が必要です。リーダーボードの言語には、名前、任意の説明、言語ごとの `--formatter`、スコアの後に付く単位（`--suffix " points"`、`--suffix-singular " point"`）があります。セットの言語には名前があります。

画像は 1 つの言語に属します。正方形で 512×512 以上（通常は 512×512 または 1024×1024）の PNG または JPEG にしてください。アップロードすると、その言語の現在の画像が置き換えられ、Apple の確認を待つので、却下された画像はすぐに報告されます。

## 並び順と App Review

```bash
ascelerate game-center achievements reorder <bundle-id> first.win,high.five
ascelerate game-center achievements submit <bundle-id> first.win [--platform ios]
```

`reorder` は指定したものをその順序で先頭に置き、残りは今の順序のまま続きます。`submit` は項目の新しいバージョンをアプリの下書きの提出に追加します（なければ作成します）。下書きを `ascelerate apps review submit` で提出すると App Review に送られます。
