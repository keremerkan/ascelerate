---
sidebar_position: 1
title: Installation
---

# Installation

## Voraussetzungen

- macOS 13+
- Swift 6.0+ (nur zum Kompilieren aus dem Quellcode)

## Homebrew

```bash
brew tap keremerkan/tap
brew install ascelerate
```

Der Tap stellt eine vorgefertigte Binärdatei für Apple Silicon Macs bereit, sodass die Installation sofort erfolgt.

## Installationsskript

```bash
curl -sSL https://raw.githubusercontent.com/keremerkan/asc-cli/main/install.sh | bash
```

Lädt die neueste Version herunter, installiert sie nach `/usr/local/bin` und entfernt automatisch das Quarantäne-Attribut. Nur für Apple Silicon.

## Manueller Download

Laden Sie die neueste Version von [GitHub Releases](https://github.com/keremerkan/asc-cli/releases) herunter:

```bash
curl -L https://github.com/keremerkan/asc-cli/releases/latest/download/ascelerate-macos-arm64.tar.gz -o ascelerate.tar.gz
tar xzf ascelerate.tar.gz
mv ascelerate /usr/local/bin/
```

Da die Binärdatei nicht signiert oder notarisiert ist, wird sie von macOS beim ersten Download unter Quarantäne gestellt. Entfernen Sie das Quarantäne-Attribut:

```bash
xattr -d com.apple.quarantine /usr/local/bin/ascelerate
```

:::note
Vorgefertigte Binärdateien werden nur für Apple Silicon (arm64) bereitgestellt. Intel-Mac-Benutzer sollten aus dem Quellcode kompilieren.
:::

## Aus dem Quellcode kompilieren

```bash
git clone https://github.com/keremerkan/asc-cli.git
cd asc-cli
swift build -c release
strip .build/release/ascelerate
cp .build/release/ascelerate /usr/local/bin/
```

:::note
Der Release-Build dauert einige Minuten, da die [asc-swift](https://github.com/aaronsky/asc-swift)-Abhängigkeit etwa 2500 generierte Quelldateien enthält, die die gesamte App Store Connect API abdecken. `strip` entfernt Debug-Symbole und reduziert die Binärdatei von ca. 175 MB auf ca. 59 MB.
:::

## Shell-Vervollständigung

Richten Sie die Tab-Vervollständigung für Unterbefehle, Optionen und Flags ein (unterstützt zsh und bash):

```bash
ascelerate install-completions
```

Dies erkennt Ihre Shell und konfiguriert alles automatisch. Starten Sie Ihre Shell neu oder öffnen Sie einen neuen Tab, um die Vervollständigung zu aktivieren.

## Version prüfen

```bash
ascelerate version     # Gibt die Versionsnummer aus
ascelerate --version   # Wie oben
ascelerate -v          # Wie oben
```
