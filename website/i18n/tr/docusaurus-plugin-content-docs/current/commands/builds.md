---
sidebar_position: 2
title: Build'ler
---

# Build'ler

## Build'leri listeleme

```bash
ascelerate builds list
ascelerate builds list --bundle-id <bundle-id>
ascelerate builds list --bundle-id <bundle-id> --version 2.1.0
ascelerate builds list --bundle-id <bundle-id> --platform macos
```

Çıktı, her build'in uygulama sürümünü, platformunu, build numarasını, işlenme durumunu ve yükleme tarihini gösterir.

## Arşivleme

```bash
ascelerate builds archive
ascelerate builds archive --scheme MyApp --output ./archives
```

`archive` komutu geçerli dizindeki `.xcworkspace` veya `.xcodeproj` dosyasını otomatik olarak algılar ve yalnızca bir tane varsa scheme'i çözer.

## Doğrulama

```bash
ascelerate builds validate MyApp.ipa
```

## Yükleme

```bash
ascelerate builds upload MyApp.ipa
```

`.ipa`, `.pkg` veya `.xcarchive` dosyalarını kabul eder. `.xcarchive` verildiğinde arşivin platformunu algılar ve yüklemeden önce otomatik olarak `.ipa` (iOS ailesi) veya `.pkg` (macOS) biçimine dışa aktarır; eşleşen platform altool'a iletilir.

## İşlenmeyi bekleme

```bash
ascelerate builds await-processing <bundle-id>
ascelerate builds await-processing <bundle-id> --build-version 903
ascelerate builds await-processing <bundle-id> --build-version 903 --platform macos
```

Yakın zamanda yüklenen build'lerin API'da görünmesi birkaç dakika sürebilir -- komut, build bulunana ve işlenmesi tamamlanana kadar ilerleme göstergesiyle yoklar.

## Bir sürüme build ekleme

```bash
# İnteraktif olarak bir build seçin ve ekleyin
ascelerate apps build attach <bundle-id>
ascelerate apps build attach <bundle-id> --version 2.1.0

# En son build'i otomatik olarak ekleyin
ascelerate apps build attach-latest <bundle-id>
ascelerate apps build attach-latest <bundle-id> --platform macos

# Bir sürümden eklenen build'i kaldırın
ascelerate apps build detach <bundle-id>
```

`build attach-latest`, en son build hâlâ işleniyorsa beklemeyi teklif eder. `--yes` ile otomatik olarak bekler.

Build aramaları platforma duyarlıdır: evrensel satın alma kullanan uygulamalarda iOS ve macOS build'leri aynı build numaralarını paylaşabildiğinden, ekleme komutları yalnızca hedef sürümün platformuyla eşleşen build'leri dikkate alır.
