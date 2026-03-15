---
sidebar_position: 11
title: Profils de provisionnement
---

# Profils de provisionnement

Toutes les commandes de profils prennent en charge le mode interactif -- les arguments sont facultatifs.

## Lister

```bash
asc profiles list
asc profiles list --type IOS_APP_STORE --state ACTIVE
```

## Détails

```bash
asc profiles info
asc profiles info "My App Store Profile"
```

## Télécharger

```bash
asc profiles download
asc profiles download "My App Store Profile" --output ./profiles/
```

## Créer

```bash
# Entièrement interactif
asc profiles create

# Non interactif
asc profiles create --name "My Profile" --type IOS_APP_STORE --bundle-id com.example.MyApp --certificates all
```

`--certificates all` utilise tous les certificats de la famille correspondante (distribution, développement ou Developer ID). Vous pouvez également spécifier des numéros de série : `--certificates ABC123,DEF456`.

## Supprimer

```bash
asc profiles delete
asc profiles delete "My App Store Profile"
```

## Réémettre

Réémettez des profils en les supprimant et en les recréant avec les derniers certificats de la famille correspondante :

```bash
# Interactif : choisir parmi tous les profils (affiche le statut)
asc profiles reissue

# Réémettre un profil spécifique par nom
asc profiles reissue "My Profile"

# Réémettre tous les profils invalides
asc profiles reissue --all-invalid

# Réémettre tous les profils quel que soit leur état
asc profiles reissue --all

# Réémettre tous les profils en utilisant tous les appareils activés pour dev/adhoc
asc profiles reissue --all --all-devices

# Utiliser des certificats spécifiques au lieu de la détection automatique
asc profiles reissue --all --to-certs ABC123,DEF456
```
