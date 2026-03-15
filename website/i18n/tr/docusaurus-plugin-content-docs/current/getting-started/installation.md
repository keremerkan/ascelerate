---
sidebar_position: 1
title: Kurulum
---

# Kurulum

## Gereksinimler

- macOS 13+
- Swift 6.0+ (yalnızca kaynaktan derleme için)

## Homebrew

```bash
brew tap keremerkan/tap
brew install asc-cli
```

Tap, Apple Silicon Mac'ler için önceden derlenmiş bir binary sağlar, bu yüzden kurulum anlıktır.

## Kurulum betiği

```bash
curl -sSL https://raw.githubusercontent.com/keremerkan/asc-cli/main/install.sh | bash
```

En son sürümü indirir, `/usr/local/bin` dizinine kurar ve karantina özniteliğini otomatik olarak kaldırır. Yalnızca Apple Silicon.

## Manuel indirme

En son sürümü [GitHub Releases](https://github.com/keremerkan/asc-cli/releases) sayfasından indirin:

```bash
curl -L https://github.com/keremerkan/asc-cli/releases/latest/download/asc-macos-arm64.tar.gz -o asc.tar.gz
tar xzf asc.tar.gz
mv asc /usr/local/bin/
```

Binary imzalı veya notarize edilmiş olmadığından, macOS ilk indirmede karantinaya alır. Karantina özniteliğini kaldırın:

```bash
xattr -d com.apple.quarantine /usr/local/bin/asc
```

:::note
Önceden derlenmiş binary'ler yalnızca Apple Silicon (arm64) için sağlanır. Intel Mac kullanıcıları kaynaktan derlemelidir.
:::

## Kaynaktan derleme

```bash
git clone https://github.com/keremerkan/asc-cli.git
cd asc-cli
swift build -c release
strip .build/release/asc
cp .build/release/asc /usr/local/bin/
```

:::note
Release derlemesi birkaç dakika sürer çünkü [asc-swift](https://github.com/aaronsky/asc-swift) bağımlılığı, App Store Connect API yüzeyinin tamamını kapsayan ~2500 üretilmiş kaynak dosya içerir. `strip` debug sembollerini kaldırarak binary boyutunu ~175 MB'dan ~59 MB'a düşürür.
:::

## Shell tamamlama

Alt komutlar, seçenekler ve flag'ler için sekme tamamlamayı ayarlayın (zsh ve bash desteklenir):

```bash
asc install-completions
```

Bu, shell'inizi otomatik olarak algılar ve her şeyi yapılandırır. Etkinleştirmek için shell'inizi yeniden başlatın veya yeni bir sekme açın.

## Sürüm kontrolü

```bash
asc version     # Sürüm numarasını yazdırır
asc --version   # Yukarıdakiyle aynı
asc -v          # Yukarıdakiyle aynı
```
