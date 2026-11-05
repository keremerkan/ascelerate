---
sidebar_position: 7
title: Abonelikler
---

# Abonelikler

## Listeleme ve inceleme

```bash
ascelerate sub groups <bundle-id>
ascelerate sub list <bundle-id>
ascelerate sub info <bundle-id> <product-id>
```

Üç komut da makine tarafından okunabilir çıktı için `--json` seçeneğini kabul eder ([kurallar](../guides/automation.md#json-output)); `info`, eksik fiyat uyarısını `hasPricing` boolean'ı olarak raporlar.

## Abonelik oluşturma, güncelleme ve silme

```bash
ascelerate sub create <bundle-id> --name "Monthly" --product-id <product-id> --period ONE_MONTH --group-id <group-id>
ascelerate sub update <bundle-id> <product-id> --name "Monthly Plan"
ascelerate sub delete <bundle-id> <product-id>
```

## Abonelik grupları

```bash
ascelerate sub create-group <bundle-id> --name "Premium"
ascelerate sub update-group <bundle-id> --name "Premium Plus"
ascelerate sub delete-group <bundle-id>
```

## İncelemeye gönderme

```bash
ascelerate sub submit <bundle-id> <product-id>
```

Bir ürün, bekleyen bir sürümü olduğunda gönderilebilir; bu, Prepare for Submission, Ready for Review veya reddedilmiş durumdaki herhangi bir sürümdür. Son onayından sonra düzenlenen onaylı ürünler de buna dahildir. Bekleyen sürüm yoksa komut, herhangi bir istek göndermeden durur. `sub info`, varsa bekleyen sürümü gösterir.

## Abonelik yerelleştirmeleri

```bash
ascelerate sub localizations view <bundle-id> <product-id>
ascelerate sub localizations export <bundle-id> <product-id>
ascelerate sub localizations import <bundle-id> <product-id> --file sub-de.json
```

## Grup yerelleştirmeleri

```bash
ascelerate sub group-localizations view <bundle-id>
ascelerate sub group-localizations export <bundle-id>
ascelerate sub group-localizations import <bundle-id> --file group-de.json
```

İçe aktarma komutları eksik locale'leri onay ile otomatik olarak oluşturur, böylece App Store Connect'i ziyaret etmeden yeni diller ekleyebilirsiniz.

## Fiyatlandırma

Abonelik fiyatlandırması bölgeye özeldir. IAP'lerde olduğu gibi otomatik eşitleme kavramı yoktur; fiyatlamak istediğiniz her bölgenin kendi kaydı olmalıdır. CLI ya tek bir bölgeyi ayarlar ya da Apple'ın yerel para birimi kademe karşılıklarını kullanarak fiyatı tüm bölgelere yayar.

```bash
# Mevcut bölgeye özel fiyatları göster (yoksa uyarır)
ascelerate sub pricing show <bundle-id> <product-id>

# Fiyatları JSON olarak göster (bölge başına fiyat, para birimi, başlangıç tarihi ve koruma bayrağı)
ascelerate sub pricing show <bundle-id> <product-id> --json

# Bir bölgedeki mevcut fiyat kademelerini listele
ascelerate sub pricing tiers <bundle-id> <product-id> --territory USA

# Tek bir bölge için fiyat ayarla
ascelerate sub pricing set <bundle-id> <product-id> --price 4.99 --territory USA

# Tüm bölgelere fiyatı yay (her bölge için bir POST)
ascelerate sub pricing set <bundle-id> <product-id> --price 4.99 --equalize-all-territories
```

### Fiyat değişiklikleri ve mevcut aboneler

Apple, fiyat değişikliklerini değişikliğin yönüne göre mevcut aboneler için farklı şekilde uygular. `sub pricing set` komutu her etkilenen bölgenin mevcut fiyatını alır, değişikliği sınıflandırır ve doğru davranışı uygular:

- **Düşürme**: mevcut aboneler otomatik olarak düşük fiyata geçer. Etkileşimli çalıştırmalarda uyarı ile birlikte sorulur. `--yes` modunda, gelir etkisini onaylamak için `--confirm-decrease` eklemeniz gerekir; sadece `--yes` yeterli değildir.
- **Artış**: mevcut abonelerle nasıl başa çıkılacağını açıkça seçmeniz gerekir. Aşağıdakilerden biri ayarlanmadığı sürece komut hata verir:
  - `--preserve-current`: mevcut aboneleri eski fiyatlarında tutar
  - `--no-preserve-current`: Apple'ın bildirim süresinden sonra yeni fiyatı mevcut abonelere uygular
- **Yeni bölge** (mevcut fiyat yok): değerlendirilecek mevcut abone yok; bayraklar isteğe bağlıdır.
- **Değişiklik yok**: sessizce atlanır.

`--equalize-all-territories` için aynı kurallar toplu olarak uygulanır. Yayılan bölgelerden herhangi biri artış ise, korunma bayrağı hepsi için gereklidir. Herhangi biri `--yes` modunda düşüş ise, `--confirm-decrease` gereklidir.

```bash
# Standart küresel fiyat artışı: tüm bölgelerde $4.99 → $9.99,
# mevcut aboneleri eski fiyatta tut
ascelerate sub pricing set myapp com.example.monthly \
  --price 9.99 --territory USA --equalize-all-territories \
  --preserve-current
```

### Ürünler arasında fiyat kopyalama

```bash
# Her bölgenin mevcut fiyatını JSON olarak dışa aktar
ascelerate sub pricing export <bundle-id> <product-id> --output prices.json

# Başka bir aboneliğe uygula (aynı uygulamada veya farklı bir uygulamada)
ascelerate sub pricing import <other-bundle-id> <other-product-id> --file prices.json
```

Dosya, bölge koduna göre anahtarlanmış müşteri fiyatlarını içerir (korunan eski fiyatlar ve gelecekte yürürlüğe girecek fiyatlar dışa aktarıma dahil edilmez). İçe aktarma sırasında her fiyat, müşteri fiyatı üzerinden *hedef* aboneliğin kendi fiyat kademeleriyle eşleştirilir; bu sayede aynı dosya farklı ürünlerde ve uygulamalarda kullanılabilir. İçe aktarma yalnızca dosyada listelenen bölgeleri değiştirir, zaten listelenen fiyatta olan bölgeleri atlar ve `set` komutuyla aynı artış/düşüş güvenlik kurallarını uygular (`--preserve-current`/`--no-preserve-current` ve `--confirm-decrease` dahil).

Hedefin fiyat kademelerinden biri olmayan bir fiyat içe aktarmayı durdurur ve en yakın kademeleri listeler. `--snap` ile bu fiyatların her biri bunun yerine en yakın kademeyi alır (iki kademe eşit uzaklıktaysa daha ucuz olanı); düzeltilen fiyatlar onaydan önce listelenir.

Çok bölgeli yazma işlemleri sırasında App Store Connect'in geçici hataları (HTTP 429/5xx) otomatik olarak yeniden denenir: önce bekleme süresiyle yerinde, ardından çalıştırmanın sonunda ikinci bir turda. Yine de başarısız olan bölgeler son raporda listelenir ve komut sıfır olmayan bir çıkış koduyla sonlanır; aynı komutu yeniden çalıştırdığınızda güncellenmiş bölgeler değişmemiş sayılarak atlanır ve yalnızca başarısız olanlar yeniden denenir.

## Bölge erişilebilirliği

Her aboneliğin uygulamadan bağımsız kendi bölge erişilebilirliği vardır. Varsayılan olarak abonelik, uygulamasının bölgelerini devralır; `sub availability` ile değişiklik yaptığınızda aboneliğe özel bir liste oluşur.

```bash
ascelerate sub availability <bundle-id> <product-id>
ascelerate sub availability <bundle-id> <product-id> --add CHN,RUS
ascelerate sub availability <bundle-id> <product-id> --remove ITA
ascelerate sub availability <bundle-id> <product-id> --available-in-new-territories true
ascelerate sub availability <bundle-id> <product-id> --plan monthly --add DEU,FRA
```

Yıllık abonelikler **12 ay taahhütlü aylık ödeme** olarak da sunulabilir (her ay faturalandırılır; ABD ve Singapur'da sunulmaz). Bu ödeme planının kendi bölge listesi vardır: Görüntülemek ya da düzenlemek için `--plan monthly` ekleyin. `--plan` olmadan komut normal peşin ödemeli planı yönetir.

## Tanıtım teklifleri

Tanıtım teklifleri **yeni aboneleri** hedefler: ücretsiz denemeler ve tanıtım indirimleri.

```bash
ascelerate sub intro-offer list <bundle-id> <product-id>

# Ücretsiz deneme (fiyat gerekmez; --periods + --duration deneme süresini belirler)
ascelerate sub intro-offer create <bundle-id> <product-id> \
  --mode FREE_TRIAL --duration ONE_WEEK --periods 1 --territories all

# Pay-as-you-go indirimi (3 ay $0.99/ay, USA'ya özel)
ascelerate sub intro-offer create <bundle-id> <product-id> \
  --mode PAY_AS_YOU_GO --duration ONE_MONTH --periods 3 \
  --territories USA --price 0.99

# Yalnızca bitiş tarihini güncelle (diğer alanlar için sil + yeniden oluştur)
ascelerate sub intro-offer update <bundle-id> <product-id> <offer-id> --end-date 2026-12-31

ascelerate sub intro-offer delete <bundle-id> <product-id> <offer-id>
```

Modlar: `FREE_TRIAL`, `PAY_AS_YOU_GO`, `PAY_UP_FRONT`. `--territories` zorunludur: `USA,TUR` gibi ülke veya bölge kodları ya da `all`. Apple her ülke veya bölge için ayrı bir teklif tutar; ascelerate bunları tek istekte oluşturur ve teklifin mevcut bir teklifle çakışacağı ya da zaten ileri tarihli bir teklifi olan ülke veya bölgeleri atlar. Ücretli bir teklifin `--price` değeri ilk ülke veya bölgenin para birimindedir; diğerlerine Apple'ın karşılık gelen fiyatı uygulanır. `--price`, iki ücretli mod için zorunludur ve `FREE_TRIAL` için kullanılamaz.

## Promosyon teklifleri

Promosyon teklifleri **mevcut aboneleri** hedefler; genellikle uygulama içi yükseltme akışlarında kullanılır. `--code` değeri (teklif kodu), istemcilerin teklifi kullanabilmesi için sunucunuzun çalışma zamanında imzaladığı yüke gömülmelidir.

```bash
ascelerate sub promo-offer list <bundle-id> <product-id>
ascelerate sub promo-offer info <bundle-id> <product-id> <offer-id>

# Oluştur: aynı tek bölge veya --equalize-all-territories deseni
ascelerate sub promo-offer create <bundle-id> <product-id> \
  --name "Loyalty 50%" --code LOYALTY50 \
  --mode PAY_AS_YOU_GO --duration ONE_MONTH --periods 3 \
  --price 4.99 --territory USA --equalize-all-territories

# Yalnızca fiyatları güncelle (diğer alanlar için sil + yeniden oluştur)
ascelerate sub promo-offer update <bundle-id> <product-id> <offer-id> \
  --price 5.99 --equalize-all-territories

ascelerate sub promo-offer delete <bundle-id> <product-id> <offer-id>
```

## Elde tutma mesajları ve teklifleri

Bir abone App Store'daki abonelik ayarlarından aboneliğini iptal etmek istediğinde App Store ona bir **elde tutma mesajı** gösterebilir: kendi dilinde bir başlık ve metin, isteğe bağlı bir görsel ve kalması için teklifler. Mesaj uygulamaya aittir ve App Review'dan geçer. Her abonelik bir mesaj gösterir ve bu mesajda kendi **elde tutma tekliflerinden** istediklerini sunar.

```bash
ascelerate sub retention-message list <bundle-id>
ascelerate sub retention-message info <bundle-id> "Stay with us"
ascelerate sub retention-message create <bundle-id> --name "Stay with us" \
  --locale en-US --header "Before you go" --body "Your plan gets new features every month."
ascelerate sub retention-message localizations set <bundle-id> "Stay with us" \
  --locale tr --header "Gitmeden önce" --body "Planınıza her ay yeni özellikler ekleniyor."
ascelerate sub retention-message image upload <bundle-id> "Stay with us" ./retention.png
ascelerate sub retention-message submit <bundle-id> "Stay with us"
ascelerate sub retention-message new-version <bundle-id> "Stay with us"

# Elde tutma teklifleri, ardından aboneliğin gösterdiği mesaj ve teklifler
ascelerate sub retention-offer create <bundle-id> <product-id> \
  --name "Half off" --offer-id stay.half --mode PAY_AS_YOU_GO --duration ONE_MONTH --periods 3 \
  --paid-months 6 --wait-months 12 --price 4.99 --territories all
ascelerate sub retention-offer update <bundle-id> <product-id> stay.half --paid-months 3
ascelerate sub retention-message assign <bundle-id> <product-id> "Stay with us" --offers stay.half
```

- **Metin ve görsel:** Başlık en fazla 66, metin en fazla 144 karakter olabilir. Görsel saydamlık içermeyen, 16:9 oranında bir görseldir: 3840×2160 (PNG veya JPEG) ya da 5244×2950 (PNG). Her sürüm bir görsel alır.
- **Sürümler:** Bir mesajın aynı anda yalnızca bir yayımlanmamış sürümü olabilir. App Review sürümü aldıktan sonra `new-version` bir sonraki sürümü başlatır. `submit` mesajı taslak gönderime ekler; gönderimi `apps review submit` ile yapın.
- **Teklifi kimler alır:** En az `--paid-months` ay (1–24, 36, 48 veya 60) ödeme yapmış aboneler ve `--wait-months` verildiğinde son teklifini 2–24 ay önce almış olanlar. Teklif oluşturulduktan sonra yalnızca bu ikisi değiştirilebilir; bekleme süresi bir kez belirlendikten sonra kaldırılamaz.
- **Fiyatlar:** Ücretli bir teklifin `--price` değeri, `--territories` listesindeki ilk ülke veya bölgenin fiyatıdır; diğerlerine Apple'ın karşılık gelen fiyatı uygulanır. Ücretsiz deneme fiyat almaz. `--plan monthly`, yıllık bir aboneliğin aylık ödeme planını hedefler (varsayılan: peşin ödeme).

## Teklif kodları

Abonelikler için kullanılabilir kodlardır, iki türde gelir:

- **Tek kullanımlık kodlar**: Apple, asenkron olarak N adet benzersiz kod üretir. Her biri yalnızca bir kez kullanılabilir.
- **Özel kodlar**: geliştirici tarafından sağlanan dize, N kez kullanılabilir.

```bash
ascelerate sub offer-code list <bundle-id> <product-id>
ascelerate sub offer-code info <bundle-id> <product-id> <offer-code-id>

# Teklif kodu oluştur (tüm teklif benzeri özelliklerle)
ascelerate sub offer-code create <bundle-id> <product-id> \
  --name "Launch Free Month" \
  --eligibility NEW \
  --offer-eligibility STACK_WITH_INTRO_OFFERS \
  --mode FREE_TRIAL --duration ONE_MONTH --periods 1 \
  --price 0 --territory USA --equalize-all-territories

ascelerate sub offer-code toggle <bundle-id> <product-id> <offer-code-id> --active true

# Tek kullanımlık kod yığını oluştur (asenkron)
ascelerate sub offer-code gen-codes <bundle-id> <product-id> <offer-code-id> \
  --count 500 --expires 2026-12-31

# Üretim tamamlandıktan sonra gerçek kod değerlerini al
ascelerate sub offer-code view-codes <one-time-use-batch-id> --output codes.txt

# Geliştirici tanımlı özel kod ekle
ascelerate sub offer-code add-custom-codes <bundle-id> <product-id> <offer-code-id> \
  --code SUBPROMO --count 1000 --expires 2026-12-31
```

Abonelik teklif kodları için müşteri uygunluk değerleri: `NEW`, `EXISTING`, `EXPIRED`. Teklif uygunluğu: `STACK_WITH_INTRO_OFFERS` veya `REPLACE_INTRO_OFFERS`.

## Abonelik grubunu incelemeye gönderme

Abonelik grupları, sonraki uygulama sürümüyle birlikte incelenir. `sub submit-group`, `sub submit` komutunun grup düzeyindeki karşılığıdır.

```bash
ascelerate sub submit-group <bundle-id>
```

Grubun kendine ait bekleyen bir sürümü olmalıdır (örneğin düzenlenmiş grup yerelleştirmeleri); aksi halde komut, herhangi bir istek göndermeden durur.

## Tanıtım görselleri

App Store'da aboneliğin yanında gösterilen tanıtım görsellerini yükleyin.

```bash
ascelerate sub images list <bundle-id> <product-id>
ascelerate sub images upload <bundle-id> <product-id> ./hero.png
ascelerate sub images delete <bundle-id> <product-id> <image-id>
```

## App Review ekran görüntüsü

Her abonelik en fazla bir App Review ekran görüntüsüne sahip olabilir. Yükleme mevcut olanı değiştirir.

```bash
ascelerate sub review-screenshot view <bundle-id> <product-id>
ascelerate sub review-screenshot upload <bundle-id> <product-id> ./review.png
ascelerate sub review-screenshot delete <bundle-id> <product-id>
```

Görsel ve ekran görüntüsü yüklemeleri Apple'ın 3 adımlı akışını kullanır (rezerve et → parçaları PUT et → MD5 ile tamamla). Tek bir `upload` çağrısı üç adımı da yönetir.

## Win-back teklifleri

Win-back teklifleri, aboneliği sona ermiş kişiler içindir: App Store onlara geri dönmeleri için bir başlangıç tarihinden isteğe bağlı bir bitiş tarihine kadar indirim veya ücretsiz süre sunar. Yalnızca onaylanmış bir abonelik bu teklifleri alabilir.

```bash
ascelerate sub win-back-offer list <bundle-id> <product-id>
ascelerate sub win-back-offer info <bundle-id> <product-id> comeback.half
ascelerate sub win-back-offer create <bundle-id> <product-id> \
  --name "Come back" --offer-id comeback.half --mode PAY_AS_YOU_GO --duration ONE_MONTH --periods 3 \
  --since-months 3-12 --paid-months 6 --end-date 2027-01-31 --priority high --promote \
  --price 4.99 --territories all
ascelerate sub win-back-offer update <bundle-id> <product-id> comeback.half --since-months 2-24 --end-date 2027-03-31
ascelerate sub win-back-offer delete <bundle-id> <product-id> comeback.half
```

- **Teklifi kimler alır:** Aboneliği `--since-months` ay önce (1–23 ile 2–24 ay arasında bir aralık) sona ermiş, en az `--paid-months` ay (1–24, 36, 48 veya 60) ödeme yapmış ve `--wait-months` verildiğinde son teklifini 2–24 ay önce almış kişiler.
- **Tarihler:** Teklif `--start-date` tarihinde başlar (en erken ve varsayılan olarak yarın); `--end-date` verildiğinde en az 3 gün sonra sona erer.
- **App Store'da:** `--priority high` teklifi diğer tekliflerin önüne koyar; `--promote`, App Store'un teklifi Apple'ın oluşturduğu görsellerle tanıtmasını sağlar.
- **Fiyatlar:** Elde tutma tekliflerinde olduğu gibi `--price`, `--territories` listesindeki ilk ülke veya bölgenin fiyatıdır; diğerlerine Apple'ın karşılık gelen fiyatı uygulanır. Ücretsiz deneme fiyat almaz. Kullandıkça öde (`PAY_AS_YOU_GO`) teklifinin süresi, aboneliğin kendi dönemidir (yıllık bir abonelikte `ONE_YEAR`).
- **Değişiklikler:** Uygunluk koşulları, tarihler, öncelik ve tanıtım değiştirilebilir; diğer her şey için teklifi silip yeniden oluşturun.
