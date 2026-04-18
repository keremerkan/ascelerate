---
sidebar_position: 7
title: サブスクリプション
---

# サブスクリプション

## 一覧と詳細

```bash
ascelerate sub groups <bundle-id>
ascelerate sub list <bundle-id>
ascelerate sub info <bundle-id> <product-id>
```

## サブスクリプションの作成、更新、削除

```bash
ascelerate sub create <bundle-id> --name "Monthly" --product-id <product-id> --period ONE_MONTH --group-id <group-id>
ascelerate sub update <bundle-id> <product-id> --name "Monthly Plan"
ascelerate sub delete <bundle-id> <product-id>
```

## サブスクリプショングループ

```bash
ascelerate sub create-group <bundle-id> --name "Premium"
ascelerate sub update-group <bundle-id> --name "Premium Plus"
ascelerate sub delete-group <bundle-id>
```

## 審査への提出

```bash
ascelerate sub submit <bundle-id> <product-id>
```

## サブスクリプションのローカライゼーション

```bash
ascelerate sub localizations view <bundle-id> <product-id>
ascelerate sub localizations export <bundle-id> <product-id>
ascelerate sub localizations import <bundle-id> <product-id> --file sub-de.json
```

## グループのローカライゼーション

```bash
ascelerate sub group-localizations view <bundle-id>
ascelerate sub group-localizations export <bundle-id>
ascelerate sub group-localizations import <bundle-id> --file group-de.json
```

インポートコマンドは、存在しないロケールを確認のうえ自動的に作成するため、App Store Connectにアクセスせずに新しい言語を追加できます。

## 価格設定

サブスクリプションの価格設定は地域ごとに行われます。アプリ内課金のような自動均等化の概念はないため、価格を設定したい各地域に独自のレコードが必要です。CLIでは単一の地域の価格を設定するか、Appleの現地通貨価格層を使用してすべての地域に価格を展開することができます。

```bash
# 現在の地域別価格を表示（存在しない場合は警告）
ascelerate sub pricing show <bundle-id> <product-id>

# ある地域で利用可能な価格層を一覧表示
ascelerate sub pricing tiers <bundle-id> <product-id> --territory USA

# 単一地域の価格を設定
ascelerate sub pricing set <bundle-id> <product-id> --price 4.99 --territory USA

# すべての地域に価格を展開（地域ごとに1回のPOST）
ascelerate sub pricing set <bundle-id> <product-id> --price 4.99 --equalize-all-territories
```

### 価格変更と既存サブスクライバー

Appleは、価格変更の方向によって既存サブスクライバーへの扱いを変えます。`sub pricing set` は影響を受ける各地域の現在の価格を取得し、変更を分類して、適切な動作を強制します。

- **値下げ**: 既存サブスクライバーは自動的に低い価格に移行します。インタラクティブな実行では警告とともに確認を求めます。`--yes` モードでは、収益への影響を確認するために `--confirm-decrease` を追加する必要があります — `--yes` だけでは不十分です。
- **値上げ**: 既存サブスクライバーをどのように扱うかを明示的に選択する必要があります。以下のいずれかが設定されない限り、コマンドはエラーになります：
  - `--preserve-current` — 既存サブスクライバーを以前の価格のまま維持
  - `--no-preserve-current` — Appleの通知期間後に既存サブスクライバーに新しい価格を適用
- **新規地域**（既存価格なし）: 考慮すべき既存サブスクライバーはなく、フラグは任意です。
- **変更なし**: 何もせずスキップされます。

`--equalize-all-territories` でも同じルールが集約的に適用されます。展開先の地域のいずれかが値上げの場合、保持フラグはすべてに対して必要です。`--yes` モードで値下げが含まれる場合、`--confirm-decrease` が必要です。

```bash
# 標準的なグローバル値上げ: すべての地域で $4.99 → $9.99、
# 既存サブスクライバーは旧価格のまま
ascelerate sub pricing set myapp com.example.monthly \
  --price 9.99 --territory USA --equalize-all-territories \
  --preserve-current
```

## 地域別の利用可否

各サブスクリプションは、アプリとは独立した独自の地域別利用可否を持ちます。デフォルトではサブスクリプションはアプリの地域を継承しますが、`sub availability` で変更を加えると、サブスクリプションに明示的なリストが作成されます。

```bash
ascelerate sub availability <bundle-id> <product-id>
ascelerate sub availability <bundle-id> <product-id> --add CHN,RUS
ascelerate sub availability <bundle-id> <product-id> --remove ITA
ascelerate sub availability <bundle-id> <product-id> --available-in-new-territories true
```

## 導入オファー

導入オファーは**新規サブスクライバー**を対象とします — 無料トライアルおよび導入時の割引です。

```bash
ascelerate sub intro-offer list <bundle-id> <product-id>

# 無料トライアル（価格不要；--periods と --duration で期間を設定）
ascelerate sub intro-offer create <bundle-id> <product-id> \
  --mode FREE_TRIAL --duration ONE_WEEK --periods 1

# Pay-as-you-go割引（3ヶ月、月額$0.99、USA限定）
ascelerate sub intro-offer create <bundle-id> <product-id> \
  --mode PAY_AS_YOU_GO --duration ONE_MONTH --periods 3 \
  --territory USA --price 0.99

# 終了日のみを更新（他のフィールドは削除＋再作成が必要）
ascelerate sub intro-offer update <bundle-id> <product-id> <offer-id> --end-date 2026-12-31

ascelerate sub intro-offer delete <bundle-id> <product-id> <offer-id>
```

モード：`FREE_TRIAL`、`PAY_AS_YOU_GO`、`PAY_UP_FRONT`。`--territory` を指定しない場合、オファーはグローバルに適用されます。指定すると、その1つの地域のみに限定されます。`--price` は2つの有料モードでは必須で、`FREE_TRIAL` では使用できません。

## プロモーションオファー

プロモーションオファーは**既存サブスクライバー**を対象とします — 通常はアプリ内のアップセルフローで使用されます。`--code` の値（オファーコード）は、クライアントがオファーを利用する前に、サーバーが実行時に生成する署名付きペイロードに埋め込まれている必要があります。

```bash
ascelerate sub promo-offer list <bundle-id> <product-id>
ascelerate sub promo-offer info <bundle-id> <product-id> <offer-id>

# 作成 — 単一地域または --equalize-all-territories パターンを使用
ascelerate sub promo-offer create <bundle-id> <product-id> \
  --name "Loyalty 50%" --code LOYALTY50 \
  --mode PAY_AS_YOU_GO --duration ONE_MONTH --periods 3 \
  --price 4.99 --territory USA --equalize-all-territories

# 価格のみを更新（他のフィールドは削除＋再作成が必要）
ascelerate sub promo-offer update <bundle-id> <product-id> <offer-id> \
  --price 5.99 --equalize-all-territories

ascelerate sub promo-offer delete <bundle-id> <product-id> <offer-id>
```

## オファーコード

サブスクリプション用の引換可能コードで、2種類あります：

- **ワンタイムユースコード**：Appleが非同期でN個の一意のコードをバッチで生成します。
- **カスタムコード**：開発者が指定する文字列で、N回まで使用可能です。

```bash
ascelerate sub offer-code list <bundle-id> <product-id>
ascelerate sub offer-code info <bundle-id> <product-id> <offer-code-id>

# オファーコードを作成（すべてのオファー属性を含む）
ascelerate sub offer-code create <bundle-id> <product-id> \
  --name "Launch Free Month" \
  --eligibility NEW \
  --offer-eligibility STACK_WITH_INTRO_OFFERS \
  --mode FREE_TRIAL --duration ONE_MONTH --periods 1 \
  --price 0 --territory USA --equalize-all-territories

ascelerate sub offer-code toggle <bundle-id> <product-id> <offer-code-id> --active true

# ワンタイムユースコードを生成（非同期）
ascelerate sub offer-code gen-codes <bundle-id> <product-id> <offer-code-id> \
  --count 500 --expires 2026-12-31

# 生成完了後に実際のコード値を取得
ascelerate sub offer-code view-codes <one-time-use-batch-id> --output codes.txt

# 開発者指定のカスタムコードを追加
ascelerate sub offer-code add-custom-codes <bundle-id> <product-id> <offer-code-id> \
  --code SUBPROMO --count 1000 --expires 2026-12-31
```

サブスクリプションオファーコードの顧客対象：`NEW`、`EXISTING`、`EXPIRED`。オファー対象：`STACK_WITH_INTRO_OFFERS` または `REPLACE_INTRO_OFFERS`。

## サブスクリプショングループを審査に提出

サブスクリプショングループは次のアプリバージョンと一緒に審査されます。`sub submit-group` は `sub submit` のグループレベルに相当します。

```bash
ascelerate sub submit-group <bundle-id>
```

## プロモーション画像

App Storeでサブスクリプションと並んで表示されるプロモーション画像をアップロードします。

```bash
ascelerate sub images list <bundle-id> <product-id>
ascelerate sub images upload <bundle-id> <product-id> ./hero.png
ascelerate sub images delete <bundle-id> <product-id> <image-id>
```

## App Reviewスクリーンショット

各サブスクリプションは最大1つのApp Reviewスクリーンショットを持つことができます。アップロードすると既存のスクリーンショットが置き換えられます。

```bash
ascelerate sub review-screenshot view <bundle-id> <product-id>
ascelerate sub review-screenshot upload <bundle-id> <product-id> ./review.png
ascelerate sub review-screenshot delete <bundle-id> <product-id>
```

画像およびスクリーンショットのアップロードはAppleの3ステップフローを使用します（予約 → チャンクをPUT → MD5でコミット）。単一の `upload` 呼び出しで3つのステップすべてを処理します。

## ウィンバックオファー（未実装）

ウィンバックオファー（解約したサブスクライバー向けのオファー）は意図的にまだ実装されていません。`asc-swift` 依存関係の `WinBackOfferPriceInlineCreate` 型には、APIが必要とする `territory` および `subscriptionPricePoint` の関係が含まれていないため、有効な作成リクエストを構築できません。依存関係が更新されたら再検討します。
