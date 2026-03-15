---
sidebar_position: 2
title: Otomasyon ve CI/CD
---

# Otomasyon ve CI/CD

Onay isteyen komutların çoğu `--yes` / `-y` flag'ini destekler; bu sayede CI/CD pipeline'larında ve betiklerde rahatlıkla kullanılabilirler.

```bash
asc apps build attach-latest <bundle-id> --yes
asc apps review submit <bundle-id> --yes
```

:::warning
Provisioning komutlarıyla `--yes` kullanırken, tüm gerekli argümanlar açıkça belirtilmelidir -- interaktif mod devre dışı bırakılır.
:::

## CI'da Xcode imzalama

Hem `builds archive` hem de arşivden IPA'ya dışa aktarma, `xcodebuild`'e `-allowProvisioningUpdates` geçirir. Bu olmadan `xcodebuild` yalnızca yerel olarak önbelleğe alınmış provisioning profillerini kullanır ve Developer Portal'dan güncellenmiş olanları almaz.

Xcode GUI girişi olmayan CI ortamları için kimlik doğrulama flag'lerini geçirin:

```bash
asc builds archive \
  --authentication-key-path /path/to/AuthKey.p8 \
  --authentication-key-id YOUR_KEY_ID \
  --authentication-key-issuer-id YOUR_ISSUER_ID
```

## Çıkış kodları

Komutlar başarısızlıkta sıfır olmayan çıkış kodu döndürür, bu sayede `set -e` veya `&&` zincirleme ile betiklerde güvenle kullanılabilirler. `preflight` komutu özellikle herhangi bir kontrol başarısız olduğunda sıfır olmayan çıkış kodu döndürür, böylece incelemeye göndermeyi buna bağlayabilirsiniz:

```bash
asc apps review preflight <bundle-id> && asc apps review submit <bundle-id>
```
