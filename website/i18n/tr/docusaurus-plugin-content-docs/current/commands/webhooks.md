---
sidebar_position: 20
title: Webhook'lar
---

# Webhook'lar

App Store Connect'in bir uygulamaya ait olayları gerçekleştikleri anda sunucunuza göndermesini sağlayın: inceleme durumu değişiklikleri, build yüklemeleri, TestFlight harici build durumları ve test kullanıcısı geri bildirimleri. Webhook'lara **ad** veya kimlikleriyle başvurulur.

## Listeleme

```bash
ascelerate webhooks <bundle-id>
```

## Oluşturma

```bash
ascelerate webhooks create <bundle-id> --name "Release bot" --url https://example.com/hook \
  --events app-store-version-app-version-state-updated,build-upload-state-updated
```

`--events`, virgülle ayrılmış bir liste veya `all` kabul eder. Olay türlerinden bazıları:

| Olay | Gönderildiği durum |
|---|---|
| `app-store-version-app-version-state-updated` | Bir sürümün App Review veya yayın durumu değiştiğinde |
| `build-upload-state-updated` | Bir build yüklemesinin durumu değiştiğinde |
| `build-beta-detail-external-build-state-updated` | Bir build'in harici TestFlight durumu değiştiğinde |
| `beta-feedback-crash-submission-created` | Bir test kullanıcısı çökme geri bildirimi gönderdiğinde |
| `beta-feedback-screenshot-submission-created` | Bir test kullanıcısı ekran görüntüsü geri bildirimi gönderdiğinde |

`ascelerate webhooks create --help`, arka plan varlıkları (Background Assets) ve alternatif dağıtım olayları dahil tüm türleri listeler.

Apple her isteği webhook'un gizli anahtarıyla imzalar. `--secret` verilmezse `create` rastgele bir gizli anahtar oluşturur ve yalnızca bir kez yazdırır. Bu anahtarı sunucunuzda saklayın; App Store Connect onu bir daha göstermez. `--disabled`, webhook'u etkinleştirmeden oluşturur.

## Test etme ve hata ayıklama

```bash
ascelerate webhooks ping <bundle-id> "Release bot"
ascelerate webhooks deliveries <bundle-id> "Release bot"
ascelerate webhooks deliveries <bundle-id> "Release bot" --state failed
ascelerate webhooks redeliver <delivery-id>
```

`ping` bir test olayı gönderir. `deliveries`, son teslimatları olay türü, sunucunuzun döndürdüğü HTTP durum kodu ve varsa hatayla birlikte listeler (`--state succeeded|failed|pending`, `--limit`, `--json`). Sunucunuzu düzelttikten sonra `redeliver`, bir teslimatın olayını yeniden gönderir.

## Güncelleme ve silme

```bash
ascelerate webhooks update <bundle-id> "Release bot" --enabled false
ascelerate webhooks update <bundle-id> "Release bot" --events all --url https://example.com/new-hook
ascelerate webhooks delete <bundle-id> "Release bot"
```

`--events` listenin tamamını değiştirir; `--secret` yeni bir imzalama anahtarı ayarlar.
