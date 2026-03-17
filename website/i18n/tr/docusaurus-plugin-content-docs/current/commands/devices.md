---
sidebar_position: 8
title: Cihazlar
---

# Cihazlar

Tüm cihaz komutları interaktif modu destekler -- argümanlar isteğe bağlıdır. Belirtilmediğinde komut numaralı listelerle seçim yapmayı ister.

## Listeleme

```bash
ascelerate devices list
ascelerate devices list --platform IOS --status ENABLED
```

## Detayları görüntüleme

```bash
# İnteraktif seçici
ascelerate devices info

# Ad veya UDID ile
ascelerate devices info "My iPhone"
```

## Kayıt etme

```bash
# İnteraktif sorular
ascelerate devices register

# İnteraktif olmayan
ascelerate devices register --name "My iPhone" --udid 00008101-XXXXXXXXXXXX --platform IOS
```

## Güncelleme

```bash
# İnteraktif seçici ve güncelleme soruları
ascelerate devices update

# Bir cihazı yeniden adlandırın
ascelerate devices update "My iPhone" --name "Work iPhone"

# Bir cihazı devre dışı bırakın
ascelerate devices update "My iPhone" --status DISABLED
```
