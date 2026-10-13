---
sidebar_position: 18
title: プロダクトページの最適化
---

# プロダクトページの最適化

App Store の元のプロダクトページに対して、別のスクリーンショット、アプリプレビュー、App アイコンをテストします。テストでは最大3つの**トリートメント**（ページのバリエーション）を App Store の訪問者の一部に表示し、そのコンバージョン率を元のページと比較します。テストとトリートメントは**名前**または ID で指定します。

## 一覧と確認

```bash
ascelerate experiments <bundle-id>
ascelerate experiments info <bundle-id> "Screenshot order"
```

`info` は、テストの状態、トラフィックの割合、日付に加えて、各トリートメントのロケールとロケールごとのメディアを表示します。どちらのコマンドも `--json` に対応しています。

## テストの作成

```bash
ascelerate experiments create <bundle-id> --name "Screenshot order" --traffic 50 --treatment "Map first" --treatment "Alerts first"
```

`--traffic` は、いずれかのトリートメントが表示される App Store 訪問者の割合（パーセント）です。この割合はトリートメント間で均等に分けられ、それ以外の訪問者には元のページが表示されます。`--platform` のデフォルトは `ios` です。

## トリートメント

```bash
ascelerate experiments treatments add <bundle-id> "Screenshot order" --name "Icon B" --app-icon AppIconB
ascelerate experiments treatments update <bundle-id> "Screenshot order" "Icon B" --name "Blue icon"
ascelerate experiments treatments delete <bundle-id> "Screenshot order" "Blue icon"
ascelerate experiments treatments remove-locale <bundle-id> "Screenshot order" "Map first" --locale de-DE
```

`--app-icon` では代替の App アイコンをテストします。このアイコンは、公開中のビルドに代替アイコンとして含まれている必要があります。トリートメントが対応していないロケールでは、テストの対象となった訪問者にも元のページが表示されます。

## メディア

```bash
ascelerate experiments media list <bundle-id> "Screenshot order"
ascelerate experiments media upload <bundle-id> "Screenshot order" "Map first" --locale en-US --display-type APP_IPHONE_67 01.png
ascelerate experiments media upload <bundle-id> "Screenshot order" "Map first" --locale en-US --preview-type APP_IPHONE_67 preview.mp4
ascelerate experiments media delete <bundle-id> "Screenshot order" <media-id>
```

アップロードは[カスタムプロダクトページのメディア](product-pages.md)と同じように動作します。画像は `--display-type` に応じてスクリーンショットセットに、ビデオは `--preview-type` に応じてアプリプレビューセットに追加され、`PRODUCT_PAGE_HEADER`、`APP_STORE_SEARCH_RESULTS`、`APP_IPHONE_DUO` はアセットライブラリを経由します。トリートメントのロケールは、最初のアップロード時に作成されます。

:::note
新しいトリートメントのロケールは、**元のページのメディアのコピー**から始まります。App Store Connect が現在のバージョンのスクリーンショットとプレビューでロケールを埋めるためです。アップロードしたメディアはそのコピーの後に追加されるので、置き換えるコピー済みのスクリーンショットは削除してください（ID は `media list` で確認できます）。
:::

## 審査、開始、停止

```bash
ascelerate experiments submit <bundle-id> "Screenshot order"
ascelerate experiments start <bundle-id> "Screenshot order"
ascelerate experiments stop <bundle-id> "Screenshot order"
```

新しいメディアを含むテストは、開始する前に App Review を受ける必要があります（`info` で確認できます）。`submit` はテストだけを含む審査提出を作成して提出します。そのプラットフォームに他の項目（アプリバージョンなど）を含む提出の下書きがすでにある場合は、テストがその提出に追加され、[`apps review submit`](apps.md#submit-for-review) を通じて他の項目と一緒に審査に送られます。テストが承認されたら、`start` で実行し、`stop` で終了します。結果は App Store Connect で確認できます。

## 更新と削除

```bash
ascelerate experiments update <bundle-id> "Screenshot order" --traffic 30
ascelerate experiments delete <bundle-id> "Screenshot order"
```

どの変更が違いを生んだのかが結果からわかるように、変更はトリートメントごとに1つ（たとえば最初のスクリーンショットだけ、またはアイコンだけ）にしてください。
