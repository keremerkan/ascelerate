---
sidebar_position: 2
title: Build'ler
---

# Build'ler

## Build'leri listeleme

```bash
asc builds list
asc builds list --bundle-id <bundle-id>
asc builds list --bundle-id <bundle-id> --version 2.1.0
```

## Arşivleme

```bash
asc builds archive
asc builds archive --scheme MyApp --output ./archives
```

`archive` komutu geçerli dizindeki `.xcworkspace` veya `.xcodeproj` dosyasını otomatik olarak algılar ve yalnızca bir tane varsa scheme'i çözer.

## Doğrulama

```bash
asc builds validate MyApp.ipa
```

## Yükleme

```bash
asc builds upload MyApp.ipa
```

`.ipa`, `.pkg` veya `.xcarchive` dosyalarını kabul eder. `.xcarchive` verildiğinde, yüklemeden önce otomatik olarak `.ipa`'ya dışa aktarır.

## İşlenmeyi bekleme

```bash
asc builds await-processing <bundle-id>
asc builds await-processing <bundle-id> --build-version 903
```

Yakın zamanda yüklenen build'lerin API'da görünmesi birkaç dakika sürebilir -- komut, build bulunana ve işlenmesi tamamlanana kadar ilerleme göstergesiyle yoklar.

## Bir sürüme build ekleme

```bash
# İnteraktif olarak bir build seçin ve ekleyin
asc apps build attach <bundle-id>
asc apps build attach <bundle-id> --version 2.1.0

# En son build'i otomatik olarak ekleyin
asc apps build attach-latest <bundle-id>

# Bir sürümden eklenen build'i kaldırın
asc apps build detach <bundle-id>
```

`build attach-latest`, en son build hâlâ işleniyorsa beklemeyi teklif eder. `--yes` ile otomatik olarak bekler.
