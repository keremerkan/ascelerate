---
sidebar_position: 1
title: Installation
---

# Installation

## Prérequis

- macOS 13+
- Swift 6.0+ (uniquement pour la compilation depuis les sources)

## Homebrew

```bash
brew tap keremerkan/tap
brew install ascelerate
```

Le tap fournit un binaire pré-compilé pour les Mac Apple Silicon, l'installation est donc instantanée.

## Script d'installation

```bash
curl -sSL https://raw.githubusercontent.com/keremerkan/asc-cli/main/install.sh | bash
```

Télécharge la dernière version, l'installe dans `/usr/local/bin` et supprime automatiquement l'attribut de quarantaine. Apple Silicon uniquement.

## Téléchargement manuel

Téléchargez la dernière version depuis [GitHub Releases](https://github.com/keremerkan/asc-cli/releases) :

```bash
curl -L https://github.com/keremerkan/asc-cli/releases/latest/download/ascelerate-macos-arm64.tar.gz -o asc.tar.gz
tar xzf ascelerate.tar.gz
mv ascelerate /usr/local/bin/
```

Le binaire n'étant ni signé ni notarisé, macOS le mettra en quarantaine lors du premier téléchargement. Supprimez l'attribut de quarantaine :

```bash
xattr -d com.apple.quarantine /usr/local/bin/ascelerate
```

:::note
Les binaires pré-compilés sont fournis uniquement pour Apple Silicon (arm64). Les utilisateurs de Mac Intel doivent compiler depuis les sources.
:::

## Compilation depuis les sources

```bash
git clone https://github.com/keremerkan/asc-cli.git
cd asc-cli
swift build -c release
strip .build/release/ascelerate
cp .build/release/ascelerate /usr/local/bin/
```

:::note
La compilation en mode release prend quelques minutes car la dépendance [asc-swift](https://github.com/aaronsky/asc-swift) inclut environ 2500 fichiers sources générés couvrant l'intégralité de la surface de l'API App Store Connect. `strip` supprime les symboles de débogage, réduisant le binaire d'environ 175 Mo à environ 59 Mo.
:::

## Complétion shell

Configurez la complétion par tabulation pour les sous-commandes, options (supporte zsh et bash) :

```bash
ascelerate install-completions
```

Cette commande détecte votre shell et configure tout automatiquement. Redémarrez votre shell ou ouvrez un nouvel onglet pour activer la complétion.

## Vérifier votre version

```bash
ascelerate version     # Affiche le numéro de version
ascelerate --version   # Identique
ascelerate -v          # Identique
```
