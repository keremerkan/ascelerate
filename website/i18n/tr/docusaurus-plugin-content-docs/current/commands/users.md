---
sidebar_position: 22
title: Kullanıcılar
---

# Kullanıcılar

Ekipteki kişiler ve bekleyen davetler: rolleri, gördükleri uygulamalar ve Sertifikalar, Tanımlayıcılar ve Profiller'e erişip erişemedikleri. Kişiler **e-posta adresi** veya kimliğiyle, uygulamalar bundle kimliği veya takma adıyla belirtilir. Rolleri değiştirmek veya birini çıkarmak için Yönetici anahtarı gerekir.

## Listeleme

```bash
ascelerate users
ascelerate users info someone@example.com
ascelerate users invitations
```

`users` herkesi rolleri, gördükleri uygulama sayısı ve Sertifikalar, Tanımlayıcılar ve Profiller'e erişimleriyle listeler; `info` bir kişiyi uygulamalarıyla birlikte gösterir. `invitations` henüz kabul edilmemiş davetleri sona erme tarihleriyle listeler. Üçü de `--json` alır.

## Değiştirme

```bash
ascelerate users update someone@example.com --roles developer,marketing
ascelerate users update someone@example.com --apps com.example.app,myalias
ascelerate users update someone@example.com --all-apps --provisioning true
ascelerate users remove someone@example.com
```

`--roles` rollerin yerine geçer (`admin`, `finance`, `sales`, `marketing`, `app-manager`, `developer`, `access-to-reports`, `customer-support`, `create-apps`, …). `--apps` görülen uygulamaların yerine geçer; `--all-apps` tüm uygulamaları verir. Her komut değişiklikleri listeler ve önce onay ister. `remove` kişiyi ekipten hemen çıkarır.

## Davet Etme

```bash
ascelerate users invite --email someone@example.com --first-name Ada --last-name Lovelace --roles developer --apps com.example.app
ascelerate users cancel-invitation someone@example.com
```

App Store Connect daveti oluşturulur oluşturulmaz e-postayla gönderir. `--apps` verilmezse kişi tüm uygulamaları görür; `--provisioning` Sertifikalar, Tanımlayıcılar ve Profiller'e erişim verir.
