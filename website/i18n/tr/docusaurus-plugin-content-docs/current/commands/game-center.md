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

## Etkinlikler

Etkinlik, oyunun oyuncuların doğrudan davet edilebildiği bir bölümüdür (bir seviye veya bir mod gibi). Başarıları ve puan tabloları, ona ait olanlardır.

```bash
ascelerate game-center activities <bundle-id> [--json]
ascelerate game-center activities create <bundle-id> --id duel --name "Duel" --play-style sync \
  --min-players 2 --max-players 2 [--party-code true] [--properties mode=duel] [--fallback-url https://example.com/duel]
ascelerate game-center activities update <bundle-id> duel --max-players 4 --fallback-url ""
ascelerate game-center activities link <bundle-id> duel --achievements first.win --leaderboards high.score
ascelerate game-center activities link <bundle-id> duel --leaderboards high.score --remove
```

`--play-style`, `sync` (oyuncular birlikte oynar) veya `async` (sırayla) alır. `--properties`, oyunun etkinliğe ait anahtar-değer özelliklerinin yerini alır. Yedek URL, oyunu olmayan oyuncular için bir web sayfasıdır ve en son sürüme aittir.

## Meydan Okumalar

Meydan okuma, oyuncuların arkadaşlarını uygulamanın puan tablolarından birindeki bir skoru geçmeye davet etmesini sağlar.

```bash
ascelerate game-center challenges <bundle-id> [--json]
ascelerate game-center challenges create <bundle-id> --id beat.score --name "Beat My Score" --leaderboard high.score --repeatable
ascelerate game-center challenges update <bundle-id> beat.score --leaderboard weekly.best
```

App Store Connect'in kuralları (komutlar bunları önceden denetler): bir puan tablosunun en fazla bir meydan okuması olur, her oyuncunun en iyi skorunu saymalıdır ve `--repeatable` olmayan bir meydan okuma yinelenen bir puan tablosu gerektirir.

## Diller ve Görseller

Başarılar, puan tabloları, setler, etkinlikler ve meydan okumalar aynı dil ve görsel komutlarına sahiptir; `achievements` yerine `leaderboards`, `sets`, `activities` veya `challenges` yazın:

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

Bir başarının yeni dili için adı ve iki açıklaması gerekir. Bir puan tablosu dilinde ad, isteğe bağlı bir açıklama, kendine ait bir `--formatter` ve skordan sonra gelen birim (`--suffix " points"`, `--suffix-singular " point"`) bulunur. Bir set dilinin yalnızca adı vardır; bir etkinlik veya meydan okuma dilinin adı ve açıklaması vardır (`--name`, `--description`).

Bir görsel tek bir dile aittir. Başarılar, puan tabloları ve setler için kare ve en az 512×512 olmalıdır (genellikle 512×512 veya 1024×1024); etkinlikler ve meydan okumalar için tam olarak 3840×2160 olmalıdır ve sürümleri ayrıca varsayılan bir görsel alır (`image upload --default`). PNG ya da JPEG. Yükleme mevcut görselin yerini alır ve Apple'ın kontrolünü bekler; böylece reddedilen bir görsel hemen bildirilir.

## Sıralama ve App Review

```bash
ascelerate game-center achievements reorder <bundle-id> first.win,high.five
ascelerate game-center achievements submit <bundle-id> first.win [--platform ios]
```

`reorder` (başarılar, puan tabloları ve setler), listelenenleri bu sırayla başa koyar; diğerleri oldukları gibi ardından gelir. `submit`, öğenin yeni sürümünü uygulamanın taslak gönderimine ekler (yoksa bir tane oluşturur). Taslağı `ascelerate apps review submit` ile gönderdiğinizde App Review'a gider. `apps review submit` de incelemeyi bekleyen değişiklikleri olan tüm öğeleri listeler ve gönderime eklemeyi önerir; kaç tane olduğunu `game-center <bundle-id>` gösterir.

## Gruplar

Bir grup; başarıları, puan tablolarını, setleri, etkinlikleri ve meydan okumaları ekibin uygulamaları arasında paylaştırır. Gruplar referans adıyla veya kimliğiyle belirtilir.

```bash
ascelerate game-center groups [--json]                  # the team's groups with their apps
ascelerate game-center groups create --name "My Games"
ascelerate game-center groups rename "My Games" --name "Our Games"
ascelerate game-center groups delete "Our Games"
ascelerate game-center groups add-app "Our Games" <bundle-id> --dry-run
```

Bir uygulamayı gruba eklemek geri alınamaz: Uygulama gruptan çıkamaz ve başarıları, puan tabloları ve diğer öğeleri gruba taşınır. `add-app` bunu belirtir ve önce sorar; `--dry-run` ile deneyin. Bir gruptaki uygulama için diğer `game-center` komutları grubun öğelerini listeler, oluşturur ve sıralar; `leaderboards default` ise Game Center'ın o uygulama için açtığı grup puan tablosunu belirler.

## Eşleştirme

Kurala dayalı eşleştirme tek bir uygulamaya değil ekibe aittir; bu yüzden bu komutlar bundle ID almaz. Bir **kural seti** oyuncu sayısını, kuralları ve takımları belirler; bir **kuyruk**, oyunların eşleşme isteklerini gönderdiği yerdir ve tek bir kural setiyle eşleştirir. Kural setleri ve kuyruklar referans adıyla veya kimliğiyle belirtilir.

```bash
ascelerate game-center matchmaking rule-sets [--json]
ascelerate game-center matchmaking rule-sets create --name Ranked --min 2 --max 4
ascelerate game-center matchmaking rule-sets info Ranked
ascelerate game-center matchmaking rules add Ranked --name SameVersion --type compatible \
  --expression "requests[0].appVersion == requests[1].appVersion" --description "Same app version"
ascelerate game-center matchmaking rules add Ranked --name Skill --type distance \
  --expression "requests[0].properties.skill" --description "Close skill" --weight 2
ascelerate game-center matchmaking teams add Ranked --name Red --min 1 --max 2
ascelerate game-center matchmaking queues create --name RankedQueue --rule-set Ranked [--experiment-rule-set RankedB] [--classic-apps com.example.MyApp]
ascelerate game-center matchmaking queues update RankedQueue --experiment-rule-set none
ascelerate game-center matchmaking test Ranked --file requests.json
```

Kurallar, Apple'ın JMESPath tabanlı kural dilinde yazılır (JMESPath'te aritmetik işleçler yoktur). Uyumluluk kuralı (compatible) `requests[0]` ve `requests[1]` isteklerini karşılaştırır; mesafe kuralı (distance) `requests[0]` için bir sayı verir ve sayıları birbirine daha yakın olan istekler önce eşleşir. Bir oyuncunun özellikleri `requests[0].properties.<anahtar>` olarak okunur. App Store Connect bir ifadeyi kaydederken yalnızca söz dizimini denetler; bu yüzden bir kural setini kullanmadan önce test edin.

`test`, örnek istekleri bir kural setinden geçirir ve Apple'ın yapacağı eşleşmeleri her oyuncunun takımıyla birlikte gösterir; hiçbir şey kaydedilmez. Dosya bir JSON dizisidir:

```json
[
  {"requestName": "alice", "bundleId": "com.example.MyApp", "platform": "IOS", "appVersion": "1.0",
   "secondsInQueue": 5, "locale": "EN-US", "players": [{"playerId": "alice", "properties": {"skill": "10"}}]},
  {"requestName": "bob", "bundleId": "com.example.MyApp", "platform": "IOS", "appVersion": "1.0",
   "secondsInQueue": 8, "locale": "EN-US", "players": [{"playerId": "bob", "properties": {"skill": "12"}}]}
]
```

Bir istek ayrıca `latitude`, `longitude`, `playerCount`, `minPlayers` ve `maxPlayers` verebilir. Bir kuyruğun kullandığı kural seti silinemez; önce kuyruğu değiştirin veya silin.
