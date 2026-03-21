---
sidebar_position: 4
title: スクリーンショットとプレビュー
---

# スクリーンショットとアプリプレビュー

## ダウンロード

```bash
ascelerate apps media download <bundle-id>
ascelerate apps media download <bundle-id> --folder my-media/ --version 2.1.0
```

デフォルトでは `<bundle-id>-media/` にダウンロードされ、アップロードで使用されるのと同じフォルダ構造が使用されます。

## アップロード

```bash
# フォルダからアップロード
ascelerate apps media upload <bundle-id> media/

# アーカイブからアップロード（zip、tar、tar.gz対応）
ascelerate apps media upload <bundle-id> screenshots.zip

# 特定のバージョンにアップロード
ascelerate apps media upload <bundle-id> media/ --version 2.1.0

# アップロード前にマッチするセットの既存メディアを削除して置き換え
ascelerate apps media upload <bundle-id> media/ --replace

# インタラクティブモード：カレントディレクトリからフォルダまたはアーカイブを選択
ascelerate apps media upload <bundle-id>
```

フォルダ引数を省略すると、カレントディレクトリのすべてのサブディレクトリとアーカイブファイルが番号付きリストとして表示されます。アーカイブ（zip、tar、tar.gz）はアップロード前に自動的に展開されます。

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
