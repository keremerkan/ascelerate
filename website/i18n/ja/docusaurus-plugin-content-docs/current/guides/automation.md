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

## ドライラン {#dry-run}

`--dry-run` を付けると、App Store Connect 上で何も変更せずに、コマンドやワークフロー全体を試せます。このオプションはコマンドラインのどこに置いても有効で、`ASCELERATE_DRY_RUN=1` を設定しても同じ効果があります。読み取りリクエストは通常どおり送信されるため、検索やチェックは実際のデータに対して行われますが、書き込みリクエストはすべて送信前に停止されます。ascelerate はそのリクエストのメソッド、パス、JSON ボディを stderr に出力し、リクエストが送信されなかったことを報告します。

```bash
ascelerate apps localizations import <bundle-id> --file localizations.json --yes --dry-run
ascelerate run-workflow release.txt --yes --dry-run
ASCELERATE_DRY_RUN=1 ascelerate run-workflow release.txt --yes   # 同じ効果（CI ジョブ全体に適用する場合など）
```

- コマンドは最初に停止された書き込みで終了します。項目を1つずつ処理するコマンドでは、停止された各リクエストを失敗として報告します。
- `media upload` は停止された書き込みを完了したものとして処理を続けるため、すべてのファイルの書き込みを確認できます。最後に、アップロードされるはずのファイル数を表示します。
- `run-workflow` では、書き込みが停止されたステップでワークフローは止まらないため、1回の実行ですべてのステップの書き込みを確認できます。ただし、前のステップで作成されるはずだったもの（新しいバージョンやアップロードされたビルドなど）に依存するステップは失敗することがあります。
- ワークフローファイルで1つのステップに `--dry-run` を付けた場合は、そのステップにのみ適用されます。
- `builds upload` はアップロードをスキップします。`builds archive` と `builds validate` は App Store Connect 上で何も変更しないため、通常どおり実行されます。

## API レート制限 {#rate-limit}

App Store Connect では、API キーごとに1時間あたり 3,600 件の API リクエストが許可され、直近1時間の移動枠で数えられます。長いコマンド（大量のメディアのアップロード、ライブラリの整理、価格のインポートなど）がこれを使い切ると、ascelerate は App Store Connect が再びリクエストを受け付けるまで待ち、再開する時刻を表示してから処理を続けます。止めたいときは Ctrl-C を押してください。

CI では待つより失敗させたい場合があります。`ASCELERATE_MAX_RATE_LIMIT_WAIT` に、1回の実行で待ってよい合計秒数を設定してください（`0` にすると、最初に制限されたリクエストで失敗します）。

```bash
ASCELERATE_MAX_RATE_LIMIT_WAIT=600 ascelerate run-workflow release.txt --yes
```

`ascelerate rate-limit` は残りのリクエスト数を表示します。このコマンドは待ちません。

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
