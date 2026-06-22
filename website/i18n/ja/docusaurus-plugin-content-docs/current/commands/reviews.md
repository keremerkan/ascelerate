---
sidebar_position: 13
title: カスタマーレビュー
---

# カスタマーレビュー

カスタマーレビューを表示し、デベロッパ返信を管理します。レビュー自体は読み取り専用で、**デベロッパ返信**の公開・置き換え・削除のみが行えます。

## 一覧

```bash
ascelerate reviews list <bundle-id>
ascelerate reviews list <bundle-id> --rating 1 --sort critical --unanswered --limit 20
ascelerate reviews list <bundle-id> --territory USA
```

テーブルにはレビューID、星評価、日付、地域、返信の有無、タイトルが表示されます。

- `--rating` — 星評価（1〜5）でフィルタリングします。
- `--territory` — レビューの地域コード（例：`USA`）でフィルタリングします。
- `--sort` — `recent`（デフォルト）、`oldest`、`critical`（評価の低い順）、`best`（評価の高い順）。
- `--unanswered` — 公開済みの返信がないレビューのみ。
- `--limit` — 表示するレビューの最大数（デフォルト50、最大200）。

## 詳細

```bash
ascelerate reviews info <review-id>
```

レビューの全文と、ある場合はデベロッパ返信を表示します。レビューIDは `reviews list` から取得できます。

## 返信

```bash
ascelerate reviews respond <review-id> --body "フィードバックありがとうございます。最新のアップデートで修正しました。"
```

デベロッパ返信を公開します。レビューにすでに返信がある場合は、確認のうえ置き換えられます。

## 返信の削除

```bash
ascelerate reviews delete-response <review-id>
```
