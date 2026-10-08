---
sidebar_position: 4
title: スクリーンショットとプレビュー
---

# スクリーンショットとアプリプレビュー

## ダウンロード

```bash
ascelerate apps media download <bundle-id>
ascelerate apps media download <bundle-id> --folder my-media/ --version 2.1.0
ascelerate apps media download <bundle-id> --locale en-US,tr
```

デフォルトでは `<bundle-id>-media/` にダウンロードされ、アップロードで使用されるのと同じフォルダ構造が使用されます。

`--locale` を指定すると、そのロケールだけをダウンロードします（例：`--locale en-US,tr`）。iPhone Duo のスクリーンショットや、ヘッダーと検索結果の画像も保存されます。

## アップロード

```bash
# フォルダからアップロード
ascelerate apps media upload <bundle-id> media/

# アーカイブからアップロード（zip、tar、tar.gz対応）
ascelerate apps media upload <bundle-id> screenshots.zip

# 特定のバージョンにアップロード（ユニバーサル購入のアプリでは --platform を追加）
ascelerate apps media upload <bundle-id> media/ --version 2.1.0
ascelerate apps media upload <bundle-id> media/ --version 2.1.0 --platform macos

# アップロード前にマッチするセットの既存メディアを削除して置き換え
ascelerate apps media upload <bundle-id> media/ --replace

# インタラクティブモード：カレントディレクトリからフォルダまたはアーカイブを選択
ascelerate apps media upload <bundle-id>
```

フォルダ引数を省略すると、カレントディレクトリのすべてのサブディレクトリとアーカイブファイルが番号付きリストとして表示されます。アーカイブ（zip、tar、tar.gz）はアップロード前に自動的に展開されます。

各ファイルの行は、実行全体での位置（`[57/203]`）で始まります。ターミナルでは、送信中のファイルのアップロード済みの量も同じ行に表示されます。

## フォルダ構造

ロケールとディスプレイタイプのサブフォルダでメディアフォルダを整理します：

```
media/
├── en-US/
│   ├── APP_IPHONE_67/
│   │   ├── 01_home.png
│   │   ├── 02_settings.png
│   │   └── preview.mp4
│   └── APP_IPAD_PRO_3GEN_129/
│       └── 01_home.png
└── de-DE/
    └── APP_IPHONE_67/
        ├── 01_home.png
        └── 02_settings.png
```

- **レベル1：** ロケール（例：`en-US`、`de-DE`、`ja`）
- **レベル2：** ディスプレイタイプのフォルダ名（下記の表を参照）
- **レベル3：** メディアファイル — 画像（`.png`、`.jpg`、`.jpeg`）はスクリーンショットに、動画（`.mp4`、`.mov`）はアプリプレビューになります
- ファイルはファイル名のアルファベット順にアップロードされます
- サポートされていないファイルは警告とともにスキップされます

## ディスプレイタイプ

App Store Connectでは、iPhoneアプリには **`APP_IPHONE_67`** のスクリーンショットが、iPadアプリには **`APP_IPAD_PRO_3GEN_129`** のスクリーンショットが**必須**です。その他のディスプレイタイプはすべてオプションです。

| フォルダ名 | デバイス | スクリーンショット | プレビュー |
|---|---|---|---|
| `APP_IPHONE_67` | iPhone 6.7"（iPhone 17 Pro Max、16 Pro Max、15 Pro Max） | **必須** | 対応 |
| `APP_IPAD_PRO_3GEN_129` | iPad Pro 12.9"（第3世代以降） | **必須** | 対応 |

<details>
<summary>すべてのオプションディスプレイタイプ</summary>

| フォルダ名 | デバイス | スクリーンショット | プレビュー |
|---|---|---|---|
| `APP_IPHONE_61` | iPhone 6.1"（iPhone 17 Pro、16 Pro、15 Pro） | 対応 | 対応 |
| `APP_IPHONE_65` | iPhone 6.5"（iPhone 11 Pro Max、XS Max） | 対応 | 対応 |
| `APP_IPHONE_58` | iPhone 5.8"（iPhone 11 Pro、X、XS） | 対応 | 対応 |
| `APP_IPHONE_55` | iPhone 5.5"（iPhone 8 Plus、7 Plus、6s Plus） | 対応 | 対応 |
| `APP_IPHONE_47` | iPhone 4.7"（iPhone SE 第3世代、8、7、6s） | 対応 | 対応 |
| `APP_IPHONE_40` | iPhone 4"（iPhone SE 第1世代、5s、5c） | 対応 | 対応 |
| `APP_IPHONE_35` | iPhone 3.5"（iPhone 4s以前） | 対応 | 対応 |
| `APP_IPHONE_DUO` | iPhone Duo（[下記](#iphone-duo)参照） | 対応 | 非対応 |
| `PRODUCT_PAGE_HEADER` | プロダクトページのヘッダー（[下記](#header-and-search-results)参照） | 対応 | 非対応 |
| `APP_STORE_SEARCH_RESULTS` | App Store の検索結果（[下記](#header-and-search-results)参照） | 対応 | 非対応 |
| `APP_IPAD_PRO_3GEN_11` | iPad Pro 11" | 対応 | 対応 |
| `APP_IPAD_PRO_129` | iPad Pro 12.9"（第1/2世代） | 対応 | 対応 |
| `APP_IPAD_105` | iPad 10.5"（iPad Air 第3世代、iPad Pro 10.5"） | 対応 | 対応 |
| `APP_IPAD_97` | iPad 9.7"（iPad 第6世代以前） | 対応 | 対応 |
| `APP_DESKTOP` | Mac | 対応 | 対応 |
| `APP_APPLE_TV` | Apple TV | 対応 | 対応 |
| `APP_APPLE_VISION_PRO` | Apple Vision Pro | 対応 | 対応 |
| `APP_WATCH_ULTRA` | Apple Watch Ultra | 対応 | 非対応 |
| `APP_WATCH_SERIES_10` | Apple Watch Series 10 | 対応 | 非対応 |
| `APP_WATCH_SERIES_7` | Apple Watch Series 7 | 対応 | 非対応 |
| `APP_WATCH_SERIES_4` | Apple Watch Series 4 | 対応 | 非対応 |
| `APP_WATCH_SERIES_3` | Apple Watch Series 3 | 対応 | 非対応 |
| `IMESSAGE_APP_IPHONE_67` | iMessage iPhone 6.7" | 対応 | 非対応 |
| `IMESSAGE_APP_IPHONE_61` | iMessage iPhone 6.1" | 対応 | 非対応 |
| `IMESSAGE_APP_IPHONE_65` | iMessage iPhone 6.5" | 対応 | 非対応 |
| `IMESSAGE_APP_IPHONE_58` | iMessage iPhone 5.8" | 対応 | 非対応 |
| `IMESSAGE_APP_IPHONE_55` | iMessage iPhone 5.5" | 対応 | 非対応 |
| `IMESSAGE_APP_IPHONE_47` | iMessage iPhone 4.7" | 対応 | 非対応 |
| `IMESSAGE_APP_IPHONE_40` | iMessage iPhone 4" | 対応 | 非対応 |
| `IMESSAGE_APP_IPAD_PRO_3GEN_129` | iMessage iPad Pro 12.9"（第3世代以降） | 対応 | 非対応 |
| `IMESSAGE_APP_IPAD_PRO_3GEN_11` | iMessage iPad Pro 11" | 対応 | 非対応 |
| `IMESSAGE_APP_IPAD_PRO_129` | iMessage iPad Pro 12.9"（第1/2世代） | 対応 | 非対応 |
| `IMESSAGE_APP_IPAD_105` | iMessage iPad 10.5" | 対応 | 非対応 |
| `IMESSAGE_APP_IPAD_97` | iMessage iPad 9.7" | 対応 | 非対応 |

</details>

:::note
WatchとiMessageのディスプレイタイプはスクリーンショットのみ対応しています。これらのフォルダ内の動画ファイルは警告とともにスキップされます。`--replace` フラグは、新しいファイルをアップロードする前にマッチする各セットの既存アセットをすべて削除します。
:::

### iPhone Duo

App Store Connect には iPhone Duo 用のスクリーンショットセットがありません。ascelerate は `APP_IPHONE_DUO` フォルダ内のファイルをアプリのアセットライブラリにアップロードし、ファイル順にバージョンのローカライズ情報へ配置します。対応サイズは 2853×2007 または 2007×2853（内側ディスプレイ、開いた状態）と、2034×1398 または 1398×2034（外側ディスプレイ）です。それ以外のサイズは、アップロード前に拒否されます。`--replace` を指定すると、各ロケールの既存の iPhone Duo スクリーンショットが先に削除されます。

このフォルダには iPhone Duo のアプリプレビュー（`.mp4`、`.m4v`、`.mov`）も入れられます。サイズは 1920×886 または 886×1920、長さは 15〜30 秒、フレームレートは 23〜30 fps で、音声トラックが必要です。プレビューはロケールの既存のプレビューの後に追加され、`--replace` を指定すると既存のものが先に削除されます。スクリーンショットとプレビューは別々に置き換えられ、フォルダにその種類のファイルがある場合にのみ置き換えられます。

再試行しても失敗したファイルがある場合、`media upload` は実行の最後にそのロケールの iPhone Duo のスクリーンショットまたはプレビューを配置し直し、ファイル順を保ちます。`media verify` はファイル名と処理状況つきで一覧表示し、メディアフォルダを指定すると、ファイルや順序がフォルダと異なるロケールも報告します（`--replace` を付けて `media upload` を実行すると直せます）。`media download` はスクリーンショットを元のファイル名で保存し、`media prune` がこれらを削除することはありません。

### プロダクトページのヘッダーと検索結果 {#header-and-search-results}

さらに2つのフォルダがアセットライブラリ経由でアップロードされます。どちらもロケールごとに画像またはビデオ1点で、デバイスクラスには結び付きません。バージョンはそれをすべてのデバイス（iPhone、iPad、iPhone Duo）で表示し、すべてのプラットフォームのバージョンで使えます。

- `PRODUCT_PAGE_HEADER`：プロダクトページ上部の画像またはビデオ。3840×1646 または 5244×2950 の PNG、または 3840×1646 で長さ 5〜30 秒、30 または 60 fps のビデオ。
- `APP_STORE_SEARCH_RESULTS`：App Store の検索結果でアプリと一緒に表示されます。1920×1280 から 3840×2560 までの 3:2 の JPG または PNG、または 5244×2950 の PNG。あるいは同じサイズ範囲の 3:2 のビデオで、長さ 5〜30 秒、30 または 60 fps。

アップロードすると、`--replace` の有無にかかわらず、そのロケールの現在の画像またはビデオが置き換えられます。古いものは、新しいもののアップロードが終わってから削除されます。新しいビデオは数分間処理中になり、`media verify` にそのように表示されます。`media download` は画像を保存します。これらのビデオには App Store Connect がダウンロードリンクを提供していません。

カスタムプロダクトページにも、`product-pages media upload` に `--display-type PRODUCT_PAGE_HEADER`、`APP_STORE_SEARCH_RESULTS`、`APP_IPHONE_DUO` を指定して同じファイルをアップロードできます。

## app-store-screenshotsとの連携

[app-store-screenshots](https://github.com/keremerkan/ascelerate/tree/main/skills/app-store-screenshots) は、AIコーディングエージェント用のコンパニオンスキルで、本番品質のApp Storeスクリーンショットを生成します。`ascelerate screenshot frame` でフレーム加工されたデバイススクリーンショットを使用して広告スタイルのマーケティングレイアウトをレンダリングするNext.jsページを作成し、`ascelerate apps media upload` でアップロード可能なzipファイルとしてエクスポートします：

```
en-US/APP_IPHONE_67/01_hero.png
en-US/APP_IPAD_PRO_3GEN_129/01_hero.png
de-DE/APP_IPHONE_67/01_hero.png
```

AIコーディングエージェントにスキルをインストールします：

```bash
npx skills add keremerkan/ascelerate
```

エクスポートしたzipを直接アップロードできます：

```bash
ascelerate apps media upload <bundle-id> screenshots.zip --replace
```

## 停滞したメディアの確認とリトライ

アップロード後にスクリーンショットやプレビューが「処理中」のままスタックすることがあります。`media verify` でステータスを確認し、停滞したアイテムをリトライできます：

```bash
# すべてのスクリーンショットとプレビューのステータスを確認
ascelerate apps media verify <bundle-id>

# 特定のバージョンを確認
ascelerate apps media verify <bundle-id> --version 2.1.0

# メディアフォルダのローカルファイルを使用して停滞したアイテムをリトライ
ascelerate apps media verify <bundle-id> media/
```

フォルダ引数を指定しない場合、読み取り専用のステータスレポートが表示されます。すべてのアイテムが完了しているセットはコンパクトな1行で表示され、停滞したアイテムがあるセットは各ファイルとその状態を展開して表示します。フォルダ引数を指定すると、停滞したアイテムを削除してマッチするローカルファイルから再アップロードし、元の並び順を保持します。

スクリーンショット自体は完了と表示されていても、アセットライブラリでの配置がまだ処理中の場合は停滞として扱われます。この状態のバージョンは App Review に受け付けられないため（「Asset is being processed」）、フォルダを指定して再試行すると、そのスクリーンショットが再アップロードされます。

## 古いセットの削除

アップロード時の `--replace` は、ローカルフォルダに対応するセットのみを入れ替えます。提供を終了した画面サイズのサーバー側セットには、古いスクリーンショットが残ったままになります。`media prune` は、対応するロケール/ディスプレイタイプのフォルダが存在しないセットを、アセット数とともに一覧表示して確認した上で削除します。

```bash
ascelerate apps media prune <bundle-id> media/
ascelerate apps media prune <bundle-id> media/ --version 2.1.0 --platform ios
```

ローカルフォルダのないロケールは完全にスキップされます。このコマンドは、フォルダが実際に管理しているロケール内のみを削除対象とします。

## アセットライブラリの画像を削除する

`media remove` は、アセットライブラリの項目のうち1種類をバージョンから外します。`PRODUCT_PAGE_HEADER` または `APP_STORE_SEARCH_RESULTS` の画像やビデオ、あるいは `APP_IPHONE_DUO` のスクリーンショット（`--previews` でアプリプレビュー）です。`--locale` で指定したロケール、または全ロケールが対象で、見つかったものを一覧表示してから確認します。

```bash
ascelerate apps media remove <bundle-id> PRODUCT_PAGE_HEADER --locale en-US
ascelerate apps media remove <bundle-id> APP_STORE_SEARCH_RESULTS
ascelerate apps media remove <bundle-id> APP_IPHONE_DUO --locale en-US,tr --version 2.1.0
ascelerate apps media remove <bundle-id> APP_IPHONE_DUO --previews --locale en-US
```

## アセットライブラリを整理する

各アプリには、アップロードした画像とビデオを保持するアセットライブラリがあり、画像はバージョン間で共有されます。新しいバージョンのスクリーンショットは前のバージョンの画像で、古いバージョンも自分の画像を保持しています。そのため、どこかのバージョン（古いものを含む）、カスタムプロダクトページ、イベントに配置されている限り、画像は使用中です。ascelerate が配置を外すとき（`media remove`、`media upload --replace`、ヘッダーや検索結果の画像の置き換え）、その画像がどこにも使われておらず、App Review を一度も経ていなければ、画像やビデオも削除します。

以前のアップロードによって、未使用の画像やビデオがライブラリに残っていることがあります。`media library` は画像とビデオを数えて未使用のものを一覧表示し、`--delete-unused` を付けると確認のうえ削除します。

```bash
ascelerate apps media library <bundle-id>
ascelerate apps media library <bundle-id> --delete-unused
ascelerate apps media library <bundle-id> --only APP_IPHONE_DUO --delete-unused
```

`--only` を付けると、指定した種類に合う画像だけを、アセットカテゴリとピクセルサイズで判定して一覧に含めます。種類は `PRODUCT_PAGE_HEADER`、`APP_STORE_SEARCH_RESULTS`、`APP_IPHONE_DUO`、`APP_IPHONE_67` などのスクリーンショット表示タイプ（サイズは App Store Connect から取得）、またはファイルが届かなかったアップロードを表す `UNFINISHED_UPLOADS` です。これにより、デバイスタイプごとにライブラリを整理できます。作成から1時間未満の画像は、同時に実行中のアップロードが配置しようとしている可能性があるため常に残します。App Store Connect の1時間あたりの API 上限に達した場合は処理を止め、後で再実行するよう案内します。

App Review を経た画像は、配置の有無にかかわらず削除されません。また、各画像は削除の直前にもう一度確認されます。
