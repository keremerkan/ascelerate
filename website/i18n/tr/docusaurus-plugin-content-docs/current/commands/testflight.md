---
sidebar_position: 17
title: TestFlight
---

# TestFlight

TestFlight beta testlerini uçtan uca yönetin: beta grupları, test kullanıcıları, build dağıtımı, What to Test notları, beta incelemesi ve test kullanıcısı geri bildirimleri.

Build kapsamındaki komutlar varsayılan olarak süresi dolmamış en son build'i hedefler. Belirli bir build'i hedeflemek için `--build <number>` geçin; evrensel satın alma kullanan bir uygulama aynı build numarasını birden fazla platformda paylaşıyorsa `--platform` ile netleştirin.

## Beta grupları

```bash
ascelerate testflight groups list <bundle-id>
ascelerate testflight groups info <bundle-id> "External Testers"
ascelerate testflight groups create <bundle-id> --name "Friends" --public-link --public-link-limit 100
ascelerate testflight groups update <bundle-id> "Friends" --public-link false
ascelerate testflight groups delete <bundle-id> "Friends"
```

`groups list` her grubun türünü, herkese açık bağlantısını, test kullanıcısı sınırını ve geri bildirim ayarını gösterir. `groups info` bunlara grubun test kullanıcılarını ve atanmış build'lerini ekler. `create` komutu, ekip üyelerinden oluşan dahili bir grup için `--internal` ve gruba tüm build'lere otomatik erişim vermek için `--all-builds` seçeneklerini kabul eder; harici gruplarda isteğe bağlı test kullanıcısı sınırıyla birlikte herkese açık bir davet bağlantısı etkinleştirilebilir.

Grup adları büyük/küçük harf ayrımı yapılmadan eşleştirilir. Adı boş bırakırsanız etkileşimli bir listeden seçim yapabilirsiniz.

### Build atama

```bash
# Varsayılan olarak süresi dolmamış en son build kullanılır
ascelerate testflight groups add-build <bundle-id> "Friends"
ascelerate testflight groups add-build <bundle-id> "Friends" --build 123
ascelerate testflight groups remove-build <bundle-id> "Friends" --build 123
```

### Katılım ölçütleri

Herkese açık bağlantı kullanan gruplar, katılımı cihaz ailesine ve işletim sistemi sürümüne göre sınırlayabilir:

```bash
# Geçerli ölçütleri ve Apple'ın kabul ettiği cihaz/işletim sistemi seçeneklerini görüntüleyin
ascelerate testflight groups criteria view <bundle-id> "Friends" --options

# Ölçütleri değiştirin: FAMILY[:MIN[:MAX]], sınır değerleri dahildir
ascelerate testflight groups criteria set <bundle-id> "Friends" --filter IPHONE:18.0 --filter IPAD:17.0:26

# Tüm ölçütleri kaldırın
ascelerate testflight groups criteria clear <bundle-id> "Friends"
```

Geçerli cihaz aileleri: `IPHONE`, `IPAD`, `MAC`, `APPLE_TV`, `APPLE_WATCH`, `VISION`.

## Test kullanıcıları

```bash
ascelerate testflight testers list <bundle-id>
ascelerate testflight testers list <bundle-id> --group "Friends"

# Harici gruplara ekleme, TestFlight davetini gönderir
ascelerate testflight testers add <bundle-id> --email tester@example.com --first-name Jane --group "Friends"

# Tek bir gruptan veya uygulamanın tamamından çıkarın
ascelerate testflight testers remove <bundle-id> tester@example.com --group "Friends"
ascelerate testflight testers remove <bundle-id> tester@example.com

# Davet e-postasını yeniden gönderin
ascelerate testflight testers invite <bundle-id> tester@example.com
```

`add` ve `import` komutlarında `--group` seçeneği, virgülle ayrılmış birden fazla grup adı kabul eder.

### Toplu içe aktarma

```bash
ascelerate testflight testers import <bundle-id> --file testers.csv --group "Friends"
```

Dosyada her satırda bir test kullanıcısı bulunur: `email[,ad[,soyad]]`. Boş satırlar, `#` ile başlayan satırlar ve baştaki başlık satırı atlanır; App Store Connect web arayüzünün dışa aktardığı CSV biçimi olduğu gibi kullanılabilir. Başarısız satırlar toplu işlemin geri kalanını durdurmadan en sonda raporlanır.

## Build'ler ve dağıtım

```bash
# Tüm build'ler ve TestFlight durumları
ascelerate testflight builds <bundle-id>
ascelerate testflight builds <bundle-id> --platform ios --limit 50

# Yayın öncesi sürümler
ascelerate testflight versions <bundle-id>

# Tek bir build'in tüm durumu
ascelerate testflight status <bundle-id> --build 123
```

`builds` her build'in işlenme durumunu, dahili ve harici test durumlarını ve son kullanma tarihini listeler. `status` tek bir build için bunlara otomatik bildirim ayarını ve beta inceleme durumunu ekler.

```bash
# Bir build'in süresini doldurun; test kullanıcıları artık yükleyemez
ascelerate testflight expire <bundle-id> --build 123

# Test kullanıcılarına bir build'in hazır olduğunu bildirin
ascelerate testflight notify <bundle-id>

# Bir build için otomatik bildirimi açın veya kapatın
ascelerate testflight auto-notify <bundle-id> --enabled false
```

## What to Test

Test notları build ve dil başına saklanır:

```bash
ascelerate testflight whats-new view <bundle-id>

# Tek bir dil için; --locale verilmezse mevcut tüm diller güncellenir
ascelerate testflight whats-new set <bundle-id> --text "Yeni harita filtrelerini deneyin" --locale tr-TR
ascelerate testflight whats-new set <bundle-id> --text "Yeni harita filtrelerini deneyin"

# JSON ile dışa ve içe aktarma
ascelerate testflight whats-new export <bundle-id> --output notes.json
ascelerate testflight whats-new import <bundle-id> --file notes.json
```

JSON biçimi diğer yerelleştirme komutlarıyla aynıdır:

```json
{
  "en-US": { "whatsNew": "Try the new map filters" },
  "tr-TR": { "whatsNew": "Yeni harita filtrelerini deneyin" }
}
```

## Beta incelemesi

Harici test için her build'in bir beta incelemesinden geçmesi gerekir:

```bash
ascelerate testflight submit <bundle-id> --build 123
ascelerate testflight status <bundle-id> --build 123
```

Beta uygulama bilgileri ve inceleme ayrıntıları uygulama düzeyindedir:

```bash
# Dil başına beta uygulama açıklaması ve geri bildirim e-postası
ascelerate testflight app-info view <bundle-id>
ascelerate testflight app-info update <bundle-id> --locale tr-TR --feedback-email ben@example.com
ascelerate testflight app-info export <bundle-id> --output beta-app-info.json
ascelerate testflight app-info import <bundle-id> --file beta-app-info.json

# Beta inceleme ekibi için iletişim ve demo hesabı bilgileri
ascelerate testflight review-info <bundle-id>
ascelerate testflight review-info <bundle-id> --demo-account-name demo@example.com --demo-account-required true

# Özel beta lisans sözleşmesi (--text "" Apple'ın standart sözleşmesine geri döner)
ascelerate testflight eula <bundle-id>
ascelerate testflight eula <bundle-id> --file eula.txt
```

## Test kullanıcısı geri bildirimleri

Test kullanıcılarının TestFlight üzerinden gönderdiği çökme ve ekran görüntüsü geri bildirimleri:

```bash
ascelerate testflight feedback crashes list <bundle-id>
ascelerate testflight feedback crashes info <submission-id>
ascelerate testflight feedback crashes log <submission-id> --output crash.log
ascelerate testflight feedback crashes delete <submission-id>

ascelerate testflight feedback screenshots list <bundle-id>
ascelerate testflight feedback screenshots info <submission-id>
ascelerate testflight feedback screenshots download <bundle-id> [submission-id] --output feedback.zip
ascelerate testflight feedback screenshots delete <submission-id>
```

`list` komutu `--build` ve `--platform` filtrelerini kabul eder. `info` cihazla ilgili tüm bağlamı gösterir: model, işletim sistemi sürümü, dil, bağlantı türü, pil düzeyi, boş disk alanı ve test kullanıcısının yorumu. `log` çökme günlüğünü yazdırır veya `--output` ile dosyaya kaydeder. `download` bir gönderimin ekran görüntülerini ve yorumunu tek bir zip arşivinde toplar; gönderim kimliğini vermezseniz uygulamanın gönderimleri sayfalı bir listede sunulur ve içinden seçim yapabilirsiniz. Ekran görüntüsü bağlantılarının süresi birkaç gün içinde dolar; bu nedenle saklamak istediğiniz geri bildirimleri indirin.
