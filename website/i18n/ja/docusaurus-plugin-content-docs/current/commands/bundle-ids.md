---
sidebar_position: 10
title: Bundle ID
---

# Bundle ID

すべてのBundle IDコマンドはインタラクティブモードに対応しています。引数はオプションです。

## 一覧

```bash
ascelerate bundle-ids list
ascelerate bundle-ids list --platform IOS
```

## 詳細

```bash
# インタラクティブな選択
ascelerate bundle-ids info

# 識別子で指定
ascelerate bundle-ids info com.example.MyApp
```

## 登録

```bash
# インタラクティブな入力
ascelerate bundle-ids register

# 非インタラクティブ
ascelerate bundle-ids register --name "My App" --identifier com.example.MyApp --platform IOS
```

## 名前の変更

```bash
ascelerate bundle-ids update
ascelerate bundle-ids update com.example.MyApp --name "My Renamed App"
```

識別子自体は変更できません。変更できるのは名前のみです。

## 削除

```bash
ascelerate bundle-ids delete
ascelerate bundle-ids delete com.example.MyApp
```

## ケイパビリティ

### 有効化

```bash
# インタラクティブな選択（まだ有効でないケイパビリティのみ表示）
ascelerate bundle-ids enable-capability

# 非インタラクティブ
ascelerate bundle-ids enable-capability com.example.MyApp --type PUSH_NOTIFICATIONS
```

### 無効化

```bash
# 現在有効なケイパビリティから選択
ascelerate bundle-ids disable-capability
ascelerate bundle-ids disable-capability com.example.MyApp
```

ケイパビリティの有効化・無効化後、そのBundle IDにプロビジョニングプロファイルが存在する場合、再生成するか確認します（変更を反映するために必要です）。

:::note
一部のケイパビリティ（App Groups、iCloud、Associated Domainsなど）は、有効化後に [Apple Developer ポータル](https://developer.apple.com/account/resources) で追加の設定が必要です。
:::
