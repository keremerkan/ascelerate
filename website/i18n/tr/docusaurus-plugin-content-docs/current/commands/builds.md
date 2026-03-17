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
```

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

`.ipa`, `.pkg` veya `.xcarchive` dosyalarını kabul eder. `.xcarchive` verildiğinde, yüklemeden önce otomatik olarak `.ipa`'ya dışa aktarır.

## İşlenmeyi bekleme

```bash
ascelerate builds await-processing <bundle-id>
ascelerate builds await-processing <bundle-id> --build-version 903
```

Yakın zamanda yüklenen build'lerin API'da görünmesi birkaç dakika sürebilir -- komut, build bulunana ve işlenmesi tamamlanana kadar ilerleme göstergesiyle yoklar.

## Bir sürüme build ekleme

```bash
# İnteraktif olarak bir build seçin ve ekleyin
ascelerate apps build attach <bundle-id>
ascelerate apps build attach <bundle-id> --version 2.1.0

# En son build'i otomatik olarak ekleyin
ascelerate apps build attach-latest <bundle-id>

# Bir sürümden eklenen build'i kaldırın
ascelerate apps build detach <bundle-id>
```

`build attach-latest`, en son build hâlâ işleniyorsa beklemeyi teklif eder. `--yes` ile otomatik olarak bekler.
