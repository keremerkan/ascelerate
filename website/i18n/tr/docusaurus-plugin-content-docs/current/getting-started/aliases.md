---
sidebar_position: 3
title: Takma Adlar
---

# Takma Adlar

Her seferinde tam bundle ID yazmak yerine kısa takma adlar oluşturabilirsiniz:

```bash
# Takma ad ekleyin (interaktif uygulama seçici)
ascelerate alias add myapp

# Artık bundle ID kullanacağınız her yerde takma adı kullanabilirsiniz
ascelerate apps info myapp
ascelerate apps versions myapp
ascelerate apps localizations view myapp

# Tüm takma adları listeleyin
ascelerate alias list

# Takma adı kaldırın
ascelerate alias remove myapp
```

Takma adlar `~/.ascelerate/aliases.json` dosyasında saklanır. Nokta içermeyen her argüman takma ad olarak aranır -- gerçek bundle ID'ler (her zaman nokta içerir) değişmeden çalışır.

:::tip
Takma adlar tüm app, IAP, subscription ve build komutlarıyla çalışır. Provisioning komutları (`devices`, `certs`, `bundle-ids`, `profiles`) farklı bir tanımlayıcı alanı kullanır ve takma adları çözmez.
:::
