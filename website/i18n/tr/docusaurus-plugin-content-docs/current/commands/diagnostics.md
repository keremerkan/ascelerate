---
sidebar_position: 16
title: Tanılama
---

# Tanılama

Xcode'un Organizer penceresinde görünenler; analiz verilerini geliştiricilerle paylaşan kullanıcıların cihazlarından gelir: bir derlemenin en sık takılmaları, yavaş açılışları ve disk yazmaları çağrı yığınlarıyla birlikte, ayrıca uygulamanın sürümler boyunca performans ve güç metrikleri. `--build` verilmezse App Store'daki sürümün derlemesi kullanılır.

## İmzalar

```bash
ascelerate diagnostics <bundle-id>
ascelerate diagnostics <bundle-id> --type hangs --build 2041
```

Derlemenin takılma, açılış ve disk yazma imzaları; her türde ağırlığa göre sıralı, önceki sürümlere göre eğilimleriyle. `--type` olarak `hangs`, `launches` veya `disk-writes` verilir (birden fazlası virgülle ayrılır).

## Günlükler

```bash
ascelerate diagnostics logs <signature-id>
ascelerate diagnostics logs <signature-id> --frames 0
```

Örneklenen her olay cihazı, işletim sistemi ve uygulama sürümüyle, ardından çağrı yığınlarıyla gösterilir; App Store Connect'in sorumlu tuttuğu satır ▶ ile işaretlenir. `--frames` çağrı yığını başına satır sayısını sınırlar (varsayılan 40, tümü için 0).

## Metrikler

```bash
ascelerate diagnostics metrics <bundle-id>
ascelerate diagnostics metrics <bundle-id> --type launch,hang --all
```

Her metrik (açılış süresi, takılma oranı, en yüksek bellek, disk yazmaları, pil, sonlandırmalar, animasyon, depolama) uygulama sürümü başına, tüm cihazlar için tipik (50.) ve 90. yüzdelikte gösterilir; `--all` her cihaz modelini ekler. Apple'ın gerilemeleri ve yükselen eğilimleri önce gelir. `--build` tek bir derlemenin metriklerini gösterir.

Üçü de `--json` alır.
