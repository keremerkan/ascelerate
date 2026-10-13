---
sidebar_position: 21
title: Apple Ads
---

# Apple Ads

Apple Ads (eski adıyla Search Ads) kampanyalarını Apple Ads Platform API üzerinden komut satırından yönetin: performans raporları, kampanyalar, reklam grupları, anahtar kelimeler ve negatif anahtar kelimeler, teklifler ve bütçeler, Apple'ın önerileri ve anahtar kelime araştırma verileri. Uygulamalar App Store Connect ile eşleştirilir; bu yüzden `--app`, diğer tüm komutlarla aynı bundle ID'leri ve [takma adları](../getting-started/aliases.md) kabul eder. Kampanyalara ve reklam gruplarına **ad** (büyük/küçük harf duyarsız) veya kimlikleriyle başvurulur; yanlış bir ad verildiğinde geçerli adlar listelenir.

Bir şeyi değiştiren her komut önce onay ister (`-y` bunu atlar); `--dry-run` ise gönderilecek istekleri göndermeden olduğu gibi yazdırır ([deneme çalıştırması](../guides/automation.md#dry-run)). Değişiklikler gerçek para harcatır; bu yüzden önce `--dry-run` ile deneyin. Tutarlar reklam hesabının para birimindedir.

## Kurulum

Apple Ads, App Store Connect API anahtarınızdan ayrı, kendi kimlik bilgilerini kullanır:

1. Apple Ads hesabınızda **Account Settings → User Management** bölümüne gidin, **API** rolüne sahip bir kullanıcı (örneğin API Account Manager) davet edin ve daveti o kullanıcının Apple Hesabı ile kabul edin.
2. Kurulumu çalıştırın:

```bash
ascelerate ads configure
```

ascelerate anahtar çiftini oluşturur ve genel anahtarı yazdırır. API kullanıcısıyla Apple Ads hesabına giriş yapın, anahtarı **Account Settings → API** bölümüne yapıştırın ve orada gösterilen client ID, team ID ve key ID değerlerini girin. ascelerate ardından kullanıcının erişebildiği reklam hesaplarını listeler ve seçtiğiniz hesabı `~/.ascelerate/config.json` dosyasındaki bir `ads` bölümüne kaydeder. `--new-key` yeni bir anahtar çifti oluşturur.

```bash
ascelerate ads accounts          # API kullanıcısının reklam hesapları ve rolleri
```

## Raporlar

```bash
ascelerate ads reports campaigns --days 30
ascelerate ads reports campaigns --from 2026-09-01 --to 2026-09-30 --app myapp
ascelerate ads reports campaigns --campaign "MyApp US" --by device
ascelerate ads reports adgroups --campaign "MyApp US"
ascelerate ads reports ads --campaign "MyApp US"
ascelerate ads reports keywords --campaign "MyApp US"
ascelerate ads reports search-terms --app myapp --days 14
```

| Rapor | Satırlar |
|---|---|
| `campaigns` | Kampanyalar; `--by age gender device country region city` bunları kırılımlara ayırır |
| `adgroups` | Reklam grupları (örneğin test gruplarını karşılaştırmak için) |
| `ads` | Reklamlar, yani her reklam grubunun dokunmaları yönlendirdiği ürün sayfası |
| `keywords` | Anahtar kelimeler ve Apple'ın önerdiği teklif |
| `search-terms` | Kullanıcıların gerçekte ne aradığı, eşleşen anahtar kelime ve eşleşmenin sizin anahtar kelimelerinizden mi yoksa Search Match'ten mi geldiği |

Tüm raporlar `--days N` (bugün dahil) veya `--from`/`--to`, `--app`, `--campaign`, `--all` (etkinliği olmayan satırları da gösterir) ve `--json` seçeneklerini kabul eder. Tarihler reklam hesabının saat dilimindedir. Karar verirken tamamlanmış günleri karşılaştırın: Bugünün rakamları henüz kesinleşmedi.

Her satır harcamayı, gösterimleri, dokunmaları, yüklemeleri, dokunma oranını (TTR), dokunma başına (CPT) ve yükleme başına (CPI) ortalama maliyeti ve iki dönüşüm oranını gösterir:

- **CR (Tap)**: dokunmanın ardından gelen yüklemelerin dokunmalara oranı. Ürün sayfanızın, dokunan kullanıcıları ne kadar iyi dönüştürdüğünü gösterir.
- **CR (Total)**: görüntüleme sonrası yüklemeler (reklamı görüp dokunmadan daha sonra yükleyen kullanıcılar) dahil tüm yüklemelerin dokunmalara oranı. Yüzde 100'ü aşabilir.

:::note
Apple yaşı, cinsiyeti ve ülkeden daha ayrıntılı konumu yalnızca Kişiselleştirilmiş Reklamlar'a izin veren kullanıcılar için bilir; bu yüzden bu kırılımlar neredeyse tamamen "Unknown" olarak gelir. Cihaz kırılımları eksiksizdir. Apple'ın gizlilik nedeniyle göstermediği arama terimleri "(low volume)" olarak görünür.
:::

## Kampanyalar

```bash
ascelerate ads campaigns list --app myapp
ascelerate ads campaigns pause "MyApp US"
ascelerate ads campaigns resume "MyApp US"
ascelerate ads campaigns budget "MyApp US" --daily 120
ascelerate ads campaigns bid "MyApp US Max Conv" --amount 2.50
```

`list`, her kampanyanın durumunu, ülkelerini, günlük bütçesini ve teklif yöntemini (Manual CPT veya Max Conversions) gösterir. Max Conversions kampanyalarında `bid`, tek bir açık artırmada ödenebilecek en yüksek tutarı belirler. Bu tutarı bir yüklemenin sizin için değerine göre ayarlayın; ülke mağazasındaki olağan dokunma başına maliyetin altında kalan bir tavan, kampanyayı trafiksiz bırakır.

### Kampanya oluşturma

```bash
ascelerate ads campaigns create --like "MyApp US" --name "MyApp US Max Conv" --max-conversions --bid 2.50 --daily 25
ascelerate ads campaigns create --app myapp --name "MyApp DE" --country DE --daily 20 --default-bid 1.00 --search-match off
```

Kampanya, reklam grubuyla birlikte **duraklatılmış** olarak oluşturulur: Max Conversions için otomatik bir reklam grubu, `--default-bid` ile ise manuel bir reklam grubu. `--like`, mevcut bir kampanyanın uygulamasını, ülkelerini ve ayarlarını kopyalar. `--enabled` kampanyayı hemen başlatır.

```bash
ascelerate ads campaigns target-cpa --app myapp --country US
```

Yeni bir Max Conversions kampanyası için Apple'ın önerdiği hedef yükleme başına maliyeti gösterir.

:::tip
Bir uygulamanın aynı ülke mağazasındaki kampanyaları birbiriyle rekabet etmez: Apple her açık artırmaya bunlardan yalnızca birini alır. Bu yüzden çalışan bir kampanyanın yanına açılan yeni bir kampanya yalnızca geriye kalan trafiği alır. Yeni bir kampanyayı denemek için trafiği ona taşıyın; örneğin eskisini yalnızca marka adınızla sınırlayın.
:::

## Reklam grupları

```bash
ascelerate ads adgroups --campaign "MyApp US"
ascelerate ads adgroups create --campaign "MyApp US" --name "Exact" --search-match off
ascelerate ads adgroups create --campaign "MyApp US" --name "Adults" --like "US Ad Group" --min-age 25
ascelerate ads adgroups update "Exact" --campaign "MyApp US" --default-bid 1.20
ascelerate ads adgroups pause "Exact" --campaign "MyApp US"
ascelerate ads adgroups resume "Exact" --campaign "MyApp US"
```

`create`, mevcut bir reklam grubunun fiyatlandırmasını, teklif ayarlarını ve hedeflemesini kopyalar (`--like` ile verilen grubu ya da kampanyanın tek grubunu); `--enabled` verilmedikçe yeni grup **duraklatılmış** olarak oluşturulur. `--min-age`/`--max-age` 18 ile 64 arasındaki yaşları hedefler (`--max-age` verilmezse 65 yaş ve üstü de hedeflenir). Yaş hedeflemesi yalnızca Kişiselleştirilmiş Reklamlar'a izin veren kullanıcılara ulaşır ve Apple, yaş hedefli reklam gruplarından gelen yüklemeleri diğer araçlarda kampanyaya atfetmez; bu yüzden bu grupları Apple Ads rakamlarına göre değerlendirin.

## Anahtar kelimeler ve negatif anahtar kelimeler

```bash
ascelerate ads keywords list --campaign "MyApp US"
ascelerate ads keywords add --campaign "MyApp US" --match exact --bid 1.50 "qr scanner" "barcode reader"
ascelerate ads keywords bid --campaign "MyApp US" --bid 1.25 "qr scanner"
ascelerate ads keywords pause --campaign "MyApp US" "barcode reader"
ascelerate ads keywords copy --campaign "MyApp US" --from "US Ad Group" --to "Exact"

ascelerate ads negatives list --campaign "MyApp US"
ascelerate ads negatives add --campaign "MyApp US" "free wifi"
ascelerate ads negatives add --campaign "MyApp US" --ad-group "Discovery" --match broad "wifi"
ascelerate ads negatives remove --campaign "MyApp US" "free wifi"
```

Bir kampanyada birden fazla reklam grubu olduğunda hangisinin kullanılacağını `--ad-group` belirler. Negatif anahtar kelimeler, `--ad-group` verilmedikçe kampanya düzeyindedir ve `--match broad` verilmedikçe tam eşleme kullanır. `keywords add` zaten var olan anahtar kelimeleri atlar. Max Conversions kampanyaları tekliflerini kendileri belirlediğinden anahtar kelime teklifleri bu kampanyalara uygulanmaz.

## Değişiklik önerileri

```bash
ascelerate ads opportunities --app myapp
ascelerate ads opportunities --campaign "MyApp US" --days 60 --min-taps 20 --brand "my app"
```

`opportunities`, bir kampanyanın arama terimlerini (varsayılan olarak son 30 tamamlanmış gün) kampanyanın anahtar kelimeleri ve kendi ortalamalarıyla karşılaştırır ve şunları önerir:

- **Tam eşlemeli anahtar kelime olarak ekleme**: kendine ait tam eşlemeli bir anahtar kelimesi olmayan, iyi bir yükleme başına maliyetle dönüşüm sağlayan bir arama terimi.
- **Ayrı teklif verme**: dönüşüm sağlayan ama başka bir anahtar kelimenin teklifiyle, daha yüksek maliyetle gösterilen bir terim.
- **Hariç tutma**: gerçek harcaması olup hiç yükleme getirmeyen ya da maliyeti veya dönüşüm oranı çok daha kötü olan bir terim.

Uygulamanızın adına yapılan aramalar ortalamalara katılmaz ve hiçbir zaman negatif anahtar kelime olarak önerilmez; markanızın diğer yazılışlarını `--brand` ile ekleyin. Sonuçları birer aday olarak görün ve harekete geçmeden önce her terimin uygulamanızla ilgili olduğunu kontrol edin.

```bash
ascelerate ads recommendations
ascelerate ads recommendations apply <id>
ascelerate ads recommendations dismiss <id>
```

Apple'ın açıktaki önerilerini (günlük bütçe ve hedef CPA değişiklikleri) beklenen sonuçlarıyla birlikte gösterir.

```bash
ascelerate ads history --app myapp --days 7
```

Son altı ayda kampanyalarda, reklam gruplarında, anahtar kelimelerde ve negatif anahtar kelimelerde yapılan tüm değişiklikleri, Apple Ads web sitesinde veya Apple tarafından yapılanlar dahil, eski ve yeni değerleriyle gösterir. Performanstaki bir değişikliği yorumlamadan önce bakmak işe yarar.

## Anahtar kelime araştırması

```bash
ascelerate ads keywords suggest --app myapp --seed "qr code" "barcode" --country US GB
ascelerate ads keywords popularity --app myapp --country US --term "qr code" "qr scanner"
ascelerate ads keywords popularity --genre PRODUCTIVITY_UTILITIES --country US --contains scanner
ascelerate ads insights impression-share --app myapp --country US --weeks 4
```

- `suggest`, verdiğiniz başlangıç terimleri için Apple'ın anahtar kelime önerilerini, popülerlikleri ve bunları zaten nerede hedeflediğinizle birlikte getirir.
- `popularity`, arama terimlerinin bir ülke mağazasında (1 ile 100 arası) ve uygulamanın türünde (genre) ne kadar popüler olduğunu gösterir. Türün sıralı listesinde yer almayan terimler ayrıca listelenir.
- `impression-share`, reklamlarınızın göründüğü arama terimlerinde gösterim payınızı ve sıranızı gösterir. Popüler ve dönüşüm sağlayan bir terimde düşük pay büyüme fırsatı demektir; kendi marka adınızda yüzde 100'ün altında kalan bir pay ise rakiplerin bu ada teklif verdiğini gösterir.

Popülerlik verileri, App Store anahtar kelime (ASO) seçimleriniz için de işe yarar.

## Reklamlar ve özel ürün sayfaları

```bash
ascelerate ads product-pages --app myapp
ascelerate ads ads --campaign "MyApp US"
ascelerate ads ads create --campaign "MyApp US" --ad-group "Scanner" --product-page "Scanner Page" --enabled
ascelerate ads ads pause "Scanner Page ad" --campaign "MyApp US"
```

Bir reklam, bir reklam grubunun dokunmalarını bir ürün sayfasına yönlendirir. Sizin oluşturduğunuz bir reklamı olmayan reklam grupları varsayılan ürün sayfasını kullanır. Belirli bir ihtiyaca yönelik aramaları bir [özel ürün sayfasına](product-pages.md) yönlendirmek için bu aramalara ayrı bir reklam grubu açın (`adgroups create`, `keywords add`) ve o grup için bir reklam oluşturun. Her reklam grubunda aynı anda yalnızca bir reklam yayında olabilir; bu yüzden `--enabled` o ana kadar yayında olan reklamı duraklatır. Apple yeni reklamları inceler; `ads ads` inceleme durumlarını gösterir.

## Yapay zeka ajanıyla kullanım

[ascelerate skill'i](../guides/ai-skill.md), yapay zeka kodlama ajanlarına bu raporları nasıl okuyacaklarını ve ne zaman değişiklik önereceklerini öğretir. Böylece bir ajandan kampanyalarınızı tüm uygulamalarınızda gözden geçirmesini, eklenecek veya hariç tutulacak anahtar kelimeleri bulmasını ya da performanstaki bir değişikliği açıklamasını isteyebilirsiniz. Her komut `--json` kabul eder; ajanlardan da bir şey gönderilmeden önce önerilen değişiklikleri size göstermeleri ve `--dry-run` kullanmaları istenir.
