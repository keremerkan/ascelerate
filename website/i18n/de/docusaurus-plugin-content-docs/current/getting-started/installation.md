---
sidebar_position: 1
title: Installation
---

# Installation

## Voraussetzungen

- macOS 15+
- Swift 6.2+ (nur zum Kompilieren aus dem Quellcode)

## Homebrew

```bash
brew tap keremerkan/tap
brew trust keremerkan/tap
brew install ascelerate
```

Der Tap stellt eine vorgefertigte Binärdatei für Apple Silicon Macs bereit, sodass die Installation sofort erfolgt.

:::note
Seit Homebrew 6.0 müssen Taps von Drittanbietern ausdrücklich als vertrauenswürdig eingestuft werden, bevor ihr Code ausgeführt wird. Der obige `brew trust`-Schritt bestätigt den Tap. Alternativ fordert eine voll qualifizierte Installation (`brew install keremerkan/tap/ascelerate`) Sie interaktiv zur Bestätigung auf.
:::

## Installationsskript

```bash
curl -fsSL https://raw.githubusercontent.com/keremerkan/ascelerate/main/install.sh | bash
```

Lädt die neueste Version herunter, prüft, dass sie mit der Developer ID von ascelerate signiert ist, und installiert sie nach `/usr/local/bin` (legt den Ordner bei Bedarf an); dafür wird Ihr Passwort abgefragt. Nur für Apple Silicon. Später aktualisieren Sie mit `sudo ascelerate update`.

## Manueller Download

Laden Sie die neueste Version von [GitHub Releases](https://github.com/keremerkan/ascelerate/releases) herunter:

```bash
curl -L https://github.com/keremerkan/ascelerate/releases/latest/download/ascelerate-macos-arm64.tar.gz -o ascelerate.tar.gz
tar xzf ascelerate.tar.gz
sudo mkdir -p /usr/local/bin
sudo mv ascelerate /usr/local/bin/
```

Die Binärdatei ist mit der Developer ID von ascelerate (AKE Software GmbH) signiert und von Apple notarisiert, daher führt macOS sie ohne Warnung aus. `codesign -dv /usr/local/bin/ascelerate` zeigt die Signatur; `sudo ascelerate update` installiert spätere Versionen.

:::note
Vorgefertigte Binärdateien werden nur für Apple Silicon (arm64) bereitgestellt. Intel-Mac-Benutzer sollten aus dem Quellcode kompilieren.
:::

## Aus dem Quellcode kompilieren

```bash
git clone https://github.com/keremerkan/ascelerate.git
cd ascelerate
swift build -c release
strip .build/release/ascelerate
cp .build/release/ascelerate /usr/local/bin/
```

:::note
Der Release-Build dauert einige Minuten, da er den App-Store-Connect-Client kompiliert, den ascelerate aus Apples OpenAPI-Spezifikation generiert. `strip` entfernt Debug-Symbole und reduziert die Binärdatei von ca. 156 MB auf ca. 41 MB.
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
