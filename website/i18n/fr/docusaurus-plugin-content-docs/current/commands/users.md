---
sidebar_position: 22
title: Utilisateurs
---

# Utilisateurs

Les personnes de l’équipe et les invitations en attente : leurs rôles, les apps qu’elles voient et leur accès à Certificats, identifiants et profils. Une personne est désignée par son **adresse e-mail** ou son identifiant, une app par son bundle ID ou un alias. Modifier des rôles ou retirer quelqu’un demande une clé Admin.

## Lister

```bash
ascelerate users
ascelerate users info someone@example.com
ascelerate users invitations
```

`users` liste tout le monde avec ses rôles, le nombre d’apps visibles et l’accès à Certificats, identifiants et profils ; `info` montre une personne avec ses apps. `invitations` liste les invitations pas encore acceptées, avec leur date d’expiration. Les trois acceptent `--json`.

## Modifier

```bash
ascelerate users update someone@example.com --roles developer,marketing
ascelerate users update someone@example.com --apps com.example.app,myalias
ascelerate users update someone@example.com --all-apps --provisioning true
ascelerate users remove someone@example.com
```

`--roles` remplace ses rôles (`admin`, `finance`, `sales`, `marketing`, `app-manager`, `developer`, `access-to-reports`, `customer-support`, `create-apps`, …). `--apps` remplace les apps qu’elle voit ; `--all-apps` lui donne toutes les apps. Chaque commande liste les modifications et demande confirmation. `remove` retire la personne de l’équipe immédiatement.

## Inviter

```bash
ascelerate users invite --email someone@example.com --first-name Ada --last-name Lovelace --roles developer --apps com.example.app
ascelerate users cancel-invitation someone@example.com
```

App Store Connect envoie l’invitation dès sa création. Sans `--apps`, la personne voit toutes les apps ; `--provisioning` donne accès à Certificats, identifiants et profils.
