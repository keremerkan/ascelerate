---
sidebar_position: 13
title: Customer Reviews
---

# Customer Reviews

View customer reviews and manage developer responses. Reviews themselves are read-only — you can only publish, replace, or delete the **developer response**.

## List

```bash
ascelerate reviews list <bundle-id>
ascelerate reviews list <bundle-id> --rating 1 --sort critical --unanswered --limit 20
ascelerate reviews list <bundle-id> --territory USA
```

The table shows the review ID, star rating, date, territory, whether it has a response, and the title.

- `--rating` — filter by star rating (1–5).
- `--territory` — filter by review territory code (e.g. `USA`).
- `--sort` — `recent` (default), `oldest`, `critical` (lowest rating first), or `best` (highest first).
- `--unanswered` — only reviews without a published response.
- `--limit` — maximum number to show (default 50, max 200).
- `--json` — machine-readable output including the **full review bodies and developer responses**, so no per-review `info` calls are needed ([conventions](../guides/automation.md#json-output)).

## Details

```bash
ascelerate reviews info <review-id>
```

Shows the full review body and the developer response (if any). Review IDs come from `reviews list`. Accepts `--json` as well, emitting the same shape as one `reviews list --json` element.

## Respond

```bash
ascelerate reviews respond <review-id> --body "Thanks for the feedback! We've fixed this in the latest update."
```

Publishes a developer response. If the review already has a response, it is replaced (after confirmation).

## Delete a response

```bash
ascelerate reviews delete-response <review-id>
```
