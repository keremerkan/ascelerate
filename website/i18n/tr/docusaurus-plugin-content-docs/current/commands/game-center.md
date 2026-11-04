---
sidebar_position: 18
title: Game Center
---

# Game Center

Bir uygulamanın başarıları, puan tabloları ve puan tablosu setleri; dilleri, görselleri ve sıralarıyla. Her biri **kimliğiyle** (oyunun kullandığı vendor identifier), referans adıyla veya Apple kimliğiyle belirtilir.

Metinleri ve görselleri bir **sürümde** durur. Yeni bir başarı, puan tablosu veya set, Prepare for Submission durumundaki 1. sürümle başlar ve bir sürüm App Review'a uygulamayla birlikte gider. Yayında olan birini değiştirmek için komut, sorduktan sonra önce onun bir sonraki sürümünü oluşturur.

## Game Center'ı Açma

```bash
ascelerate game-center <bundle-id>                      # açık mı, sayılar, varsayılan puan tablosu
ascelerate game-center enable <bundle-id>
ascelerate game-center version <bundle-id> --enabled true   # App Store sürümünün Game Center anahtarı
```

App Store Connect API, açıldıktan sonra bir uygulamanın Game Center'ını kapatamaz. Bundle ID'nin Game Center özelliğine sahip olması gerekir. `version`, hazırlanmakta olan sürümde ya da `--version` ile belirtilen sürümde çalışır.

## Başarılar

```bash
ascelerate game-center achievements <bundle-id> [--json]
ascelerate game-center achievements info <bundle-id> first.win
ascelerate game-center achievements create <bundle-id> --id first.win --name "First Win" --points 10 [--hidden] [--repeatable]
ascelerate game-center achievements update <bundle-id> first.win --points 20 --hidden false
ascelerate game-center achievements update <bundle-id> first.win --archived true
ascelerate game-center achievements delete <bundle-id> first.win
```

Bir uygulamanın başarıları toplam 1.000 puanı paylaşır ve her biri 1 ile 100 arasında puan verir. `--hidden`, bir başarıyı oyuncu kazanana kadar gizli tutar. Yayında bulunmuş bir başarı silinemez; bunun yerine arşivleyin.

## Puan Tabloları

```bash
ascelerate game-center leaderboards <bundle-id> [--json]
ascelerate game-center leaderboards create <bundle-id> --id high.score --name "High Score"
ascelerate game-center leaderboards create <bundle-id> --id weekly.time --name "Weekly Time" \
  --formatter elapsed-time-second --sort low --submission recent --min 0 --max 3600 \
  --recurrence-start 2026-12-07T00:00:00Z --recurrence-duration PT168H --recurrence-rule "FREQ=DAILY;INTERVAL=7"
ascelerate game-center leaderboards update <bundle-id> weekly.time --hidden true
ascelerate game-center leaderboards default <bundle-id> high.score
```

Varsayılan olarak skorlar tam sayıdır, yüksek skorlar önde yer alır ve her oyuncunun en iyi skoru sayılır. `--formatter`; `integer`, `decimal-point-1-place` ile `decimal-point-3-place` arası, `elapsed-time-centisecond`, `elapsed-time-second`, `elapsed-time-minute` veya `money-dollar-decimal` gibi bir para birimi alır.

Yinelenen bir puan tablosu düzenli aralıklarla baştan başlar. Süre saat veya dakika olarak verilir (`PT24H` ya da bir hafta için `PT168H`); kural dakika, saat veya gün olarak yinelenir (`FREQ=DAILY;INTERVAL=7` her hafta yeniden başlatır). Bir skor aralığı yalnızca bütün olarak, `--min "" --max ""` ile temizlenir.

İlk puan tablosu, Game Center'ın açıldığı varsayılan puan tablosu olur; `default` bunu değiştirir.

## Puan Tablosu Setleri

```bash
ascelerate game-center sets <bundle-id>
ascelerate game-center sets create <bundle-id> --id all.scores --name "All Scores" --leaderboards high.score,weekly.time
ascelerate game-center sets update <bundle-id> all.scores --leaderboards weekly.time,high.score
```

`--leaderboards`, setin puan tablolarını mevcut olanların yerine bu sırayla belirler.

## Diller ve Görseller

Başarılar, puan tabloları ve setler aynı dil ve görsel komutlarına sahiptir; `achievements` yerine `leaderboards` veya `sets` yazın:

```bash
ascelerate game-center achievements localizations <bundle-id> first.win
ascelerate game-center achievements localizations set <bundle-id> first.win --locale en-US \
  --name "First Win" --before-earned "Win a round." --after-earned "You won a round."
ascelerate game-center achievements localizations export <bundle-id> first.win --output first-win.json
ascelerate game-center achievements localizations import <bundle-id> first.win --file first-win.json
ascelerate game-center achievements localizations delete <bundle-id> first.win --locale tr

ascelerate game-center achievements image upload <bundle-id> first.win --locale en-US icon.png
ascelerate game-center achievements image delete <bundle-id> first.win --locale en-US
```

Bir başarının yeni dili için adı ve iki açıklaması gerekir. Bir puan tablosu dilinde ad, isteğe bağlı bir açıklama, kendine ait bir `--formatter` ve skordan sonra gelen birim (`--suffix " points"`, `--suffix-singular " point"`) bulunur. Bir set dilinin yalnızca adı vardır.

Bir görsel tek bir dile aittir. Kare ve en az 512×512 olmalıdır (genellikle 512×512 veya 1024×1024), PNG ya da JPEG. Yükleme, dilin mevcut görselinin yerini alır ve Apple'ın kontrolünü bekler; böylece reddedilen bir görsel hemen bildirilir.

## Sıralama ve App Review

```bash
ascelerate game-center achievements reorder <bundle-id> first.win,high.five
ascelerate game-center achievements submit <bundle-id> first.win [--platform ios]
```

`reorder`, listelenenleri bu sırayla başa koyar; diğerleri oldukları gibi ardından gelir. `submit`, öğenin yeni sürümünü uygulamanın taslak gönderimine ekler (yoksa bir tane oluşturur). Taslağı `ascelerate apps review submit` ile gönderdiğinizde App Review'a gider.
