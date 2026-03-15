---
sidebar_position: 3
title: Takma Adlar
---

# Takma Adlar

Her seferinde tam bundle ID yazmak yerine kısa takma adlar oluşturabilirsiniz:

```bash
# Takma ad ekleyin (interaktif uygulama seçici)
asc alias add myapp

# Artık bundle ID kullanacağınız her yerde takma adı kullanabilirsiniz
asc apps info myapp
asc apps versions myapp
asc apps localizations view myapp

# Tüm takma adları listeleyin
asc alias list

# Takma adı kaldırın
asc alias remove myapp
```

Takma adlar `~/.asc/aliases.json` dosyasında saklanır. Nokta içermeyen her argüman takma ad olarak aranır -- gerçek bundle ID'ler (her zaman nokta içerir) değişmeden çalışır.

:::tip
Takma adlar tüm app, IAP, subscription ve build komutlarıyla çalışır. Provisioning komutları (`devices`, `certs`, `bundle-ids`, `profiles`) farklı bir tanımlayıcı alanı kullanır ve takma adları çözmez.
:::
