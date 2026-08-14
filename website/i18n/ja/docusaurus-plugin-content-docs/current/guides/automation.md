---
sidebar_position: 2
title: 自動化とCI/CD
---

# 自動化とCI/CD

確認プロンプトを表示するほとんどのコマンドは `--yes` / `-y` でプロンプトをスキップできるため、CI/CDパイプラインやスクリプトでの使用に適しています。

```bash
ascelerate apps build attach-latest <bundle-id> --yes
ascelerate apps review submit <bundle-id> --yes
```

:::warning
プロビジョニングコマンドで `--yes` を使用する場合、必要なすべての引数を明示的に指定する必要があります。インタラクティブモードは無効になります。
:::

## CIでのXcode署名

`builds archive` とアーカイブからIPAへのエクスポートの両方で、`xcodebuild` に `-allowProvisioningUpdates` を渡します。これがないと、`xcodebuild` はローカルにキャッシュされたプロビジョニングプロファイルのみを使用し、Developer Portalから更新されたものを取得しません。

Xcode GUIログインのないCI環境では、認証フラグを渡してください：

```bash
ascelerate builds archive \
  --authentication-key-path /path/to/AuthKey.p8 \
  --authentication-key-id YOUR_KEY_ID \
  --authentication-key-issuer-id YOUR_ISSUER_ID
```

## JSON出力 {#json-output}

読み取り系コマンドは `--json` をサポートしており、`jq`、スクリプト、AIエージェントでそのまま扱える機械可読な出力が得られます：

```bash
ascelerate apps list --json
ascelerate apps info <bundle-id> --json
ascelerate apps versions <bundle-id> --json
ascelerate apps review preflight <bundle-id> --json
ascelerate apps review status <bundle-id> --json
ascelerate builds list --bundle-id <bundle-id> --json
ascelerate testflight builds <bundle-id> --json
ascelerate testflight status <bundle-id> --json
ascelerate reviews list <bundle-id> --json
ascelerate reviews info <review-id> --json
ascelerate iap list <bundle-id> --json
ascelerate iap info <bundle-id> <product-id> --json
ascelerate iap pricing show <bundle-id> <product-id> --json
ascelerate sub groups <bundle-id> --json
ascelerate sub list <bundle-id> --json
ascelerate sub info <bundle-id> <product-id> --json
ascelerate sub pricing show <bundle-id> <product-id> --json
ascelerate rate-limit --json
```

出力の規約：

- 一覧系コマンドはトップレベルのJSON**配列**を、詳細系コマンドは単一の**オブジェクト**を出力します。
- 列挙値はAPIの生の定数（`WAITING_FOR_REVIEW`、`IOS`）、日付はISO 8601形式で、すべてのリソースに `id` が含まれます。
- nullのフィールドは省略され、結果が空の場合は文章ではなく `[]` が出力されます。
- 警告はブール値になります。`iap info` と `sub info` は警告メッセージの代わりに `"hasPricing": false` を報告します。
- `--json` は非インタラクティブモードを意味します。プロンプトを表示するはずのコマンド（例：該当するプラットフォームが複数ある場合）は代わりにエラーで終了するため、`--platform` などのフラグを指定して曖昧さを解消してください。
- エラーはstderrに出力されるため、stdoutは常に有効なJSONです。

例として、返信のないレビューの数を数えるには：

```bash
ascelerate reviews list <bundle-id> --json | jq '[.[] | select(.response == null)] | length'
```

## 終了コード

コマンドは失敗時にゼロ以外のステータスで終了するため、`set -e` や `&&` チェーンを使用するスクリプトで安全に使用できます。`preflight` コマンドはチェックが失敗するとゼロ以外で終了するため、提出のゲートとして使用できます：

```bash
ascelerate apps review preflight <bundle-id> && ascelerate apps review submit <bundle-id>
```

`--json` を指定すると、`preflight` は終了コードの動作をそのままに、構造化されたレポート（`{"passed": false, "checks": [{"group", "name", "passed", "detail"}]}`）を出力します。どのチェックが失敗したかを報告する必要があるCIゲートに最適です。
