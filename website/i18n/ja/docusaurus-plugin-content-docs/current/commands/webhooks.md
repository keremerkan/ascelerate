---
sidebar_position: 20
title: Webhook
---

# Webhook

アプリのイベントが発生したときに、App Store Connect からお使いのサーバーへ送信されるようにします。対象となるのは、審査状態の変化、ビルドのアップロード、TestFlight の外部ビルドの状態、テスターからのフィードバックです。Webhook は**名前**または ID で指定します。

## 一覧

```bash
ascelerate webhooks <bundle-id>
```

## 作成

```bash
ascelerate webhooks create <bundle-id> --name "Release bot" --url https://example.com/hook \
  --events app-store-version-app-version-state-updated,build-upload-state-updated
```

`--events` にはカンマ区切りのリスト、または `all` を指定します。イベントの種類には次のようなものがあります。

| イベント | 送信されるタイミング |
|---|---|
| `app-store-version-app-version-state-updated` | バージョンの App Review またはリリースの状態が変わったとき |
| `build-upload-state-updated` | ビルドのアップロードの状態が変わったとき |
| `build-beta-detail-external-build-state-updated` | ビルドの外部 TestFlight の状態が変わったとき |
| `beta-feedback-crash-submission-created` | テスターがクラッシュのフィードバックを送信したとき |
| `beta-feedback-screenshot-submission-created` | テスターがスクリーンショットのフィードバックを送信したとき |

バックグラウンドアセットや代替配信のイベントを含むすべての種類は、`ascelerate webhooks create --help` で確認できます。

Apple は各リクエストに Webhook のシークレットで署名します。`--secret` を指定しない場合、`create` がランダムなシークレットを生成して一度だけ表示します。App Store Connect で再び表示されることはないため、サーバーに保存しておいてください。`--disabled` を指定すると、Webhook を無効の状態で作成します。

## テストとデバッグ

```bash
ascelerate webhooks ping <bundle-id> "Release bot"
ascelerate webhooks deliveries <bundle-id> "Release bot"
ascelerate webhooks deliveries <bundle-id> "Release bot" --state failed
ascelerate webhooks redeliver <delivery-id>
```

`ping` はテストイベントを送信します。`deliveries` は最近の配信を、イベントの種類、サーバーが返した HTTP ステータス、エラーとともに一覧表示します（`--state succeeded|failed|pending`、`--limit`、`--json`）。サーバーを修正したら、`redeliver` で配信のイベントを再送信できます。

## 更新と削除

```bash
ascelerate webhooks update <bundle-id> "Release bot" --enabled false
ascelerate webhooks update <bundle-id> "Release bot" --events all --url https://example.com/new-hook
ascelerate webhooks delete <bundle-id> "Release bot"
```

`--events` はリスト全体を置き換えます。`--secret` を指定すると新しい署名用シークレットを設定します。
