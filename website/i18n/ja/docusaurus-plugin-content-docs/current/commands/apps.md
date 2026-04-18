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

## バージョンの作成

```bash
ascelerate apps create-version <bundle-id> <version-string>
ascelerate apps create-version <bundle-id> 2.1.0 --platform ios --release-type manual
```

`--release-type` はオプションです。省略した場合、前のバージョンの設定が使用されます。

## レビュー

### レビューステータスの確認

```bash
ascelerate apps review status <bundle-id>
ascelerate apps review status <bundle-id> --version 2.1.0
```

### 審査への提出

```bash
ascelerate apps review submit <bundle-id>
ascelerate apps review submit <bundle-id> --version 2.1.0
```

提出時に、保留中の変更があるIAPやサブスクリプションを自動検出し、アプリバージョンと一緒に提出するか確認します。

### リジェクトされた項目の解決

問題を修正してResolution Centerで返信した後：

```bash
ascelerate apps review resolve-issues <bundle-id>
```

### 提出のキャンセル

```bash
ascelerate apps review cancel-submission <bundle-id>
```

## プリフライトチェック

審査に提出する前に `preflight` を実行して、すべてのロケールで必須フィールドが入力されていることを確認します：

```bash
# 最新の編集可能なバージョンを確認
ascelerate apps review preflight <bundle-id>

# 特定のバージョンを確認
ascelerate apps review preflight <bundle-id> --version 2.1.0
```

バージョンの状態、ビルドの添付、各ロケールのローカライゼーションフィールド（説明文、新機能、キーワード）、アプリ情報フィールド（名前、サブタイトル、プライバシーポリシーURL）、スクリーンショットを確認します：

```
Preflight checks for MyApp v2.1.0 (Prepare for Submission)

Check                                Status
──────────────────────────────────────────────────────────────────
Version state                        ✓ Prepare for Submission
Build attached                       ✓ Build 42

en-US (English (United States))
  App info                           ✓ All fields filled
  Localizations                      ✓ All fields filled
  Screenshots                        ✓ 2 sets, 10 screenshots

de-DE (German (Germany))
  App info                           ✗ Missing: Privacy Policy URL
  Localizations                      ✗ Missing: What's New
  Screenshots                        ✗ No screenshots
──────────────────────────────────────────────────────────────────
Result: 5 passed, 3 failed
```

チェックが失敗するとゼロ以外の終了コードを返すため、CIパイプラインやワークフローファイルでの使用に適しています。

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

# サンドボックステストでも有効化
ascelerate apps subscription-grace-period <bundle-id> --sandbox-opt-in true
```

`--duration` の有効な値：`THREE_DAYS`、`SIXTEEN_DAYS`、`TWENTY_EIGHT_DAYS`。`--renewal-type` の有効な値：`ALL_RENEWALS`、`PAID_TO_PAID_ONLY`。
