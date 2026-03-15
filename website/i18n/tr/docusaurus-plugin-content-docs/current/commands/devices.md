---
sidebar_position: 8
title: Cihazlar
---

# Cihazlar

Tüm cihaz komutları interaktif modu destekler -- argümanlar isteğe bağlıdır. Belirtilmediğinde komut numaralı listelerle seçim yapmayı ister.

## Listeleme

```bash
asc devices list
asc devices list --platform IOS --status ENABLED
```

## Detayları görüntüleme

```bash
# İnteraktif seçici
asc devices info

# Ad veya UDID ile
asc devices info "My iPhone"
```

## Kayıt etme

```bash
# İnteraktif sorular
asc devices register

# İnteraktif olmayan
asc devices register --name "My iPhone" --udid 00008101-XXXXXXXXXXXX --platform IOS
```

## Güncelleme

```bash
# İnteraktif seçici ve güncelleme soruları
asc devices update

# Bir cihazı yeniden adlandırın
asc devices update "My iPhone" --name "Work iPhone"

# Bir cihazı devre dışı bırakın
asc devices update "My iPhone" --status DISABLED
```
