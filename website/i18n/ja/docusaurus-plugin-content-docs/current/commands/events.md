---
sidebar_position: 14
title: アプリ内イベント
---

# アプリ内イベント

アプリ内イベントを作成・管理します。App Store の製品ページや検索結果に表示される、時期に応じたイベント（ライブイベント、プレミア、チャレンジ、特別オファーなど）です。イベントは**参照名**またはIDで指定します。

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

- **バッジ：** `LIVE_EVENT`、`PREMIERE`、`CHALLENGE`、`COMPETITION`、`NEW_SEASON`、`MAJOR_UPDATE`、`SPECIAL_EVENT`。バッジを解除するには `update` に `--badge NONE` を指定します。
- **目的：** `APPROPRIATE_FOR_ALL_USERS`、`ATTRACT_NEW_USERS`、`KEEP_ACTIVE_USERS_INFORMED`、`BRING_BACK_LAPSED_USERS`。
- **優先度：** `HIGH` または `NORMAL`。
- **スケジュールの日付**（`--publish-start`、`--event-start`、`--event-end`）は ISO8601（`2026-07-01T09:00:00Z`）または `yyyy-MM-dd`（UTC の午前0時）を受け付けます。すべての地域を対象にする場合は `--territories` を省略します。

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
ascelerate events media upload <bundle-id> summer-sale --locale en-US --asset-type EVENT_DETAILS_PAGE clip.mp4 --preview-frame 00:00:03
ascelerate events media delete <bundle-id> summer-sale <media-id>
```

アセットタイプは `EVENT_CARD` と `EVENT_DETAILS_PAGE` です。ファイルの種類によって、スクリーンショットとしてアップロードされるかビデオクリップとしてアップロードされるかが決まります。`--preview-frame` はビデオのプレビューフレームのタイムコードを設定します。
