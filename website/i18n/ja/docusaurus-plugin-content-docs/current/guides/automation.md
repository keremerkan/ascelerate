---
sidebar_position: 2
title: 自動化とCI/CD
---

# 自動化とCI/CD

確認プロンプトを表示するほとんどのコマンドは `--yes` / `-y` でプロンプトをスキップできるため、CI/CDパイプラインやスクリプトでの使用に適しています。

```bash
asc apps build attach-latest <bundle-id> --yes
asc apps review submit <bundle-id> --yes
```

:::warning
プロビジョニングコマンドで `--yes` を使用する場合、必要なすべての引数を明示的に指定する必要があります。インタラクティブモードは無効になります。
:::

## CIでのXcode署名

`builds archive` とアーカイブからIPAへのエクスポートの両方で、`xcodebuild` に `-allowProvisioningUpdates` を渡します。これがないと、`xcodebuild` はローカルにキャッシュされたプロビジョニングプロファイルのみを使用し、Developer Portalから更新されたものを取得しません。

Xcode GUIログインのないCI環境では、認証フラグを渡してください：

```bash
asc builds archive \
  --authentication-key-path /path/to/AuthKey.p8 \
  --authentication-key-id YOUR_KEY_ID \
  --authentication-key-issuer-id YOUR_ISSUER_ID
```

## 終了コード

コマンドは失敗時にゼロ以外のステータスで終了するため、`set -e` や `&&` チェーンを使用するスクリプトで安全に使用できます。`preflight` コマンドはチェックが失敗するとゼロ以外で終了するため、提出のゲートとして使用できます：

```bash
asc apps review preflight <bundle-id> && asc apps review submit <bundle-id>
```
