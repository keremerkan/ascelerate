---
sidebar_position: 1
title: Workflow'lar
---

# Workflow'lar

Birden fazla komutu tek bir otomatik çalıştırmada bir workflow dosyasıyla zincirleyin:

```bash
ascelerate run-workflow release.txt
ascelerate run-workflow release.txt --yes   # tüm soruları atla (CI/CD)
ascelerate run-workflow                     # .workflow/.txt dosyalarından interaktif olarak seç
```

Bir workflow dosyası, her satırda bir komut bulunan düz metin dosyasıdır (`ascelerate` öneki olmadan). `#` ile başlayan satırlar yorumdur, boş satırlar yok sayılır. Hem `.workflow` hem de `.txt` uzantıları desteklenir.

## Örnek

Örnek bir uygulamanın 2.1.0 sürümünü göndermek için `release.txt`:

```
# Release workflow for MyApp v2.1.0

# Create the new version on App Store Connect
apps create-version com.example.MyApp 2.1.0

# Build, validate, and upload
builds archive --scheme MyApp
builds validate --latest --bundle-id com.example.MyApp
builds upload --latest --bundle-id com.example.MyApp

# Wait for the build to finish processing
builds await-processing com.example.MyApp

# Update localizations and attach the build
apps localizations import com.example.MyApp --file localizations.json
apps build attach-latest com.example.MyApp

# Submit for review
apps review submit com.example.MyApp
```

## Onay davranışı

`--yes` olmadan workflow başlamadan önce onay ister ve tekil komutlar normalde soracakları yerlerde sormaya devam eder (ör. incelemeye göndermeden önce). `--yes` ile tüm sorular atlanır ve tamamen gözetimsiz çalışma sağlanır.

## İç içe geçirme

Workflow'lar başka workflow'ları çağırabilir (bir workflow dosyası içinde `run-workflow`). Döngüsel referanslar algılanır ve engellenir.

## Build pipeline entegrasyonu

`builds upload`, sonraki `await-processing` ve `build attach-latest` komutlarının yeni yüklenen build'i otomatik olarak hedeflemesi için dahili bir değişken ayarlar; bu, API'daki yayılma gecikmesinden kaynaklanan yarış koşullarını önler.
