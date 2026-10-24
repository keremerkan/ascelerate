---
sidebar_position: 1
title: Kurulum
---

# Kurulum

## Gereksinimler

- macOS 15+
- Swift 6.2+ (yalnızca kaynaktan derleme için)

## Homebrew

```bash
brew install ascelerate
```

Homebrew, Apple çipli Mac'lere hazır derlenmiş bir dosya kurar, Intel Mac'lerde ise kaynak koddan derler.

:::note
ascelerate'i daha önce `keremerkan/tap` tap'inden kurduysanız `brew update` onu Homebrew'un kendi formülüne taşır. Tap artık onu içermiyor.
:::

## Kurulum betiği

```bash
curl -fsSL https://raw.githubusercontent.com/keremerkan/ascelerate/main/install.sh | bash
```

En son sürümü indirir, ascelerate'in Developer ID'siyle imzalandığını doğrular ve `/usr/local/bin` dizinine kurar (gerekirse dizini oluşturur); bunun için parolanız sorulur. Yalnızca Apple Silicon. Daha sonra `sudo ascelerate update` ile güncelleyebilirsiniz.

## Manuel indirme

En son sürümü [GitHub Releases](https://github.com/keremerkan/ascelerate/releases) sayfasından indirin:

```bash
curl -L https://github.com/keremerkan/ascelerate/releases/latest/download/ascelerate-macos-arm64.tar.gz -o ascelerate.tar.gz
tar xzf ascelerate.tar.gz
sudo mkdir -p /usr/local/bin
sudo mv ascelerate /usr/local/bin/
```

Binary, ascelerate'in Developer ID'siyle (AKE Software GmbH) imzalanmış ve Apple tarafından notarize edilmiştir; bu nedenle macOS onu uyarı göstermeden çalıştırır. İmzayı `codesign -dv /usr/local/bin/ascelerate` gösterir; sonraki sürümleri `sudo ascelerate update` kurar.

:::note
Önceden derlenmiş binary'ler yalnızca Apple Silicon (arm64) için sağlanır. Intel Mac kullanıcıları kaynaktan derlemelidir.
:::

## Kaynaktan derleme

```bash
git clone https://github.com/keremerkan/ascelerate.git
cd ascelerate
swift build -c release
strip .build/release/ascelerate
cp .build/release/ascelerate /usr/local/bin/
```

:::note
Release derlemesi birkaç dakika sürer; çünkü bu sırada ascelerate'in Apple'ın OpenAPI spesifikasyonundan ürettiği App Store Connect istemcisi derlenir. `strip` debug sembollerini kaldırarak binary boyutunu ~156 MB'tan ~41 MB'a düşürür.
:::

## Shell tamamlama

Alt komutlar, seçenekler ve flag'ler için sekme tamamlamayı ayarlayın (zsh ve bash desteklenir):

```bash
ascelerate install-completions
```

Bu, shell'inizi otomatik olarak algılar ve her şeyi yapılandırır. Etkinleştirmek için shell'inizi yeniden başlatın veya yeni bir sekme açın.

## Sürüm kontrolü

```bash
ascelerate version     # Sürüm numarasını yazdırır
ascelerate --version   # Yukarıdakiyle aynı
ascelerate -v          # Yukarıdakiyle aynı
```
