---
sidebar_position: 8
title: デバイス
---

# デバイス

すべてのデバイスコマンドはインタラクティブモードに対応しています。引数はオプションで、省略するとコマンドが番号付きリストで候補を表示します。

## 一覧

```bash
ascelerate devices list
ascelerate devices list --platform IOS --status ENABLED
```

## 詳細

```bash
# インタラクティブな選択
ascelerate devices info

# 名前またはUDIDで指定
ascelerate devices info "My iPhone"
```

## 登録

```bash
# インタラクティブな入力
ascelerate devices register

# 非インタラクティブ
ascelerate devices register --name "My iPhone" --udid 00008101-XXXXXXXXXXXX --platform IOS
```

## 更新

```bash
# インタラクティブな選択と更新
ascelerate devices update

# デバイスの名前を変更
ascelerate devices update "My iPhone" --name "Work iPhone"

# デバイスを無効化
ascelerate devices update "My iPhone" --status DISABLED
```
