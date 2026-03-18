---
sidebar_position: 1
title: インストール
---

# インストール

## 必要条件

- macOS 13以上
- Swift 6.0以上（ソースからビルドする場合のみ）

## Homebrew

```bash
brew tap keremerkan/tap
brew install ascelerate
```

このtapはApple Silicon Mac向けのビルド済みバイナリを提供しているため、インストールは瞬時に完了します。

## インストールスクリプト

```bash
curl -sSL https://raw.githubusercontent.com/keremerkan/ascelerate/main/install.sh | bash
```

最新リリースをダウンロードし、`/usr/local/bin` にインストールして、quarantine属性を自動的に削除します。Apple Siliconのみ対応です。

## 手動ダウンロード

[GitHub Releases](https://github.com/keremerkan/ascelerate/releases) から最新リリースをダウンロードしてください：

```bash
curl -L https://github.com/keremerkan/ascelerate/releases/latest/download/ascelerate-macos-arm64.tar.gz -o ascelerate.tar.gz
tar xzf ascelerate.tar.gz
mv ascelerate /usr/local/bin/
```

バイナリは署名・公証されていないため、macOSは初回ダウンロード時にquarantine属性を付与します。以下のコマンドで削除してください：

```bash
xattr -d com.apple.quarantine /usr/local/bin/ascelerate
```

:::note
ビルド済みバイナリはApple Silicon（arm64）のみ提供しています。Intel Macをお使いの方はソースからビルドしてください。
:::

## ソースからビルド

```bash
git clone https://github.com/keremerkan/ascelerate.git
cd ascelerate
swift build -c release
strip .build/release/ascelerate
cp .build/release/ascelerate /usr/local/bin/
```

:::note
リリースビルドは数分かかります。これは依存ライブラリの [asc-swift](https://github.com/aaronsky/asc-swift) がApp Store Connect APIの全エンドポイントをカバーする約2500個の生成ソースファイルを含んでいるためです。`strip` でデバッグシンボルを削除すると、バイナリサイズが約175 MBから約59 MBに縮小されます。
:::

## シェル補完

サブコマンド、オプション、フラグのタブ補完を設定します（zshとbashに対応）：

```bash
ascelerate install-completions
```

シェルを自動検出してすべてを設定します。シェルを再起動するか、新しいタブを開くと有効になります。

## バージョン確認

```bash
ascelerate version     # バージョン番号を表示
ascelerate --version   # 同上
ascelerate -v          # 同上
```
