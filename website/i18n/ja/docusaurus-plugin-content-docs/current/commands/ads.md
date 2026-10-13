---
sidebar_position: 21
title: Apple Ads
---

# Apple Ads

Apple Ads Platform API を通じて、Apple Ads（旧 Search Ads）のキャンペーンをコマンドラインから管理します。パフォーマンスレポート、キャンペーン、広告グループ、キーワードと除外キーワード、入札額と予算、Apple の推奨事項、キーワード調査データを扱えます。アプリは App Store Connect と照合されるため、`--app` には他のコマンドと同じ Bundle ID や[エイリアス](../getting-started/aliases.md)を指定できます。キャンペーンと広告グループは**名前**（大文字と小文字を区別しません）または ID で指定します。名前が間違っている場合は、有効な名前が一覧表示されます。

変更を加えるコマンドはすべて、実行前に確認を求めます（`-y` でスキップできます）。`--dry-run` を付けると、実際に送信せずに正確なリクエスト内容を表示します（[ドライラン](../guides/automation.md#dry-run)）。変更には実際の費用がかかるため、まず `--dry-run` で試してください。金額は広告アカウントの通貨で指定します。

## セットアップ

Apple Ads では、App Store Connect の API キーとは別の認証情報を使用します。

1. Apple Ads で **アカウント設定 → ユーザー管理** に移動し、**API** ロール（API アカウントマネージャなど）を持つユーザーを招待して、そのユーザーの Apple Account で招待を承認します。
2. セットアップを実行します。

```bash
ascelerate ads configure
```

ascelerate がキーペアを作成し、公開鍵を表示します。API ユーザーとして Apple Ads にサインインし、**アカウント設定 → API** に公開鍵を貼り付けて、そこに表示されるクライアント ID、チーム ID、キー ID を入力してください。続いて ascelerate がそのユーザーがアクセスできる広告アカウントを一覧表示し、選択したアカウントを `~/.ascelerate/config.json` の `ads` セクションに保存します。`--new-key` を指定すると新しいキーペアを作成します。

```bash
ascelerate ads accounts          # API ユーザーの広告アカウントとロール
```

## レポート

```bash
ascelerate ads reports campaigns --days 30
ascelerate ads reports campaigns --from 2026-09-01 --to 2026-09-30 --app myapp
ascelerate ads reports campaigns --campaign "MyApp US" --by device
ascelerate ads reports adgroups --campaign "MyApp US"
ascelerate ads reports ads --campaign "MyApp US"
ascelerate ads reports keywords --campaign "MyApp US"
ascelerate ads reports search-terms --app myapp --days 14
```

| レポート | 行の単位 |
|---|---|
| `campaigns` | キャンペーン。`--by age gender device country region city` で内訳を表示します |
| `adgroups` | 広告グループ（テスト用の広告グループの比較などに） |
| `ads` | 広告、つまり各広告グループのタップの送り先となるプロダクトページ |
| `keywords` | キーワード。Apple の推奨入札額も表示します |
| `search-terms` | 実際に検索された語句、該当したキーワード、そしてそれがお使いのキーワードと検索マッチのどちらによるものか |

すべてのレポートで、`--days N`（今日を含む）または `--from`/`--to`、`--app`、`--campaign`、`--all`（アクティビティのない行も含める）、`--json` を指定できます。日付は広告アカウントのタイムゾーンに基づきます。判断を下す際は、丸1日分のデータ同士を比較してください。今日の数値はまだ集計途中です。

各行には、支出額、インプレッション、タップ、インストール、タップスルー率（TTR）、平均タップ単価（CPT）、平均インストール単価（CPI）と、2種類のコンバージョン率が表示されます。

- **CR (Tap)**：タップ後のインストール数をタップ数で割った値です。タップしたユーザーを、プロダクトページがどれだけインストールにつなげているかを示します。
- **CR (Total)**：ビュースルーインストール（広告を見たユーザーが、タップせずに後からインストールしたもの）を含むすべてのインストール数をタップ数で割った値です。100% を超えることもあります。

:::note
Apple が年齢、性別、国より細かい地域を把握できるのは、パーソナライズされた広告を許可したユーザーについてのみです。そのため、これらの内訳はほぼすべて「Unknown」になります。デバイス別の内訳は完全です。Apple がプライバシー保護のために伏せている検索語句は「(low volume)」と表示されます。
:::

## キャンペーン

```bash
ascelerate ads campaigns list --app myapp
ascelerate ads campaigns pause "MyApp US"
ascelerate ads campaigns resume "MyApp US"
ascelerate ads campaigns budget "MyApp US" --daily 120
ascelerate ads campaigns bid "MyApp US Max Conv" --amount 2.50
```

`list` は、各キャンペーンのステータス、国または地域、1日の予算、入札方式（Manual CPT または Max Conversions）を表示します。Max Conversions キャンペーンでは、`bid` で1回のオークションで支払う上限額を設定します。この上限は、1件のインストールが自分にとってどれだけの価値があるかを基準に決めてください。その国や地域での通常のタップ単価を下回る上限を設定すると、キャンペーンにほとんど配信されなくなります。

### キャンペーンの作成

```bash
ascelerate ads campaigns create --like "MyApp US" --name "MyApp US Max Conv" --max-conversions --bid 2.50 --daily 25
ascelerate ads campaigns create --app myapp --name "MyApp DE" --country DE --daily 20 --default-bid 1.00 --search-match off
```

キャンペーンは広告グループとともに**一時停止**の状態で作成されます。広告グループは、Max Conversions の場合は自動のもの、`--default-bid` を指定した場合は手動のものになります。`--like` を指定すると、既存のキャンペーンのアプリ、国または地域、設定をコピーします。`--enabled` を指定すると、すぐに配信を開始します。

```bash
ascelerate ads campaigns target-cpa --app myapp --country US
```

新しい Max Conversions キャンペーンについて、Apple が推奨する目標インストール単価を表示します。

:::tip
同じストアフロントにある同じアプリのキャンペーン同士は競合しません。Apple は各オークションにそのうち1つしか参加させないためです。そのため、配信中のキャンペーンと並べて新しいキャンペーンを作成しても、残りのトラフィックしか得られません。新しいキャンペーンをテストするには、既存のキャンペーンをブランド名に限定するなどして、トラフィックを新しいキャンペーンに移してください。
:::

## 広告グループ

```bash
ascelerate ads adgroups --campaign "MyApp US"
ascelerate ads adgroups create --campaign "MyApp US" --name "Exact" --search-match off
ascelerate ads adgroups create --campaign "MyApp US" --name "Adults" --like "US Ad Group" --min-age 25
ascelerate ads adgroups update "Exact" --campaign "MyApp US" --default-bid 1.20
ascelerate ads adgroups pause "Exact" --campaign "MyApp US"
ascelerate ads adgroups resume "Exact" --campaign "MyApp US"
```

`create` は、既存の広告グループ（`--like` で指定したもの、またはキャンペーン内の唯一の広告グループ）の課金方式、入札設定、ターゲティングをコピーし、`--enabled` を指定しない限り**一時停止**の状態で作成します。`--min-age`/`--max-age` では 18 歳から 64 歳までの年齢を指定できます（`--max-age` を省略すると 65 歳以上も対象になります）。年齢ターゲティングが届くのはパーソナライズされた広告を許可したユーザーのみです。また、Apple は年齢をターゲットにした広告グループからのインストールを、他のツールではキャンペーンに帰属させません。そのため、こうした広告グループは Apple Ads 上の数値で評価してください。

## キーワードと除外キーワード

```bash
ascelerate ads keywords list --campaign "MyApp US"
ascelerate ads keywords add --campaign "MyApp US" --match exact --bid 1.50 "qr scanner" "barcode reader"
ascelerate ads keywords bid --campaign "MyApp US" --bid 1.25 "qr scanner"
ascelerate ads keywords pause --campaign "MyApp US" "barcode reader"
ascelerate ads keywords copy --campaign "MyApp US" --from "US Ad Group" --to "Exact"

ascelerate ads negatives list --campaign "MyApp US"
ascelerate ads negatives add --campaign "MyApp US" "free wifi"
ascelerate ads negatives add --campaign "MyApp US" --ad-group "Discovery" --match broad "wifi"
ascelerate ads negatives remove --campaign "MyApp US" "free wifi"
```

キャンペーンに複数の広告グループがある場合は、`--ad-group` で広告グループを指定します。除外キーワードは、`--ad-group` を指定しない限りキャンペーン単位で、`--match broad` を指定しない限り完全一致で追加されます。`keywords add` は既存のキーワードをスキップします。Max Conversions キャンペーンは入札額を自動で決めるため、キーワードの入札額は適用されません。

## 何を変更すべきか

```bash
ascelerate ads opportunities --app myapp
ascelerate ads opportunities --campaign "MyApp US" --days 60 --min-taps 20 --brand "my app"
```

`opportunities` は、キャンペーンの検索語句（デフォルトでは直近30日間の丸1日分のデータ）を、そのキャンペーンのキーワードや平均値と比較し、次のような提案を行います。

- **完全一致キーワードとして追加**：コンバージョンにつながっているのに専用の完全一致キーワードがなく、インストール単価も良好な検索語句。
- **専用の入札額を設定**：コンバージョンにつながっているものの、別のキーワードの入札額に乗ってより高いコストがかかっている語句。
- **除外**：実際に費用がかかっているのにインストールがない語句、またはコストやコンバージョン率が大幅に悪い語句。

アプリ名での検索は平均値の計算から除外され、除外キーワードとして提案されることもありません。ブランド名の別の表記は `--brand` で追加してください。結果はあくまで候補として扱い、実行する前に各語句がアプリに関連しているかを確認してください。

```bash
ascelerate ads recommendations
ascelerate ads recommendations apply <id>
ascelerate ads recommendations dismiss <id>
```

Apple の未対応の推奨事項（1日の予算や目標 CPA の変更）を、見込まれる効果とともに表示します。

```bash
ascelerate ads history --app myapp --days 7
```

直近6か月間にキャンペーン、広告グループ、キーワード、除外キーワードに加えられたすべての変更を、変更前と変更後の値とともに表示します。Apple Ads のウェブサイトで行った変更や Apple による変更も含まれます。パフォーマンスの変化を読み解く前に確認しておくと便利です。

## キーワード調査

```bash
ascelerate ads keywords suggest --app myapp --seed "qr code" "barcode" --country US GB
ascelerate ads keywords popularity --app myapp --country US --term "qr code" "qr scanner"
ascelerate ads keywords popularity --genre PRODUCTIVITY_UTILITIES --country US --contains scanner
ascelerate ads insights impression-share --app myapp --country US --weeks 4
```

- `suggest` は、指定したシード語句をもとに Apple が提案するキーワードを、その人気度と、すでにどこでターゲットにしているかとともに返します。
- `popularity` は、ストアフロントにおける検索語句の人気度（1〜100）と、アプリのジャンル内での人気度を表示します。ジャンルのランキングリストに含まれない語句は別に表示されます。
- `impression-share` は、広告が表示された検索語句について、広告インプレッションのシェアと順位を表示します。人気がありコンバージョンにつながる語句でシェアが低ければ伸びしろがあり、自社のブランド名でシェアが 100% を下回っていれば競合他社がその語句に入札しています。

人気度のデータは、App Store のキーワード（ASO）選びにも役立ちます。

## 広告とカスタムプロダクトページ

```bash
ascelerate ads product-pages --app myapp
ascelerate ads ads --campaign "MyApp US"
ascelerate ads ads create --campaign "MyApp US" --ad-group "Scanner" --product-page "Scanner Page" --enabled
ascelerate ads ads pause "Scanner Page ad" --campaign "MyApp US"
```

広告は、広告グループのタップをプロダクトページに送ります。独自の広告がない広告グループでは、デフォルトのプロダクトページが使われます。特定のニーズに関する検索を[カスタムプロダクトページ](product-pages.md)に送るには、その検索用に専用の広告グループを作成し（`adgroups create`、`keywords add`）、その広告グループに広告を作成します。1つの広告グループで配信される広告は1つだけなので、`--enabled` を指定すると、それまで配信されていた広告が一時停止されます。新しい広告は Apple の審査を受けます。審査状況は `ads ads` で確認できます。

## AI エージェントとの併用

[ascelerate スキル](../guides/ai-skill.md)は、これらのレポートの読み方と変更を提案すべきタイミングを AI コーディングエージェントに教えます。そのため、複数のアプリにまたがるキャンペーンのレビュー、追加または除外すべきキーワードの発見、パフォーマンスの変化の説明などをエージェントに依頼できます。すべてのコマンドが `--json` に対応しており、エージェントには、提案する変更を提示し、何かを送信する前に `--dry-run` を使用するよう指示されています。
