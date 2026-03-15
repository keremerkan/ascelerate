---
sidebar_position: 3
title: Skill pour agent IA
---

# Skill pour agent IA

asc est livré avec un fichier de skill qui donne aux agents de codage IA (Claude Code, Cursor, Windsurf, GitHub Copilot) une connaissance complète de toutes les commandes, formats JSON et workflows.

## Installation via le binaire (Claude Code uniquement)

```bash
asc install-skill
```

L'outil vérifie la présence de skills obsolètes à chaque exécution et vous propose de mettre à jour après les mises à niveau. Pour désinstaller :

```bash
asc install-skill --uninstall
```

## Installation via npx (tout agent de codage IA)

```bash
npx asc-skill
```

Cela présente un menu interactif pour sélectionner votre agent et installe le skill dans le répertoire approprié. Le fichier de skill est récupéré depuis GitHub, il est donc toujours à jour.

Pour désinstaller :

```bash
npx asc-skill --uninstall
```

## Ce que le skill permet

Avec le skill installé, votre agent de codage IA peut :

- Exécuter n'importe quelle commande asc en votre nom
- Construire des fichiers de workflow pour votre processus de publication
- Gérer les localisations dans plusieurs langues
- Prendre en charge le pipeline complet archive, téléversement et soumission
- Travailler avec les profils de provisionnement, les certificats et les appareils
