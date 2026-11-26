---
sidebar_position: 14
title: App内イベント
---

# App内イベント

App内イベントを作成・管理します。App Store のプロダクトページや検索結果に表示される、時期に応じたイベント（ライブイベント、プレミア、チャレンジ、特別オファーなど）です。イベントは**参照名**またはIDで指定します。

## 一覧と確認

```bash
ascelerate events list <bundle-id>
ascelerate events list <bundle-id> --state PUBLISHED
ascelerate events info <bundle-id> <reference-name-or-id>
```

`info` はイベントの属性、地域ごとのスケジュール、ローカリゼーションの概要を表示します。

## 作成・更新・削除

```bash
ascelerate events create <bundle-id> --reference-name "summer-sale" --badge SPECIAL_EVENT --purpose ATTRACT_NEW_USERS --priority HIGH

# 初期スケジュール付き
ascelerate events create <bundle-id> --reference-name "launch" \
  --territories USA,GBR --publish-start 2026-07-01 --event-start 2026-07-05 --event-end 2026-07-12

ascelerate events update <bundle-id> summer-sale --priority NORMAL --badge NONE
ascelerate events delete <bundle-id> summer-sale
```

イベントには国や地域ごとのスケジュールを複数設定できます。`--territories` を指定しない場合、新しい日付はそれぞれのスケジュールに適用されます。`--territories` を指定すると、指定した国や地域のスケジュール1つがすべてを置き換え、置き換える内容が一覧表示されます。

- **バッジ：** `LIVE_EVENT`、`PREMIERE`、`CHALLENGE`、`COMPETITION`、`NEW_SEASON`、`MAJOR_UPDATE`、`SPECIAL_EVENT`。バッジを解除するには `update` に `--badge NONE` を指定します。
- **目的：** `APPROPRIATE_FOR_ALL_USERS`、`ATTRACT_NEW_USERS`、`KEEP_ACTIVE_USERS_INFORMED`、`BRING_BACK_LAPSED_USERS`。
- **優先度：** `HIGH` または `NORMAL`。
- **スケジュールの日付**（`--publish-start`、`--event-start`、`--event-end`）は ISO8601（`2026-07-01T09:00:00Z`）または `yyyy-MM-dd`（UTC の午前0時）を受け付けます。スケジュールには `--territories` が必要です。国や地域のコード、またはすべての国や地域を対象にする `all` を指定します。`update` で省略すると、各スケジュールの国や地域はそのまま保持されます。

## ローカリゼーション

```bash
ascelerate events localizations view <bundle-id> summer-sale
ascelerate events localizations export <bundle-id> summer-sale
ascelerate events localizations import <bundle-id> summer-sale --file event-locales.json
```

各ローカリゼーションには `name`、`shortDescription`、`longDescription` が含まれます。言語はアプリで設定されている言語と一致している必要があります（例：`tr-TR` ではなく `tr`）。

```json
{
  "en-US": {
    "name": "Summer Sale",
    "shortDescription": "夏の大幅割引",
    "longDescription": "夏のイベントに参加して、期間限定の割引をお楽しみください。"
  }
}
```

## メディア

ローカリゼーションごとのイベントカードおよびイベント詳細ページのスクリーンショット（`.png`/`.jpg`）と、ビデオクリップ（`.mp4`/`.mov`）です。

```bash
ascelerate events media list <bundle-id> summer-sale
ascelerate events media upload <bundle-id> summer-sale --locale en-US --asset-type EVENT_CARD card.png
ascelerate events media upload <bundle-id> summer-sale --locale en-US --asset-type EVENT_DETAILS_PAGE clip.mp4 --preview-frame 00:00:03:00
ascelerate events media delete <bundle-id> summer-sale <media-id>
```

アセットタイプは `EVENT_CARD` と `EVENT_DETAILS_PAGE` です。ファイルの種類によって、スクリーンショットとしてアップロードされるかビデオクリップとしてアップロードされるかが決まります。`--preview-frame` はビデオのプレビューフレームのタイムコードを設定します。

## その他のオプション

上の例に出てこないオプション：

- `events create` `--primary-locale`, `--deep-link`, `--purchase-requirement`：メイン言語（App Review で必須）、カードが開くリンク、購入の要件
- `events update` `--primary-locale`, `--deep-link`, `--purchase-requirement`：同じ 3 つの項目の変更
- `events localizations export|import` `--output`, `--verbose`：export：書き出すファイル／import：Apple の応答を表示
