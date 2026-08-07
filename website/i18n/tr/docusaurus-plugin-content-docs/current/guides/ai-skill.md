---
sidebar_position: 3
title: Yapay Zeka Kodlama Skill'i
---

# Yapay Zeka Kodlama Skill'i

asc, yapay zeka kodlama ajanlarına (Claude Code, Grok Build, Cursor, Windsurf, GitHub Copilot) tüm komutlar, JSON formatları ve workflow'lar hakkında tam bilgi veren bir skill dosyasıyla birlikte gelir.

## Binary ile kurulum

```bash
ascelerate install-skill          # algılanan her ajan için kur/güncelle
ascelerate install-skill --all    # desteklenen tüm ajanları dahil et (ör. Copilot)
```

Claude Code, Grok Build (Claude Code skill yolunu doğrudan okur), Cursor ve Windsurf'ü otomatik algılar (ve `--all` ile GitHub Copilot'ı), skill'i her biri için kurar veya günceller ve her çalıştırmada skill'in güncel olup olmadığını kontrol eder. Tüm ajanlardan kaldırmak için:

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
