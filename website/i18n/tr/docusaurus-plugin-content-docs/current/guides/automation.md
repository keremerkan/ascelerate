---
sidebar_position: 2
title: Otomasyon ve CI/CD
---

# Otomasyon ve CI/CD

Onay isteyen komutların çoğu `--yes` / `-y` flag'ini destekler; bu sayede CI/CD pipeline'larında ve betiklerde rahatlıkla kullanılabilirler.

```bash
ascelerate apps build attach-latest <bundle-id> --yes
ascelerate apps review submit <bundle-id> --yes
```

:::warning
Provisioning komutlarıyla `--yes` kullanırken, tüm gerekli argümanlar açıkça belirtilmelidir -- interaktif mod devre dışı bırakılır.
:::

## CI'da Xcode imzalama

Hem `builds archive` hem de arşivden IPA'ya dışa aktarma, `xcodebuild`'e `-allowProvisioningUpdates` geçirir. Bu olmadan `xcodebuild` yalnızca yerel olarak önbelleğe alınmış provisioning profillerini kullanır ve Developer Portal'dan güncellenmiş olanları almaz.

Xcode GUI girişi olmayan CI ortamları için kimlik doğrulama flag'lerini geçirin:

```bash
ascelerate builds archive \
  --authentication-key-path /path/to/AuthKey.p8 \
  --authentication-key-id YOUR_KEY_ID \
  --authentication-key-issuer-id YOUR_ISSUER_ID
```

## JSON çıktısı {#json-output}

Okuma komutları, makine tarafından okunabilir çıktı için `--json` seçeneğini destekler; çıktı `jq` ile işlemeye, betiklerde ve yapay zeka ajanlarında kullanmaya hazırdır:

```bash
ascelerate apps list --json
ascelerate apps info <bundle-id> --json
ascelerate apps versions <bundle-id> --json
ascelerate apps review preflight <bundle-id> --json
ascelerate apps review status <bundle-id> --json
ascelerate builds list --bundle-id <bundle-id> --json
ascelerate testflight builds <bundle-id> --json
ascelerate testflight status <bundle-id> --json
ascelerate reviews list <bundle-id> --json
ascelerate reviews info <review-id> --json
ascelerate iap list <bundle-id> --json
ascelerate iap info <bundle-id> <product-id> --json
ascelerate iap pricing show <bundle-id> <product-id> --json
ascelerate sub groups <bundle-id> --json
ascelerate sub list <bundle-id> --json
ascelerate sub info <bundle-id> <product-id> --json
ascelerate sub pricing show <bundle-id> <product-id> --json
ascelerate rate-limit --json
```

Çıktı kuralları:

- Liste komutları en üst düzeyde bir JSON **dizisi**, detay komutları tek bir **nesne** üretir.
- Enum değerleri ham API sabitleridir (`WAITING_FOR_REVIEW`, `IOS`), tarihler ISO 8601 biçimindedir ve her kaynak kendi `id` değerini taşır.
- Null alanlar atlanır; boş sonuçlarda açıklama metni değil, her zaman `[]` üretilir.
- Uyarılar boolean değerlere dönüşür: `iap info` ve `sub info`, uyarı mesajı yerine `"hasPricing": false` raporlar.
- `--json` etkileşimsiz modu da etkinleştirir: Normalde soru soracak komutlar (örneğin platform seçimi gerektiğinde) bunun yerine hata verir; belirsizliği gidermek için `--platform` veya ilgili diğer seçenekleri verin.
- Hatalar stderr'e yazılır, bu sayede stdout her zaman geçerli JSON'dur.

Örnek olarak, yanıtlanmamış değerlendirmeleri şöyle sayabilirsiniz:

```bash
ascelerate reviews list <bundle-id> --json | jq '[.[] | select(.response == null)] | length'
```

## Çıkış kodları

Komutlar başarısızlıkta sıfır olmayan çıkış kodu döndürür, bu sayede `set -e` veya `&&` zincirleme ile betiklerde güvenle kullanılabilirler. `preflight` komutu özellikle herhangi bir kontrol başarısız olduğunda sıfır olmayan çıkış kodu döndürür, böylece incelemeye göndermeyi buna bağlayabilirsiniz:

```bash
ascelerate apps review preflight <bundle-id> && ascelerate apps review submit <bundle-id>
```

`--json` ile `preflight`, çıkış kodu davranışını aynen korurken tablo yerine yapılandırılmış bir rapor üretir (`{"passed": false, "checks": [{"group", "name", "passed", "detail"}]}`); bu sayede tam olarak *hangi* kontrolün başarısız olduğunu raporlaması gereken CI kapıları için idealdir.
