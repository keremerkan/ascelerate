---
sidebar_position: 16
title: Raporlar
---

# Raporlar

Satış ve Trend, Finansal ve App Analytics raporlarını indirin. Satış ve Finans raporları Apple'ın gzip ile sıkıştırılmış TSV biçiminde gelir; `ascelerate` bunları açar ve bir özet yazdırır (veya ham dosyayı kaydeder). App Analytics, Apple'ın asenkron rapor isteği akışıyla alınır.

:::note Satıcı numarası
`reports sales` ve `reports finance` komutları **satıcı numaranızı** gerektirir (App Store Connect → Payments and Financial Reports, örn. `80012345`). Bunu `ascelerate configure` ile bir kez kaydedin veya her komutta `--vendor-number` ile geçin. `reports analytics` buna ihtiyaç duymaz.
:::

## Sales

Birim sayıları (indirmeler), gelirler ve uygulama içi satın alma/abonelik etkinliği. Varsayılan olarak uygulamaya ve ürün türüne göre gruplanmış, ayrıştırılmış bir özet gösterir; TSV'yi yazdırmak için `--raw`, kaydetmek için `--output` ekleyin.

```bash
ascelerate reports sales
ascelerate reports sales --frequency WEEKLY
ascelerate reports sales --frequency MONTHLY --date 2026-05
ascelerate reports sales --frequency YEARLY --date 2025 --bundle-id com.example.App
ascelerate reports sales --frequency DAILY --date 2026-06-20 --output sales.tsv
```

- `--frequency`: `DAILY`, `WEEKLY`, `MONTHLY` veya `YEARLY` (varsayılan `DAILY`).
- `--date`: Günlük/haftalık için `YYYY-MM-DD` (haftalık = haftayı bitiren Pazar günü), aylık için `YYYY-MM`, yıllık için `YYYY`. Varsayılan olarak en son tamamlanmış dönemdir.
- `--type`: Rapor türü (varsayılan `SALES`); diğerleri arasında `SUBSCRIPTION`, `SUBSCRIBER`, `SUBSCRIPTION_EVENT`, `INSTALLS`, `PRE_ORDER` bulunur.
- `--sub-type`: `SUMMARY` (varsayılan), `DETAILED`, `SUMMARY_TERRITORY`, `SUMMARY_CHANNEL`, `SUMMARY_INSTALL_TYPE`.
- `--bundle-id`: Özeti tek bir uygulamayla (veya takma adla) sınırlar.
- `--vendor-number`: Yapılandırılmış satıcı numarasını geçersiz kılar.
- `--output` / `--raw`: Ham TSV'yi bir dosyaya kaydeder veya özet yerine yazdırır.

Özet, birimleri başlığa ve **ürün türü tanımlayıcısına** göre gruplar. Tek bir rapor ilk kez indirmeleri (`1*`/`3*`), güncellemeleri (`7*`) ve uygulama içi satın almaları (`IA*`) bir arada içerdiğinden bu gruplama yararlıdır. Tüm veriler için `--raw` kullanın.

## Finance

Bir mali dönem için, bölgeye göre birim sayıları ve iş ortağı gelirleri.

```bash
ascelerate reports finance --date 2026-05 --region US
ascelerate reports finance --date 2026-05 --region US --type FINANCE_DETAIL --output finance.tsv
```

- `--date`: `YYYY-MM` biçiminde mali dönem; buradaki ay, takvim ayı değil Apple'ın **mali dönemidir (01–12)**. Zorunludur.
- `--region`: Bölge kodu, örn. `US`, `EU`, `GB`, `JP`, `AU`, `WW` (dünya geneli). Zorunludur.
- `--type`: `FINANCIAL` (varsayılan) veya `FINANCE_DETAIL`.
- `--vendor-number`, `--output`, `--raw`: Yukarıdaki gibi.

Özet, miktarı başlığa ve geliri para birimine göre toplar.

## Analytics

App Analytics rapor verileri: indirmeler, gösterimler, ürün sayfası görüntülemeleri, oturumlar ve daha fazlası. Apple bunları asenkron olarak oluşturur: komut, uygulama için bir rapor isteği bulur (veya onayınızla oluşturur) ve ardından raporun bölümlerini indirir.

```bash
ascelerate reports analytics <bundle-id>
ascelerate reports analytics <bundle-id> --category APP_USAGE --granularity WEEKLY
ascelerate reports analytics <bundle-id> --report-name "App Store Discovery and Engagement Detailed" --output ./analytics
```

- `--category`: `APP_STORE_ENGAGEMENT` (varsayılan), `APP_USAGE`, `COMMERCE`, `FRAMEWORK_USAGE`, `PERFORMANCE`.
- `--granularity`: `DAILY` (varsayılan), `WEEKLY`, `MONTHLY`.
- `--report-name`: Bir kategori birden fazla rapor içerdiğinde belirli bir raporu seçer.
- `--processing-date`: İndirilecek örnek (`YYYY-MM-DD`); varsayılan olarak en günceli.
- `--ongoing`: Tek seferlik anlık görüntü yerine sürekli bir rapor isteği kullanır.
- `--output`: İndirilen bölüm dosyaları için dizin (varsayılan `./<app>-analytics`).

Yeni oluşturulan bir anlık görüntü hemen hazır olmaz; Apple'ın bunu oluşturması zaman alır. Bölümleri indirmek için komutu birkaç dakika sonra yeniden çalıştırın.

:::info Puanlar
App Store Connect API, toplam puan sayılarını veya yıldız puanı ortalamasını/histogramını sunmaz; yalnızca tek tek değerlendirmeleri sunar (bkz. [Müşteri Değerlendirmeleri](./reviews.md)). İndirme ve gelir rakamları için yukarıdaki raporları kullanın.
:::
