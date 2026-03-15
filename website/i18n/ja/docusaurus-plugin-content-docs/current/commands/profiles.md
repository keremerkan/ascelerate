---
sidebar_position: 11
title: プロビジョニングプロファイル
---

# プロビジョニングプロファイル

すべてのプロファイルコマンドはインタラクティブモードに対応しています。引数はオプションです。

## 一覧

```bash
asc profiles list
asc profiles list --type IOS_APP_STORE --state ACTIVE
```

## 詳細

```bash
asc profiles info
asc profiles info "My App Store Profile"
```

## ダウンロード

```bash
asc profiles download
asc profiles download "My App Store Profile" --output ./profiles/
```

## 作成

```bash
# 完全にインタラクティブ
asc profiles create

# 非インタラクティブ
asc profiles create --name "My Profile" --type IOS_APP_STORE --bundle-id com.example.MyApp --certificates all
```

`--certificates all` は、該当するファミリー（distribution、development、またはDeveloper ID）のすべての証明書を使用します。シリアル番号で指定することもできます：`--certificates ABC123,DEF456`。

## 削除

```bash
asc profiles delete
asc profiles delete "My App Store Profile"
```

## 再発行

プロファイルを削除し、該当するファミリーの最新の証明書で再作成して再発行します：

```bash
# インタラクティブ：すべてのプロファイルから選択（ステータス表示あり）
asc profiles reissue

# 名前を指定して特定のプロファイルを再発行
asc profiles reissue "My Profile"

# すべての無効なプロファイルを再発行
asc profiles reissue --all-invalid

# 状態に関係なくすべてのプロファイルを再発行
asc profiles reissue --all

# すべてを再発行し、dev/adhocにはすべての有効なデバイスを使用
asc profiles reissue --all --all-devices

# 自動検出の代わりに特定の証明書を使用
asc profiles reissue --all --to-certs ABC123,DEF456
```
