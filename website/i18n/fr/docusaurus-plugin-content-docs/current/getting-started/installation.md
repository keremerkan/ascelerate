---
sidebar_position: 1
title: Installation
---

# Installation

## Prérequis

- macOS 15+
- Swift 6.2+ (uniquement pour la compilation depuis les sources)

## Homebrew

```bash
brew install ascelerate
```

Homebrew installe un binaire précompilé sur les Mac à puce Apple et compile depuis les sources sur les Mac Intel.

:::note
Si vous avez installé ascelerate depuis le tap `keremerkan/tap`, `brew update` le fait passer à la formule de Homebrew. Le tap ne le propose plus.
:::

## Script d'installation

```bash
curl -fsSL https://raw.githubusercontent.com/keremerkan/ascelerate/main/install.sh | bash
```

Télécharge la dernière version, vérifie qu'elle est signée avec le Developer ID d'ascelerate et l'installe dans `/usr/local/bin` (en créant le dossier si besoin), ce qui demande votre mot de passe. Apple Silicon uniquement. Mettez-la à jour plus tard avec `sudo ascelerate update`.

## Téléchargement manuel

Téléchargez la dernière version depuis [GitHub Releases](https://github.com/keremerkan/ascelerate/releases) :

```bash
curl -L https://github.com/keremerkan/ascelerate/releases/latest/download/ascelerate-macos-arm64.tar.gz -o ascelerate.tar.gz
tar xzf ascelerate.tar.gz
sudo mkdir -p /usr/local/bin
sudo mv ascelerate /usr/local/bin/
```

Le binaire est signé avec le Developer ID d'ascelerate (AKE Software GmbH) et notarisé par Apple : macOS l'exécute donc sans avertissement. `codesign -dv /usr/local/bin/ascelerate` affiche la signature ; `sudo ascelerate update` installe les versions suivantes.

:::note
Les binaires pré-compilés sont fournis uniquement pour Apple Silicon (arm64). Les utilisateurs de Mac Intel doivent compiler depuis les sources.
:::

## Compilation depuis les sources

```bash
git clone https://github.com/keremerkan/ascelerate.git
cd ascelerate
swift build -c release
strip .build/release/ascelerate
cp .build/release/ascelerate /usr/local/bin/
```

:::note
La compilation en mode release prend plusieurs minutes, car elle porte sur le client App Store Connect qu'ascelerate génère à partir de la spécification OpenAPI d'Apple. `strip` supprime les symboles de débogage, réduisant le binaire d'environ 156 Mo à environ 41 Mo.
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
