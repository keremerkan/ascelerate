---
sidebar_position: 1
title: アプリ
---

# アプリ

## アプリ一覧

```bash
asc apps list
```

## アプリ詳細

```bash
asc apps info <bundle-id>
```

## バージョン一覧

```bash
asc apps versions <bundle-id>
```

## バージョンの作成

```bash
asc apps create-version <bundle-id> <version-string>
asc apps create-version <bundle-id> 2.1.0 --platform ios --release-type manual
```

`--release-type` はオプションです。省略した場合、前のバージョンの設定が使用されます。

## レビュー

### レビューステータスの確認

```bash
asc apps review status <bundle-id>
asc apps review status <bundle-id> --version 2.1.0
```

### 審査への提出

```bash
asc apps review submit <bundle-id>
asc apps review submit <bundle-id> --version 2.1.0
```

提出時に、保留中の変更があるIAPやサブスクリプションを自動検出し、アプリバージョンと一緒に提出するか確認します。

### リジェクトされた項目の解決

問題を修正してResolution Centerで返信した後：

```bash
asc apps review resolve-issues <bundle-id>
```

### 提出のキャンセル

```bash
asc apps review cancel-submission <bundle-id>
```

## プリフライトチェック

審査に提出する前に `preflight` を実行して、すべてのロケールで必須フィールドが入力されていることを確認します：

```bash
# 最新の編集可能なバージョンを確認
asc apps review preflight <bundle-id>

# 特定のバージョンを確認
asc apps review preflight <bundle-id> --version 2.1.0
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
asc apps phased-release <bundle-id>

# 段階的リリースを有効化（非アクティブで開始、バージョン公開時に有効化）
asc apps phased-release <bundle-id> --enable

# 段階的リリースの一時停止、再開、完了
asc apps phased-release <bundle-id> --pause
asc apps phased-release <bundle-id> --resume
asc apps phased-release <bundle-id> --complete

# 段階的リリースを完全に削除
asc apps phased-release <bundle-id> --disable
```

## 販売地域の管理

```bash
# アプリが利用可能な地域を確認
asc apps availability <bundle-id>

# 完全な国名を表示
asc apps availability <bundle-id> --verbose

# 地域の追加・削除
asc apps availability <bundle-id> --add CHN,RUS
asc apps availability <bundle-id> --remove CHN
```

## 暗号化宣言

```bash
# 既存の暗号化宣言を確認
asc apps encryption <bundle-id>

# 新しい暗号化宣言を作成
asc apps encryption <bundle-id> --create --description "Uses HTTPS for API communication"
asc apps encryption <bundle-id> --create --description "Uses AES encryption" --proprietary-crypto --third-party-crypto
```

## EULA

```bash
# 現在のEULAを確認（標準のApple EULAが適用されているか確認）
asc apps eula <bundle-id>

# テキストファイルからカスタムEULAを設定
asc apps eula <bundle-id> --file eula.txt

# カスタムEULAを削除（標準のApple EULAに戻す）
asc apps eula <bundle-id> --delete
```
