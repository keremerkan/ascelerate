---
sidebar_position: 4
title: Ekran Görüntüleri ve Önizlemeler
---

# Ekran Görüntüleri ve Uygulama Önizlemeleri

## İndirme

```bash
ascelerate apps media download <bundle-id>
ascelerate apps media download <bundle-id> --folder my-media/ --version 2.1.0
ascelerate apps media download <bundle-id> --locale en-US,tr
```

Varsayılan olarak `<bundle-id>-media/` dizinine indirir, yükleme tarafından beklenen aynı klasör yapısını kullanır.

`--locale`, indirmeyi verilen locale'lerle sınırlar (örn. `--locale en-US,tr`). iPhone Duo ekran görüntüleri ile başlık ve arama sonuçları görselleri de kaydedilir.

## Yükleme

```bash
# Bir klasörden yükleyin
ascelerate apps media upload <bundle-id> media/

# Bir arşivden yükleyin (zip, tar, tar.gz desteklenir)
ascelerate apps media upload <bundle-id> screenshots.zip

# Belirli bir sürüme yükleyin (evrensel satın alma kullanan uygulamalar için --platform ekleyin)
ascelerate apps media upload <bundle-id> media/ --version 2.1.0
ascelerate apps media upload <bundle-id> media/ --version 2.1.0 --platform macos

# Yüklemeden önce eşleşen setlerdeki mevcut medyayı değiştirin
ascelerate apps media upload <bundle-id> media/ --replace

# İnteraktif mod: geçerli dizinden bir klasör veya arşiv seçin
ascelerate apps media upload <bundle-id>
```

Klasör argümanı belirtilmediğinde, komut geçerli dizindeki tüm alt dizinleri ve arşiv dosyalarını numaralı seçici olarak listeler. Arşivler (zip, tar, tar.gz) yüklemeden önce otomatik olarak açılır.

Her dosyanın satırı, çalıştırmadaki sırasıyla başlar (`[57/203]`). Terminalde satır, dosya gönderilirken ne kadarının yüklendiğini de gösterir.

## Klasör yapısı

Medya klasörünü locale ve display type alt klasörleriyle düzenleyin:

```
media/
├── en-US/
│   ├── APP_IPHONE_67/
│   │   ├── 01_home.png
│   │   ├── 02_settings.png
│   │   └── preview.mp4
│   └── APP_IPAD_PRO_3GEN_129/
│       └── 01_home.png
└── de-DE/
    └── APP_IPHONE_67/
        ├── 01_home.png
        └── 02_settings.png
```

- **1. seviye:** Locale (ör. `en-US`, `de-DE`, `ja`)
- **2. seviye:** Display type klasör adı (aşağıdaki tabloya bak)
- **3. seviye:** Medya dosyaları -- görseller (`.png`, `.jpg`, `.jpeg`) ekran görüntüsü olur, videolar (`.mp4`, `.mov`) uygulama önizlemesi olur
- Dosyalar dosya adına göre alfabetik sırada yüklenir
- Desteklenmeyen dosyalar uyarıyla atlanır

## Display type'ları

App Store Connect, iPhone uygulamaları için **`APP_IPHONE_67`** ve iPad uygulamaları için **`APP_IPAD_PRO_3GEN_129`** ekran görüntülerini zorunlu tutar. Diğer tüm display type'lar isteğe bağlıdır.

| Klasör adı | Cihaz | Ekran görüntüleri | Önizlemeler |
|---|---|---|---|
| `APP_IPHONE_67` | iPhone 6.7" (iPhone 17 Pro Max, 16 Pro Max, 15 Pro Max) | **Zorunlu** | Evet |
| `APP_IPAD_PRO_3GEN_129` | iPad Pro 12.9" (3. nesil+) | **Zorunlu** | Evet |

<details>
<summary>Tüm isteğe bağlı display type'lar</summary>

| Klasör adı | Cihaz | Ekran görüntüleri | Önizlemeler |
|---|---|---|---|
| `APP_IPHONE_61` | iPhone 6.1" (iPhone 17 Pro, 16 Pro, 15 Pro) | Evet | Evet |
| `APP_IPHONE_65` | iPhone 6.5" (iPhone 11 Pro Max, XS Max) | Evet | Evet |
| `APP_IPHONE_58` | iPhone 5.8" (iPhone 11 Pro, X, XS) | Evet | Evet |
| `APP_IPHONE_55` | iPhone 5.5" (iPhone 8 Plus, 7 Plus, 6s Plus) | Evet | Evet |
| `APP_IPHONE_47` | iPhone 4.7" (iPhone SE 3. nesil, 8, 7, 6s) | Evet | Evet |
| `APP_IPHONE_40` | iPhone 4" (iPhone SE 1. nesil, 5s, 5c) | Evet | Evet |
| `APP_IPHONE_35` | iPhone 3.5" (iPhone 4s ve öncesi) | Evet | Evet |
| `APP_IPHONE_DUO` | iPhone Duo ([aşağıya](#iphone-duo) bakın) | Evet | Hayır |
| `PRODUCT_PAGE_HEADER` | Ürün sayfası başlığı ([aşağıya](#header-and-search-results) bakın) | Evet | Hayır |
| `APP_STORE_SEARCH_RESULTS` | App Store arama sonuçları ([aşağıya](#header-and-search-results) bakın) | Evet | Hayır |
| `APP_IPAD_PRO_3GEN_11` | iPad Pro 11" | Evet | Evet |
| `APP_IPAD_PRO_129` | iPad Pro 12.9" (1./2. nesil) | Evet | Evet |
| `APP_IPAD_105` | iPad 10.5" (iPad Air 3. nesil, iPad Pro 10.5") | Evet | Evet |
| `APP_IPAD_97` | iPad 9.7" (iPad 6. nesil ve öncesi) | Evet | Evet |
| `APP_DESKTOP` | Mac | Evet | Evet |
| `APP_APPLE_TV` | Apple TV | Evet | Evet |
| `APP_APPLE_VISION_PRO` | Apple Vision Pro | Evet | Evet |
| `APP_WATCH_ULTRA` | Apple Watch Ultra | Evet | Hayır |
| `APP_WATCH_SERIES_10` | Apple Watch Series 10 | Evet | Hayır |
| `APP_WATCH_SERIES_7` | Apple Watch Series 7 | Evet | Hayır |
| `APP_WATCH_SERIES_4` | Apple Watch Series 4 | Evet | Hayır |
| `APP_WATCH_SERIES_3` | Apple Watch Series 3 | Evet | Hayır |
| `IMESSAGE_APP_IPHONE_67` | iMessage iPhone 6.7" | Evet | Hayır |
| `IMESSAGE_APP_IPHONE_61` | iMessage iPhone 6.1" | Evet | Hayır |
| `IMESSAGE_APP_IPHONE_65` | iMessage iPhone 6.5" | Evet | Hayır |
| `IMESSAGE_APP_IPHONE_58` | iMessage iPhone 5.8" | Evet | Hayır |
| `IMESSAGE_APP_IPHONE_55` | iMessage iPhone 5.5" | Evet | Hayır |
| `IMESSAGE_APP_IPHONE_47` | iMessage iPhone 4.7" | Evet | Hayır |
| `IMESSAGE_APP_IPHONE_40` | iMessage iPhone 4" | Evet | Hayır |
| `IMESSAGE_APP_IPAD_PRO_3GEN_129` | iMessage iPad Pro 12.9" (3. nesil+) | Evet | Hayır |
| `IMESSAGE_APP_IPAD_PRO_3GEN_11` | iMessage iPad Pro 11" | Evet | Hayır |
| `IMESSAGE_APP_IPAD_PRO_129` | iMessage iPad Pro 12.9" (1./2. nesil) | Evet | Hayır |
| `IMESSAGE_APP_IPAD_105` | iMessage iPad 10.5" | Evet | Hayır |
| `IMESSAGE_APP_IPAD_97` | iMessage iPad 9.7" | Evet | Hayır |

</details>

:::note
Watch ve iMessage display type'lar yalnızca ekran görüntülerini destekler -- bu klasörlerdeki video dosyaları uyarıyla atlanır. `--replace` flag'i, yenilerini yüklemeden önce eşleşen her setteki tüm mevcut varlıkları siler.
:::

### iPhone Duo

App Store Connect'te iPhone Duo için bir ekran görüntüsü seti yoktur. ascelerate, `APP_IPHONE_DUO` klasöründeki dosyaları uygulamanın varlık kitaplığına yükler ve dosya sırasıyla sürüm yerelleştirmesine yerleştirir. Kabul edilen boyutlar şunlardır: 2853×2007 veya 2007×2853 (iç ekran, açık konumda), 2034×1398 veya 1398×2034 (dış ekran). Diğer boyutlar, herhangi bir şey yüklenmeden önce reddedilir. `--replace` ile her locale'deki mevcut iPhone Duo ekran görüntüleri önce kaldırılır.

Klasör, iPhone Duo uygulama önizlemelerini de (`.mp4`, `.m4v` veya `.mov`) içerebilir: 1920×886 veya 886×1920, 23–30 fps'de 15–30 saniye, ses kanalıyla. Önizlemeler locale'in mevcut önizlemelerinin ardına eklenir; `--replace` ile mevcut olanlar önce kaldırılır. Ekran görüntüleri ve önizlemeler ayrı ayrı ve yalnızca klasörde o türden dosya olduğunda değiştirilir.

Yeniden denemelere rağmen yüklenemeyen bir dosya olursa `media upload`, o locale'in iPhone Duo ekran görüntülerini veya önizlemelerini çalışmanın sonunda yeniden yerleştirir; böylece dosya sırası korunur. `media verify` bunları dosya adları ve işlenme durumlarıyla listeler. Medya klasörü verildiğinde, dosyaları ya da sırası klasörden farklı olan locale'leri de bildirir (düzeltmek için `media upload` komutunu `--replace` ile çalıştırın). `media download` ekran görüntülerini kendi dosya adlarıyla kaydeder; `media prune` ise bunları hiçbir zaman silmez.

### Ürün sayfası başlığı ve arama sonuçları {#header-and-search-results}

İki klasör daha varlık kitaplığı üzerinden yüklenir. Her biri locale başına, bir cihaz sınıfına bağlı olmayan tek bir görsel veya video tutar: Sürüm bunu her cihazda (iPhone, iPad, iPhone Duo) gösterir ve klasörler tüm platformların sürümlerinde kullanılabilir.

- `PRODUCT_PAGE_HEADER`: ürün sayfasının üst kısmındaki görsel veya video. 3840×1646 veya 5244×2950 PNG ya da 30 veya 60 fps'de 5–30 saniyelik 3840×1646 video.
- `APP_STORE_SEARCH_RESULTS`: App Store arama sonuçlarında uygulamayla birlikte gösterilir. 1920×1280 ile 3840×2560 arasında 3:2 oranlı JPG veya PNG ya da 5244×2950 PNG; veya aynı boyut aralığında, 30 veya 60 fps'de 5–30 saniyelik 3:2 oranlı video.

Yükleme, `--replace` kullanılsın ya da kullanılmasın, locale'in mevcut görselini veya videosunu değiştirir; eskisi ancak yenisi yüklendikten sonra kaldırılır. Yeni bir video birkaç dakika işlenir; `media verify` bunu gösterir. `media download` görselleri kaydeder; App Store Connect bu videolar için indirme bağlantısı vermez.

Özel ürün sayfaları aynı dosyaları `product-pages media upload` ile `--display-type PRODUCT_PAGE_HEADER`, `APP_STORE_SEARCH_RESULTS` veya `APP_IPHONE_DUO` vererek kabul eder.

## app-store-screenshots ile kullanım

[app-store-screenshots](https://github.com/keremerkan/ascelerate/tree/main/skills/app-store-screenshots), yapay zeka kodlama ajanları için üretime hazır App Store ekran görüntüleri oluşturan yardımcı bir skill'dir. `ascelerate screenshot frame` ile çerçevelenmiş cihaz ekran görüntülerini kullanarak reklam tarzı pazarlama düzenleri oluşturan bir Next.js sayfası yaratır ve bunları `ascelerate apps media upload` ile yüklenmeye hazır zip dosyası olarak dışa aktarır:

```
en-US/APP_IPHONE_67/01_hero.png
en-US/APP_IPAD_PRO_3GEN_129/01_hero.png
de-DE/APP_IPHONE_67/01_hero.png
```

Skill'i yapay zeka kodlama ajanınıza yükleyin:

```bash
npx skills add keremerkan/ascelerate
```

Dışa aktarılan zip'i doğrudan yükleyin:

```bash
ascelerate apps media upload <bundle-id> screenshots.zip --replace
```

## Takılmış medyayı doğrulama ve yeniden deneme

Bazen ekran görüntüleri veya önizlemeler yüklemeden sonra "işleniyor" durumunda takılabilir. Durumu kontrol etmek ve isteğe bağlı olarak takılmış öğeleri yeniden denemek için `media verify` kullanın:

```bash
# Tüm ekran görüntüleri ve önizlemelerin durumunu kontrol edin
ascelerate apps media verify <bundle-id>

# Belirli bir sürümü kontrol edin
ascelerate apps media verify <bundle-id> --version 2.1.0

# Medya klasöründeki yerel dosyaları kullanarak takılmış öğeleri yeniden deneyin
ascelerate apps media verify <bundle-id> media/
```

Klasör argümanı olmadan komut salt okunur bir durum raporu gösterir. Tüm öğeleri tamamlanmış olan setler tek satırlık özet gösterir; takılmış öğeleri olan setler her dosyayı ve durumunu genişleterek gösterir. Klasör argümanı ile takılmış öğeleri silip eşleşen yerel dosyalardan tekrar yüklemeyi teklif eder ve orijinal sıra düzenini korur.

## Eski Setleri Temizleme

Yükleme sırasındaki `--replace` yalnızca yerel bir klasörle eşleşen setleri boşaltır; artık sunmadığınız ekran boyutlarına ait sunucu setleri eski ekran görüntülerini korur. `media prune`, eşleşen yerel locale/display-type klasörü olmayan setleri, öğe sayılarıyla birlikte listeleyip onay aldıktan sonra siler:

```bash
ascelerate apps media prune <bundle-id> media/
ascelerate apps media prune <bundle-id> media/ --version 2.1.0 --platform ios
```

Yerel klasörü olmayan locale'ler tamamen atlanır; komut yalnızca klasörün gerçekten yönettiği locale'ler içinde temizlik yapar.

## Varlık kitaplığı görsellerini kaldırma

`media remove`, varlık kitaplığı öğelerinden bir türü sürümden kaldırır: `PRODUCT_PAGE_HEADER` veya `APP_STORE_SEARCH_RESULTS` görseli ya da videosu veya `APP_IPHONE_DUO` ekran görüntüleri (uygulama önizlemeleri için `--previews`). Komut, `--locale` ile verilen locale'lerde ya da hepsinde çalışır ve onay istemeden önce bulduklarını listeler:

```bash
ascelerate apps media remove <bundle-id> PRODUCT_PAGE_HEADER --locale en-US
ascelerate apps media remove <bundle-id> APP_STORE_SEARCH_RESULTS
ascelerate apps media remove <bundle-id> APP_IPHONE_DUO --locale en-US,tr --version 2.1.0
ascelerate apps media remove <bundle-id> APP_IPHONE_DUO --previews --locale en-US
```

## Varlık kitaplığını temizleme

Her uygulamanın yüklenen görselleri ve videoları tutan bir varlık kitaplığı vardır ve sürümler bu görselleri paylaşır: Yeni bir sürümün ekran görüntüleri önceki sürümün görselleridir ve eski sürümler kendi görsellerini korur. Bu nedenle bir görsel, herhangi bir sürüm (eskiler dahil), özel ürün sayfası veya etkinlik onu kullandığı sürece kullanımda kalır. ascelerate bir yerleşimi kaldırdığında (`media remove`, `media upload --replace` ya da bir başlık veya arama sonuçları görselinin değiştirilmesi), görseli artık hiçbir şey kullanmıyorsa ve görsel hiç App Review'dan geçmemişse görseli veya videoyu da siler.

Önceki yüklemeler kitaplıkta yine de kullanılmayan görseller ve videolar bırakmış olabilir. `media library` görselleri ve videoları sayar ve kullanılmayanları listeler; `--delete-unused` ile bunları onay aldıktan sonra siler:

```bash
ascelerate apps media library <bundle-id>
ascelerate apps media library <bundle-id> --delete-unused
ascelerate apps media library <bundle-id> --only APP_IPHONE_DUO --delete-unused
```

`--only`, listeyi varlık kategorisine ve piksel boyutuna bakarak verilen türlere uyan görsellerle sınırlar: `PRODUCT_PAGE_HEADER`, `APP_STORE_SEARCH_RESULTS`, `APP_IPHONE_DUO`, `APP_IPHONE_67` gibi bir ekran görüntüsü görüntüleme türü (boyutlar App Store Connect'ten alınır) ya da dosyası hiç gelmemiş yüklemeler için `UNFINISHED_UPLOADS`. Böylece kitaplık cihaz türü cihaz türü temizlenebilir. Bir saatten yeni görseller her zaman korunur, çünkü aynı anda çalışan bir yükleme onları yerleştirmek üzere olabilir; App Store Connect'in saatlik API sınırına ulaşan bir çalıştırma durur ve daha sonra yeniden çalıştırmanızı ister.

App Review'dan geçmiş görseller, yerleştirilmiş olsun ya da olmasın hiçbir zaman silinmez ve her görsel silinmeden hemen önce yeniden denetlenir.
