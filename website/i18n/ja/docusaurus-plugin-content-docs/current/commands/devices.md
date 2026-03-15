---
sidebar_position: 8
title: デバイス
---

# デバイス

すべてのデバイスコマンドはインタラクティブモードに対応しています。引数はオプションで、省略するとコマンドが番号付きリストで候補を表示します。

## 一覧

```bash
asc devices list
asc devices list --platform IOS --status ENABLED
```

## 詳細

```bash
# インタラクティブな選択
asc devices info

# 名前またはUDIDで指定
asc devices info "My iPhone"
```

## 登録

```bash
# インタラクティブな入力
asc devices register

# 非インタラクティブ
asc devices register --name "My iPhone" --udid 00008101-XXXXXXXXXXXX --platform IOS
```

## 更新

```bash
# インタラクティブな選択と更新
asc devices update

# デバイスの名前を変更
asc devices update "My iPhone" --name "Work iPhone"

# デバイスを無効化
asc devices update "My iPhone" --status DISABLED
```
