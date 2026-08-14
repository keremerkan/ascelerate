---
sidebar_position: 13
title: Müşteri Değerlendirmeleri
---

# Müşteri Değerlendirmeleri

Müşteri değerlendirmelerini görüntüleyin ve geliştirici yanıtlarını yönetin. Değerlendirmelerin kendisi salt okunurdur; yalnızca **geliştirici yanıtını** yayımlayabilir, değiştirebilir veya silebilirsiniz.

## Listeleme

```bash
ascelerate reviews list <bundle-id>
ascelerate reviews list <bundle-id> --rating 1 --sort critical --unanswered --limit 20
ascelerate reviews list <bundle-id> --territory USA
```

Tablo; değerlendirme kimliğini, yıldız puanını, tarihi, bölgeyi, yanıt olup olmadığını ve başlığı gösterir.

- `--rating`: Yıldız puanına göre filtreler (1–5).
- `--territory`: Değerlendirme bölge koduna göre filtreler (örn. `USA`).
- `--sort`: `recent` (varsayılan), `oldest`, `critical` (önce en düşük puan) veya `best` (önce en yüksek).
- `--unanswered`: Yalnızca yayımlanmış yanıtı olmayan değerlendirmeleri gösterir.
- `--limit`: Gösterilecek en fazla değerlendirme sayısı (varsayılan 50, en fazla 200).
- `--json`: **Tam değerlendirme metinlerini ve geliştirici yanıtlarını** da içeren, makine tarafından okunabilir çıktı üretir; böylece değerlendirme başına ayrı `info` çağrısı gerekmez ([kurallar](../guides/automation.md#json-output)).

## Detaylar

```bash
ascelerate reviews info <review-id>
```

Değerlendirmenin tam metnini ve varsa geliştirici yanıtını gösterir. Değerlendirme kimlikleri `reviews list` komutundan alınır. Bu komut da `--json` kabul eder ve tek bir `reviews list --json` öğesiyle aynı yapıda çıktı verir.

## Yanıtlama

```bash
ascelerate reviews respond <review-id> --body "Geri bildiriminiz için teşekkürler! Bunu en son güncellemede düzelttik."
```

Bir geliştirici yanıtı yayımlar. Değerlendirmede zaten bir yanıt varsa, onayınızın ardından mevcut yanıt değiştirilir.

## Yanıtı silme

```bash
ascelerate reviews delete-response <review-id>
```
