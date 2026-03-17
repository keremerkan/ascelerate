---
sidebar_position: 11
title: Provisioning Profilleri
---

# Provisioning Profilleri

Tüm profil komutları interaktif modu destekler -- argümanlar isteğe bağlıdır.

## Listeleme

```bash
ascelerate profiles list
ascelerate profiles list --type IOS_APP_STORE --state ACTIVE
```

## Detayları görüntüleme

```bash
ascelerate profiles info
ascelerate profiles info "My App Store Profile"
```

## İndirme

```bash
ascelerate profiles download
ascelerate profiles download "My App Store Profile" --output ./profiles/
```

## Oluşturma

```bash
# Tamamen interaktif
ascelerate profiles create

# İnteraktif olmayan
ascelerate profiles create --name "My Profile" --type IOS_APP_STORE --bundle-id com.example.MyApp --certificates all
```

`--certificates all` eşleşen ailenin (distribution, development veya Developer ID) tüm sertifikalarını kullanır. Seri numaralarını da belirtebilirsiniz: `--certificates ABC123,DEF456`.

## Silme

```bash
ascelerate profiles delete
ascelerate profiles delete "My App Store Profile"
```

## Yeniden oluşturma

Profilleri silip eşleşen ailenin en son sertifikalarıyla yeniden oluşturarak yenileyin:

```bash
# İnteraktif: tüm profillerden seçin (durumu gösterir)
ascelerate profiles reissue

# Belirli bir profili ada göre yeniden oluşturun
ascelerate profiles reissue "My Profile"

# Tüm geçersiz profilleri yeniden oluşturun
ascelerate profiles reissue --all-invalid

# Durumdan bağımsız olarak tüm profilleri yeniden oluşturun
ascelerate profiles reissue --all

# Tüm profilleri yeniden oluşturun, dev/adhoc için tüm etkin cihazları kullanın
ascelerate profiles reissue --all --all-devices

# Otomatik algılama yerine belirli sertifikaları kullanın
ascelerate profiles reissue --all --to-certs ABC123,DEF456
```
