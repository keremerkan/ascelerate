---
sidebar_position: 11
title: Profils de provisionnement
---

# Profils de provisionnement

Toutes les commandes de profils prennent en charge le mode interactif -- les arguments sont facultatifs.

## Lister

```bash
ascelerate profiles list
ascelerate profiles list --type IOS_APP_STORE --state ACTIVE
```

## Détails

```bash
ascelerate profiles info
ascelerate profiles info "My App Store Profile"
```

## Télécharger

```bash
ascelerate profiles download
ascelerate profiles download "My App Store Profile" --output ./profiles/
```

## Créer

```bash
# Entièrement interactif
ascelerate profiles create

# Non interactif
ascelerate profiles create --name "My Profile" --type IOS_APP_STORE --bundle-id com.example.MyApp --certificates all
```

`--certificates all` utilise tous les certificats de la famille correspondante (distribution, développement ou Developer ID). Vous pouvez également spécifier des numéros de série : `--certificates ABC123,DEF456`.

## Supprimer

```bash
ascelerate profiles delete
ascelerate profiles delete "My App Store Profile"
```

## Réémettre

Réémettez des profils en les supprimant et en les recréant avec les derniers certificats de la famille correspondante :

```bash
# Interactif : choisir parmi tous les profils (affiche le statut)
ascelerate profiles reissue

# Réémettre un profil spécifique par nom
ascelerate profiles reissue "My Profile"

# Réémettre tous les profils invalides
ascelerate profiles reissue --all-invalid

# Réémettre tous les profils quel que soit leur état
ascelerate profiles reissue --all

# Réémettre tous les profils en utilisant tous les appareils activés pour dev/adhoc
ascelerate profiles reissue --all --all-devices

# Utiliser des certificats spécifiques au lieu de la détection automatique
ascelerate profiles reissue --all --to-certs ABC123,DEF456
```
