---
sidebar_position: 18
title: Ürün Sayfası Optimizasyonu
---

# Ürün Sayfası Optimizasyonu

Alternatif ekran görüntülerini, uygulama önizlemelerini ve uygulama simgelerini orijinal App Store ürün sayfanızla karşılaştırarak test edin. Bir test, App Store ziyaretçilerinin bir kısmına en fazla üç **varyasyon** (treatment; sayfanın farklı sürümleri) gösterir ve bunların dönüşüm oranlarını orijinal sayfanınkiyle karşılaştırır. Testlere ve varyasyonlara **ad** veya kimlikleriyle başvurulur.

## Listeleme ve inceleme

```bash
ascelerate experiments <bundle-id>
ascelerate experiments info <bundle-id> "Screenshot order"
```

`info` komutu testin durumunu, trafik payını ve tarihlerini, ayrıca her varyasyonu yerel ayarları ve yerel ayar başına medyasıyla birlikte gösterir. Her iki komut da `--json` kabul eder.

## Test oluşturma

```bash
ascelerate experiments create <bundle-id> --name "Screenshot order" --traffic 50 --treatment "Map first" --treatment "Alerts first"
```

`--traffic`, varyasyonlardan birini gören App Store ziyaretçilerinin yüzdesidir. Bu pay varyasyonlar arasında eşit olarak bölünür; geri kalan herkes orijinal sayfayı görür. `--platform` varsayılan olarak `ios` değerini alır.

## Varyasyonlar

```bash
ascelerate experiments treatments add <bundle-id> "Screenshot order" --name "Icon B" --app-icon AppIconB
ascelerate experiments treatments update <bundle-id> "Screenshot order" "Icon B" --name "Blue icon"
ascelerate experiments treatments delete <bundle-id> "Screenshot order" "Blue icon"
ascelerate experiments treatments remove-locale <bundle-id> "Screenshot order" "Map first" --locale de-DE
```

`--app-icon` alternatif bir uygulama simgesini test eder; simge, yayındaki build'de alternatif simge olarak bulunmalıdır. Bir varyasyonun kapsamadığı yerel ayarlarda, testteki ziyaretçilere de orijinal sayfa gösterilir.

## Medya

```bash
ascelerate experiments media list <bundle-id> "Screenshot order"
ascelerate experiments media upload <bundle-id> "Screenshot order" "Map first" --locale en-US --display-type APP_IPHONE_67 01.png
ascelerate experiments media upload <bundle-id> "Screenshot order" "Map first" --locale en-US --preview-type APP_IPHONE_67 preview.mp4
ascelerate experiments media delete <bundle-id> "Screenshot order" <media-id>
```

Yüklemeler [özel ürün sayfası medyası](product-pages.md) gibi çalışır: Görseller `--display-type` ile ekran görüntüsü setlerine, videolar `--preview-type` ile uygulama önizleme setlerine gider; `PRODUCT_PAGE_HEADER`, `APP_STORE_SEARCH_RESULTS` ve `APP_IPHONE_DUO` ise varlık kitaplığı üzerinden yüklenir. Varyasyonun yerel ayarı ilk yüklemede oluşturulur.

:::note
Yeni bir varyasyon yerel ayarı, **orijinal sayfanın medyasının bir kopyası** olarak başlar: App Store Connect onu mevcut sürümün ekran görüntüleri ve önizlemeleriyle doldurur. Yüklemeler bu kopyanın ardına eklenir; bu yüzden yerine yenisini koyduğunuz kopyalanmış ekran görüntülerini silin (`media list` kimliklerini gösterir).
:::

## İnceleme, başlatma ve durdurma

```bash
ascelerate experiments submit <bundle-id> "Screenshot order"
ascelerate experiments start <bundle-id> "Screenshot order"
ascelerate experiments stop <bundle-id> "Screenshot order"
```

Yeni medya içeren bir testin başlayabilmesi için App Review'dan geçmesi gerekir (`info` bunu belirtir). `submit`, yalnızca testi içeren bir inceleme gönderimi oluşturur ve gönderir. Platform için başka öğeler (örneğin bir uygulama sürümü) içeren bir taslak gönderim zaten varsa test bu gönderime eklenir ve [`apps review submit`](apps.md#submit-for-review) ile diğer öğelerle birlikte incelemeye gider. Test onaylandıktan sonra `start` testi çalıştırır, `stop` ise sonlandırır. Sonuçlar App Store Connect'te gösterilir.

## Güncelleme ve silme

```bash
ascelerate experiments update <bundle-id> "Screenshot order" --traffic 30
ascelerate experiments delete <bundle-id> "Screenshot order"
```

Her varyasyonda tek bir şeyi değiştirin (örneğin ilk ekran görüntüsünü veya simgeyi); böylece sonuç, farkı hangi değişikliğin yarattığını gösterir.
