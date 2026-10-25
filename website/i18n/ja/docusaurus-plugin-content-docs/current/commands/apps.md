---
sidebar_position: 1
title: アプリ
---

# アプリ

## アプリ一覧

```bash
ascelerate apps list
```

## アプリ詳細

```bash
ascelerate apps info <bundle-id>
```

## バージョン一覧

```bash
ascelerate apps versions <bundle-id>
```

`apps list`、`apps info`、`apps versions` はいずれも、機械可読な出力のための `--json` を受け付けます（[規約](../guides/automation.md#json-output)）。

## バージョンの作成

```bash
ascelerate apps create-version <bundle-id> <version-string>
ascelerate apps create-version <bundle-id> 2.1.0 --platform ios --release-type manual
```

`--release-type` はオプションです。省略した場合、前のバージョンの設定が使用されます。

:::note ユニバーサル購入
ユニバーサル購入のアプリ（iOS、macOS、tvOS、visionOSにまたがる1つのApp Storeレコード）では、同じバージョン文字列がプラットフォームごとに1つずつ存在できます。`create-version` と `review submit` はデフォルトでiOSを対象とするため、別のプラットフォームを対象にするには `--platform macos`（または `tvos`、`visionos`）を指定してください。バージョンを対象とするその他のコマンド（ローカライゼーション、メディア、ビルドの添付、review preflight/info/attachments/resolve-issues/cancel-submission、段階的リリース、手動リリース）もオプションの `--platform` を受け付けます。省略した場合、バージョン（またはアクティブな審査提出）が複数のプラットフォームに該当するときに選択を求められます。`--yes` 指定時は選択を求める代わりに、ヒントを表示して中止します。
:::

## 著作権表示

```bash
ascelerate apps copyright <bundle-id>
ascelerate apps copyright <bundle-id> --set "2026 Your Name" --version 2.1.0 --platform macos
```

`--set` を省略すると、現在の著作権表示が表示されます。更新するには、バージョンが編集可能な状態である必要があります。

## レビュー

### レビューステータスの確認

```bash
ascelerate apps review status <bundle-id>
ascelerate apps review status <bundle-id> --version 2.1.0
```

`--json` を追加すると、提出内容を項目ごとの状態を含めて機械可読なJSONとして取得できます。

### 審査への提出 {#submit-for-review}

```bash
ascelerate apps review submit <bundle-id>
ascelerate apps review submit <bundle-id> --version 2.1.0
ascelerate apps review submit <bundle-id> --platform macos
```

提出時に、保留中の変更があるIAPやサブスクリプションを自動検出し、アプリバージョンと一緒に提出するか確認します。保留中の変更は各プロダクトのバージョン履歴（「Prepare for Submission」「Ready for Review」または却下状態のバージョン）から読み取るため、スクリーンショットのみの変更も検出されます。`apps review status` は、進行中の提出に含まれる項目を、対応するアプリバージョンまたはプロダクトに解決して表示します。

### リジェクトされた項目の解決

問題を修正してResolution Centerで返信した後：

```bash
ascelerate apps review resolve-issues <bundle-id>
```

### 提出のキャンセル

```bash
ascelerate apps review cancel-submission <bundle-id>
```

### App審査に関する情報

App審査に提供する連絡先情報、デモアカウント、メモを表示または更新します。フラグを指定しない場合は現在の値が表示されます。フィールドのフラグを指定するとその項目が更新されます（指定しないフィールドは変更されません）。

```bash
ascelerate apps review info <bundle-id>
ascelerate apps review info <bundle-id> --contact-email you@example.com --demo-account-name reviewer --demo-account-password "hunter2" --demo-account-required true --notes "テスト手順…"

# 添付ファイル（デモ動画、書類など）
ascelerate apps review attachment list <bundle-id>
ascelerate apps review attachment upload <bundle-id> demo.mp4
ascelerate apps review attachment delete <attachment-id>
```

## プリフライトチェック

審査に提出する前に `preflight` を実行して、すべてのロケールで必須フィールドが入力されていることを確認します：

```bash
# 最新の編集可能なバージョンを確認
ascelerate apps review preflight <bundle-id>

# 特定のバージョンを確認
ascelerate apps review preflight <bundle-id> --version 2.1.0
```

バージョンの状態とビルド（処理済みで、輸出コンプライアンスに回答済み）、著作権、App Reviewの連絡先とサインイン、アプリのプライマリカテゴリ、コンテンツ配信権、価格、配信状況を確認します。続いて各言語について、アプリ情報（名前と、主要言語ではプライバシーポリシーURL）、バージョンのテキスト（すべての言語の説明文とキーワード、主要言語のサポートURL）、スクリーンショットを確認します。独自のスクリーンショットがない言語ではApp Storeに主要言語のスクリーンショットが表示されるため、スクリーンショットが必要なのは主要言語だけです：

```
Preflight checks for MyApp v2.1.0 (Prepare for Submission)

Check                                Status
──────────────────────────────────────────────────────────────────
Version state                        ✓ Prepare for Submission
Build attached                       ✓ Build 42
Copyright                            ✓ 2026 Your Name
Review contact                       ✓ Jane Doe, jane@example.com
Sign-in                              ✓ Not required
Category                             ✓ Productivity
Content rights                       ✓ Does Not Use Third Party Content
Price                                ✓ Set
Availability                         ✓ 175 territories

en-US (English (United States))
  App info                           ✓ All fields filled
  Localizations                      ✓ All fields filled
  Screenshots                        ✓ 2 sets, 10 screenshots

de-DE (German (Germany))
  App info                           ✓ All fields filled
  Localizations                      ✗ Missing: Keywords, What's New
  Screenshots                        ✓ None (uses en-US's)
──────────────────────────────────────────────────────────────────
Result: 14 passed, 1 failed
```

App 内課金とサブスクリプションは、価格と、提出に含められる状態かどうかを確認します。販売を停止した商品（Developer Removed from Sale）はスキップ（–）として表示され、チェックの失敗にはなりません。結果行では別に数えられます。

新機能は、同じプラットフォームのバージョンがすでにリリースされているアップデートの場合にのみ確認されます。別のプラットフォームでのリリースは数えないため、iOSアプリの最初のMacバージョンには不要です。

チェックが失敗するとゼロ以外の終了コードを返すため、CIパイプラインやワークフローファイルでの使用に適しています。`--json` を指定すると、終了コードの動作はそのままに、テーブルの代わりに構造化されたレポート（`passed` ブール値と、チェックごとのエントリ：`group`、`name`、`passed`、`detail`）を出力するため、CIゲートでどのチェックが失敗したかを正確に報告できます。

## 段階的リリース

```bash
# 段階的リリースのステータスを確認
ascelerate apps phased-release <bundle-id>

# 段階的リリースを有効化（非アクティブで開始、バージョン公開時に有効化）
ascelerate apps phased-release <bundle-id> --enable

# 段階的リリースの一時停止、再開、完了
ascelerate apps phased-release <bundle-id> --pause
ascelerate apps phased-release <bundle-id> --resume
ascelerate apps phased-release <bundle-id> --complete

# 段階的リリースを完全に削除
ascelerate apps phased-release <bundle-id> --disable
```

## 手動リリース

バージョンのリリースオプションが手動に設定されている場合、承認されたバージョンはリリースするまで「Pending Developer Release（デベロッパによるリリース待ち）」の状態のままになります：

```bash
# デベロッパによるリリース待ちのバージョンをリリース
ascelerate apps release <bundle-id>

# 特定のバージョンまたはプラットフォームを対象にする
ascelerate apps release <bundle-id> --version 2.1.0 --platform macos
```

## アクセシビリティの宣言

App Store には、アプリが対応しているアクセシビリティ機能が表示されます。この宣言はデバイスファミリーごとに行います。対象となる機能は、VoiceOver、音声コントロール、さらに大きな文字、ダークインターフェイス、色以外で区別、十分なコントラスト、視差効果を減らす、キャプション、オーディオ説明です。

```bash
# デバイスファミリーごとの宣言（下書きまたは公開済み）を表示
ascelerate apps accessibility <bundle-id>

# iPhone でアプリが対応している機能を宣言して公開
ascelerate apps accessibility set <bundle-id> --device iphone --supports voiceover,larger-text,dark-interface --publish

# 下書きの宣言をそのまま公開
ascelerate apps accessibility publish <bundle-id>
```

`set` は対応する機能の完全なリストを宣言します。指定しなかった機能は非対応として宣言されます（`--supports none` を指定すると、どの機能にも対応していないと宣言します）。デバイスファミリー：`iphone`、`ipad`、`mac`、`apple-tv`、`apple-watch`、`vision`。`--publish` を指定しない場合、宣言は下書きのままになります。変更した宣言を公開すると、公開済みの宣言が置き換えられます。`--all` を指定すると、置き換えられた宣言も一覧に表示されます。アプリの一般的な操作全体を通じてユーザーが確実に利用できる機能だけを宣言してください。

## 販売地域の管理

```bash
# アプリが利用可能な地域を確認
ascelerate apps availability <bundle-id>

# 完全な国名を表示
ascelerate apps availability <bundle-id> --verbose

# 地域の追加・削除
ascelerate apps availability <bundle-id> --add CHN,RUS
ascelerate apps availability <bundle-id> --remove CHN
```

## アプリの価格

```bash
# ベース価格、手動で設定した価格、予定されている変更（--all：すべての地域、--json）
ascelerate apps pricing <bundle-id>
ascelerate apps pricing tiers <bundle-id> --territory USA

# ベース価格を今すぐ、または指定日から変更（ベース地域の通貨、無料は0）
ascelerate apps pricing set <bundle-id> --price 0.99
ascelerate apps pricing set <bundle-id> --price 1.99 --start-date 2026-12-01

# 手動価格：1つの地域に設定、Appleの現在の価格を手動で固定、またはAppleの価格に戻す
ascelerate apps pricing override <bundle-id> --territory FRA --price 0.99
ascelerate apps pricing keep <bundle-id> --territories all
ascelerate apps pricing remove <bundle-id> --territories FRA,DEU

# 一時的な価格変更（セール）と、予定された変更の取り消し
ascelerate apps pricing sale <bundle-id> --territories all --price 0.49 --start-date 2026-12-20 --end-date 2026-12-27
ascelerate apps pricing cancel <bundle-id> --territory USA --start-date 2026-12-01

# 価格スケジュールを別のアプリにコピー（iap pricing exportと同じ形式）
ascelerate apps pricing export <bundle-id> --output prices.json
ascelerate apps pricing import <other-bundle-id> --file prices.json
```

Appleはベース価格から他の地域の価格を算出し、税や為替レートの変動に応じて調整することがあります。手動で設定した価格は変わりません。複数の地域を指定した場合、`sale`はベース地域の通貨で価格を受け取り、ほかの地域にはAppleの同等価格を適用します。期間が終わると、各地域で以前の価格に戻ります。`import`は価格スケジュール全体を置き換えます。

## 暗号化宣言

```bash
# 既存の暗号化宣言を確認
ascelerate apps encryption <bundle-id>

# 新しい暗号化宣言を作成
ascelerate apps encryption <bundle-id> --create --description "Uses HTTPS for API communication"
ascelerate apps encryption <bundle-id> --create --description "Uses AES encryption" --proprietary-crypto --third-party-crypto
```

## EULA

```bash
# 現在のEULAを確認（標準のApple EULAが適用されているか確認）
ascelerate apps eula <bundle-id>

# テキストファイルからカスタムEULAを設定
ascelerate apps eula <bundle-id> --file eula.txt

# カスタムEULAを削除（標準のApple EULAに戻す）
ascelerate apps eula <bundle-id> --delete
```

## サブスクリプションの猶予期間

猶予期間により、更新支払いが失敗した場合にAppleが再請求を試みている間、サブスクライバーが短期間アクセスを保持できます。この設定はアプリ全体に適用されます。

```bash
# 現在の設定を表示
ascelerate apps subscription-grace-period <bundle-id>

# 本番環境で16日間の猶予期間を有効化、すべての更新に適用
ascelerate apps subscription-grace-period <bundle-id> \
  --opt-in true --duration SIXTEEN_DAYS --renewal-type ALL_RENEWALS

# サンドボックステストのみ（本番環境は無効のまま）
ascelerate apps subscription-grace-period <bundle-id> \
  --sandbox-opt-in true --duration THREE_DAYS --renewal-type ALL_RENEWALS
```

`--duration` の有効な値：`THREE_DAYS`、`SIXTEEN_DAYS`、`TWENTY_EIGHT_DAYS`。`--renewal-type` の有効な値：`ALL_RENEWALS`、`PAID_TO_PAID_ONLY`。

サンドボックスを無効にしたまま本番環境だけを有効にすることはできません。`--opt-in` を有効にするとサンドボックスも有効になり、指定がなければ期間は16日、対象はすべての更新になります。両方を無効にすると期間と更新タイプは消去されます。

## 合理化された購入（Streamlined Purchasing）

合理化された購入により、顧客はApp Storeの製品ページなど、アプリの外でアプリのサブスクリプションを購入できます。デフォルトで有効で、アプリのすべてのサブスクリプションに適用されます。Appleが無効化を認めるのは、最後に承認されたビルドがStoreKitの `PurchaseIntent` APIを使用しているアプリだけです。その場合、顧客はアプリ内で登録します。

```bash
# 表示
ascelerate apps streamlined-purchasing <bundle-id>

# 無効化
ascelerate apps streamlined-purchasing <bundle-id> --enabled false
```
