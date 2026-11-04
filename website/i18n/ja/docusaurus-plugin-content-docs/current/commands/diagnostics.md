---
sidebar_position: 16
title: 診断
---

# 診断

Xcode の Organizer に表示される内容です。デベロッパと解析データを共有しているユーザのデバイスから集められた、ビルドの主なハング、起動の遅延、ディスク書き込みとそのコールスタック、およびバージョンごとの App のパフォーマンスと電力のメトリクスを扱います。`--build` を指定しない場合は、App Store で配信中のバージョンのビルドが対象です。

## シグネチャ

```bash
ascelerate diagnostics <bundle-id>
ascelerate diagnostics <bundle-id> --type hangs --build 2041
```

ビルドのハング、起動、ディスク書き込みのシグネチャを、種類ごとに重みの大きい順に、以前のバージョンと比べた傾向とともに表示します。`--type` には `hangs`、`launches`、`disk-writes` を指定します（複数はカンマ区切り）。

## ログ

```bash
ascelerate diagnostics logs <signature-id>
ascelerate diagnostics logs <signature-id> --frames 0
```

サンプリングされた各イベントのデバイス、OS、App のバージョンと、そのコールスタックを表示します。App Store Connect が原因とみなすフレームには ▶ が付きます。`--frames` はコールスタックごとのフレーム数を制限します（デフォルトは 40、0 ですべて）。

## メトリクス

```bash
ascelerate diagnostics metrics <bundle-id>
ascelerate diagnostics metrics <bundle-id> --type launch,hang --all
```

各メトリクス（起動時間、ハング率、最大メモリ、ディスク書き込み、バッテリー、終了、アニメーション、ストレージ）を App のバージョンごとに、すべてのデバイスの標準（50 パーセンタイル）と 90 パーセンタイルで表示します。`--all` ではデバイスのモデルごとの値も表示します。Apple が検出した悪化と上昇傾向が最初に表示されます。`--build` は 1 つのビルドのメトリクスを表示します。

3 つとも `--json` を使えます。
