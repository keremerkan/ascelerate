---
sidebar_position: 21
title: Xcode Cloud
---

# Xcode Cloud

Xcode Cloud build'lerini takip edin ve başlatın: ürünleriniz, bunların workflow'ları ve her build çalıştırmasının eylemleri, sorunları, test sonuçları ve artifact'leri.

Bir **ürün**, Xcode'da bir repository'yi ilk kez bağladığınızda oluşturulur (**Integrate > Create Workflow**); API ürün oluşturamaz. Sonrasında bu sayfadaki her şey komut satırından çalışır. Bir ürüne uygulamasının **bundle ID**'si (veya takma adı), adı ya da kimliğiyle; bir workflow'a **adı** veya kimliğiyle; bir build çalıştırmasına da **numarası** veya kimliğiyle başvurulur.

## Ürünler

```bash
ascelerate xcode-cloud products
```

Ekibin ürünlerini (uygulamalar ve framework'ler) bundle ID'leri ve repository'leriyle birlikte listeler.

## Workflow'lar

```bash
ascelerate xcode-cloud workflows <bundle-id>
ascelerate xcode-cloud workflows info <bundle-id> "Release"
ascelerate xcode-cloud workflows update <bundle-id> "Default" --manual-only
ascelerate xcode-cloud workflows update <bundle-id> "Release" --branch-changes "main,release/*" --xcode "Xcode 27.2" --clean false
ascelerate xcode-cloud workflows disable <bundle-id> "Nightly"
ascelerate xcode-cloud workflows enable <bundle-id> "Nightly"
ascelerate xcode-cloud workflows delete <bundle-id> "Old workflow"
```

`info`, bir workflow'un başlatma koşullarını (branch ve tag değişiklikleri, pull request'ler, zamanlamalar ve elle başlatılabilecekler), eylemlerini (scheme, platform ve dağıtım bilgisiyle build, test, analiz ve arşivleme) ve kullandığı repository'yi, projeyi, Xcode ve macOS sürümlerini gösterir. `update --manual-only`, bir workflow'un kendiliğinden başlamasını durdurur (branch ve tag değişiklikleri, pull request'ler, zamanlama); elle başlatılabilecekler korunur. `update` ayrıca adı, açıklamayı, temiz derlemeyi, “Restrict Editing” ayarını, Xcode ve macOS sürümlerini ve her başlatma koşulunu değiştirir: `--branch-changes`, `--tag-changes`, `--pull-requests` (`--pull-request-source` ile), `--manual-branches`, `--manual-tags` ve `--manual-pull-requests` adlar (`release/*` ile başlayan adlar için), `any` veya `off` alır; bunlara `--auto-cancel` ve `--remove-schedule` eşlik eder. Kaydetmeden önce değişiklikleri listeler ve onay ister. Kapatılmış bir workflow build başlatmaz. Bir workflow silindiğinde build çalıştırmaları silinmez.

## Build çalıştırmaları

```bash
ascelerate xcode-cloud runs <bundle-id>                         # en yeniden eskiye
ascelerate xcode-cloud runs <bundle-id> --workflow "Release" --limit 50
ascelerate xcode-cloud runs info <bundle-id> 42                 # ayrıntılar ve eylemler
ascelerate xcode-cloud runs issues <bundle-id> 42 [--errors]
ascelerate xcode-cloud runs tests <bundle-id> 42 [--failed]
ascelerate xcode-cloud runs logs <bundle-id> 42 [--action "Build - iOS"] [--show ci_post_clone.log]
ascelerate xcode-cloud runs artifacts <bundle-id> 42
ascelerate xcode-cloud runs artifacts <bundle-id> 42 --type LOG_BUNDLE --download ./logs
```

Her çalıştırma durumunu, derlenen branch, tag veya pull request'i, commit'i ve ne kadar sürdüğünü gösterir; `runs info` buna eylemlerini hata, uyarı ve başarısız test sayılarıyla ekler (Apple bu sayıları göndermez; her eylemin sorunlarından sayılır). `issues`, her eylemin hatalarını ve uyarılarını dosya ve satır bilgisiyle listeler; `tests`, test sonuçlarını hedef (cihaz ve işletim sistemi) başına, başarısız her testin hata mesajıyla birlikte listeler. `logs`, her eylemin log paketini okur: post-clone betiğinin, paket çözümlemesinin ve xcodebuild'in logları satır sayılarıyla listelenir veya `--show` ile yazdırılır. `artifacts` logları, arşivleri, result bundle'ları ve ürünleri listeler; `--download` bunları kaydeder (`--type` seçimi daraltır).

## Build başlatma

```bash
ascelerate xcode-cloud start <bundle-id> "Release" --branch main
ascelerate xcode-cloud start <bundle-id> "Release" --tag v2.1
ascelerate xcode-cloud start <bundle-id> "PR checks" --pull-request 128
ascelerate xcode-cloud rerun <bundle-id> 42 [--clean]
```

`start`, belirttiğiniz branch, tag veya pull request'i derler; hiçbirini belirtmezseniz Xcode Cloud, workflow'un başlatma koşulunun elle başlatmaya izin verdiği kaynağı derler. `rerun`, önceki bir çalıştırmanın commit'ini aynı workflow ile yeniden derler. `--clean` önbelleği kullanmadan derler. API bir build'i iptal edemez.

## Repository'ler ve Xcode sürümleri

```bash
ascelerate xcode-cloud repositories
ascelerate xcode-cloud xcode-versions
```

`xcode-versions`, Xcode Cloud'un sunduğu Xcode sürümlerini, her birinin çalıştığı macOS sürümleriyle birlikte listeler.

Tüm listeleme ve bilgi komutları `--json` seçeneğini kabul eder.
