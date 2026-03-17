---
sidebar_position: 3
title: Yapay Zeka Kodlama Skill'i
---

# Yapay Zeka Kodlama Skill'i

asc, yapay zeka kodlama ajanlarına (Claude Code, Cursor, Windsurf, GitHub Copilot) tüm komutlar, JSON formatları ve workflow'lar hakkında tam bilgi veren bir skill dosyasıyla birlikte gelir.

## Binary ile kurulum (yalnızca Claude Code)

```bash
ascelerate install-skill
```

Araç her çalıştırmada skill'in güncel olup olmadığını kontrol eder ve yeni sürüm varsa güncellemeyi teklif eder. Kaldırmak için:

```bash
ascelerate install-skill --uninstall
```

## npx ile kurulum (herhangi bir yapay zeka kodlama ajanı)

```bash
npx ascelerate-skill
```

Bu, ajanınızı seçmeniz için interaktif bir menü sunar ve skill'i uygun dizine kurar. Skill dosyası GitHub'dan alınır, bu yüzden her zaman günceldir.

Kaldırmak için:

```bash
npx ascelerate-skill --uninstall
```

## Skill'in sağladıkları

Skill kuruluyken yapay zeka kodlama ajanınız şunları yapabilir:

- Sizin adınıza herhangi bir asc komutunu çalıştırma
- Yayınlama süreciniz için workflow dosyaları oluşturma
- Birden fazla dilde yerelleştirmeleri yönetme
- Arşivleme, yükleme ve gönderme pipeline'ının tamamını yönetme
- Provisioning profilleri, sertifikalar ve cihazlarla çalışma
