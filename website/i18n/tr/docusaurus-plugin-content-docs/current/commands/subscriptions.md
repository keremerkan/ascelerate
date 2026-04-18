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

Abonelik fiyatlandırması bölgeye özeldir. IAP'lerde olduğu gibi otomatik eşitleme kavramı yoktur — fiyatlamak istediğiniz her bölgenin kendi kaydı olmalıdır. CLI ya tek bir bölgeyi ayarlar ya da Apple'ın yerel para birimi kademe karşılıklarını kullanarak fiyatı tüm bölgelere yayar.

```bash
# Mevcut bölgeye özel fiyatları göster (yoksa uyarır)
ascelerate sub pricing show <bundle-id> <product-id>

# Bir bölgedeki mevcut fiyat kademelerini listele
ascelerate sub pricing tiers <bundle-id> <product-id> --territory USA

# Tek bir bölge için fiyat ayarla
ascelerate sub pricing set <bundle-id> <product-id> --price 4.99 --territory USA

# Tüm bölgelere fiyatı yay (her bölge için bir POST)
ascelerate sub pricing set <bundle-id> <product-id> --price 4.99 --equalize-all-territories
```

### Fiyat değişiklikleri ve mevcut aboneler

Apple, fiyat değişikliklerini değişikliğin yönüne göre mevcut aboneler için farklı şekilde uygular. `sub pricing set` komutu her etkilenen bölgenin mevcut fiyatını alır, değişikliği sınıflandırır ve doğru davranışı uygular:

- **Düşürme**: mevcut aboneler otomatik olarak düşük fiyata geçer. Etkileşimli çalıştırmalarda uyarı ile birlikte sorulur. `--yes` modunda, gelir etkisini onaylamak için `--confirm-decrease` eklemeniz gerekir — sadece `--yes` yeterli değildir.
- **Artış**: mevcut abonelerle nasıl başa çıkılacağını açıkça seçmeniz gerekir. Aşağıdakilerden biri ayarlanmadığı sürece komut hata verir:
  - `--preserve-current` — mevcut aboneleri eski fiyatlarında tutar
  - `--no-preserve-current` — Apple'ın bildirim süresinden sonra yeni fiyatı mevcut abonelere uygular
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

## Bölge erişilebilirliği

Her aboneliğin uygulamadan bağımsız kendi bölge erişilebilirliği vardır. Varsayılan olarak abonelik, uygulamasının bölgelerini devralır; `sub availability` ile değişiklik yaptığınızda aboneliğe özel bir liste oluşur.

```bash
ascelerate sub availability <bundle-id> <product-id>
ascelerate sub availability <bundle-id> <product-id> --add CHN,RUS
ascelerate sub availability <bundle-id> <product-id> --remove ITA
ascelerate sub availability <bundle-id> <product-id> --available-in-new-territories true
```

## Tanıtım teklifleri

Tanıtım teklifleri **yeni aboneleri** hedefler — ücretsiz denemeler ve tanıtım indirimleri.

```bash
ascelerate sub intro-offer list <bundle-id> <product-id>

# Ücretsiz deneme (fiyat gerekmez; --periods + --duration deneme süresini belirler)
ascelerate sub intro-offer create <bundle-id> <product-id> \
  --mode FREE_TRIAL --duration ONE_WEEK --periods 1

# Pay-as-you-go indirimi (3 ay $0.99/ay, USA'ya özel)
ascelerate sub intro-offer create <bundle-id> <product-id> \
  --mode PAY_AS_YOU_GO --duration ONE_MONTH --periods 3 \
  --territory USA --price 0.99

# Yalnızca bitiş tarihini güncelle (diğer alanlar için sil + yeniden oluştur)
ascelerate sub intro-offer update <bundle-id> <product-id> <offer-id> --end-date 2026-12-31

ascelerate sub intro-offer delete <bundle-id> <product-id> <offer-id>
```

Modlar: `FREE_TRIAL`, `PAY_AS_YOU_GO`, `PAY_UP_FRONT`. `--territory` belirtilmediğinde teklif global olarak uygulanır; belirtildiğinde yalnızca o bölgeye özeldir. `--price`, iki ücretli mod için zorunludur ve `FREE_TRIAL` için yasaktır.

## Promosyon teklifleri

Promosyon teklifleri **mevcut aboneleri** hedefler — genellikle uygulama içi yükseltme akışlarında kullanılır. `--code` değeri (teklif kodu), istemcilerin teklifi kullanabilmesi için sunucunuzun çalışma zamanında imzaladığı yüke gömülmelidir.

```bash
ascelerate sub promo-offer list <bundle-id> <product-id>
ascelerate sub promo-offer info <bundle-id> <product-id> <offer-id>

# Oluştur — aynı tek bölge veya --equalize-all-territories deseni
ascelerate sub promo-offer create <bundle-id> <product-id> \
  --name "Loyalty 50%" --code LOYALTY50 \
  --mode PAY_AS_YOU_GO --duration ONE_MONTH --periods 3 \
  --price 4.99 --territory USA --equalize-all-territories

# Yalnızca fiyatları güncelle (diğer alanlar için sil + yeniden oluştur)
ascelerate sub promo-offer update <bundle-id> <product-id> <offer-id> \
  --price 5.99 --equalize-all-territories

ascelerate sub promo-offer delete <bundle-id> <product-id> <offer-id>
```

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

## Win-back teklifleri (henüz uygulanmadı)

Win-back teklifleri (kayıp aboneler için teklifler) henüz kasıtlı olarak uygulanmamıştır. `asc-swift` bağımlılığımızdaki `WinBackOfferPriceInlineCreate` türü, API'nin gerektirdiği `territory` ve `subscriptionPricePoint` ilişkilerini içermediğinden geçerli bir oluşturma isteği oluşturamıyoruz. Bağımlılık güncellendiğinde tekrar ele alınacak.
