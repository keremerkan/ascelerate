---
sidebar_position: 4
title: Ekran Görüntüleri ve Önizlemeler
---

# Ekran Görüntüleri ve Uygulama Önizlemeleri

## İndirme

```bash
ascelerate apps media download <bundle-id>
ascelerate apps media download <bundle-id> --folder my-media/ --version 2.1.0
```

Varsayılan olarak `<bundle-id>-media/` dizinine indirir, yükleme tarafından beklenen aynı klasör yapısını kullanır.

## Yükleme

```bash
# Bir klasörden yükleyin
ascelerate apps media upload <bundle-id> --folder media/

# Bir zip dosyasından yükleyin (ör. app-store-screenshots'tan dışa aktarılmış)
ascelerate apps media upload <bundle-id> --folder screenshots.zip

# Belirli bir sürüme yükleyin
ascelerate apps media upload <bundle-id> --folder media/ --version 2.1.0

# Yüklemeden önce eşleşen setlerdeki mevcut medyayı değiştirin
ascelerate apps media upload <bundle-id> --folder media/ --replace

# İnteraktif mod: geçerli dizinden bir klasör veya zip seçin
ascelerate apps media upload <bundle-id>
```

`--folder` belirtilmediğinde, komut geçerli dizindeki tüm alt dizinleri ve `.zip` dosyalarını numaralı seçici olarak listeler. Zip dosyaları yüklemeden önce otomatik olarak açılır.

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
ascelerate apps media upload <bundle-id> --folder screenshots.zip --replace
```

## Takılmış medyayı doğrulama ve yeniden deneme

Bazen ekran görüntüleri veya önizlemeler yüklemeden sonra "işleniyor" durumunda takılabilir. Durumu kontrol etmek ve isteğe bağlı olarak takılmış öğeleri yeniden denemek için `media verify` kullanın:

```bash
# Tüm ekran görüntüleri ve önizlemelerin durumunu kontrol edin
ascelerate apps media verify <bundle-id>

# Belirli bir sürümü kontrol edin
ascelerate apps media verify <bundle-id> --version 2.1.0

# Medya klasöründeki yerel dosyaları kullanarak takılmış öğeleri yeniden deneyin
ascelerate apps media verify <bundle-id> --folder media/
```

`--folder` olmadan komut salt okunur bir durum raporu gösterir. Tüm öğeleri tamamlanmış olan setler tek satırlık özet gösterir; takılmış öğeleri olan setler her dosyayı ve durumunu genişleterek gösterir. `--folder` ile takılmış öğeleri silip eşleşen yerel dosyalardan tekrar yüklemeyi teklif eder ve orijinal sıra düzenini korur.
