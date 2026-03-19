---
sidebar_position: 4
title: Captures d'écran et aperçus
---

# Captures d'écran et aperçus d'application

## Télécharger

```bash
ascelerate apps media download <bundle-id>
ascelerate apps media download <bundle-id> --folder my-media/ --version 2.1.0
```

Le téléchargement se fait par défaut dans `<bundle-id>-media/`, en utilisant la même structure de dossiers attendue par le téléversement.

## Téléverser

```bash
# Téléverser depuis un dossier
ascelerate apps media upload <bundle-id> --folder media/

# Téléverser depuis un fichier zip (par ex. exporté depuis app-store-screenshots)
ascelerate apps media upload <bundle-id> --folder screenshots.zip

# Téléverser vers une version spécifique
ascelerate apps media upload <bundle-id> --folder media/ --version 2.1.0

# Remplacer les médias existants dans les ensembles correspondants avant le téléversement
ascelerate apps media upload <bundle-id> --folder media/ --replace

# Mode interactif : choisir un dossier ou un zip depuis le répertoire courant
ascelerate apps media upload <bundle-id>
```

Lorsque `--folder` est omis, la commande liste tous les sous-répertoires et fichiers `.zip` du répertoire courant sous forme de sélecteur numéroté. Les fichiers zip sont extraits automatiquement avant le téléversement.

## Structure des dossiers

Organisez votre dossier de médias avec des sous-dossiers par langue et type d'affichage :

```
media/
├── en-US/
│   ├── APP_IPHONE_67/
│   │   ├── 01_home.png
│   │   ├── 02_settings.png
│   │   └── preview.mp4
│   └── APP_IPAD_PRO_3GEN_129/
│       └── 01_home.png
└── de-DE/
    └── APP_IPHONE_67/
        ├── 01_home.png
        └── 02_settings.png
```

- **Niveau 1 :** Langue (par ex. `en-US`, `de-DE`, `ja`)
- **Niveau 2 :** Nom du dossier de type d'affichage (voir le tableau ci-dessous)
- **Niveau 3 :** Fichiers médias -- les images (`.png`, `.jpg`, `.jpeg`) deviennent des captures d'écran, les vidéos (`.mp4`, `.mov`) deviennent des aperçus d'application
- Les fichiers sont téléversés dans l'ordre alphabétique par nom de fichier
- Les fichiers non pris en charge sont ignorés avec un avertissement

## Types d'affichage

App Store Connect exige des captures d'écran **`APP_IPHONE_67`** pour les applications iPhone et **`APP_IPAD_PRO_3GEN_129`** pour les applications iPad. Tous les autres types d'affichage sont facultatifs.

| Nom du dossier | Appareil | Captures d'écran | Aperçus |
|---|---|---|---|
| `APP_IPHONE_67` | iPhone 6.7" (iPhone 17 Pro Max, 16 Pro Max, 15 Pro Max) | **Requis** | Oui |
| `APP_IPAD_PRO_3GEN_129` | iPad Pro 12.9" (3e génération+) | **Requis** | Oui |

<details>
<summary>Tous les types d'affichage facultatifs</summary>

| Nom du dossier | Appareil | Captures d'écran | Aperçus |
|---|---|---|---|
| `APP_IPHONE_61` | iPhone 6.1" (iPhone 17 Pro, 16 Pro, 15 Pro) | Oui | Oui |
| `APP_IPHONE_65` | iPhone 6.5" (iPhone 11 Pro Max, XS Max) | Oui | Oui |
| `APP_IPHONE_58` | iPhone 5.8" (iPhone 11 Pro, X, XS) | Oui | Oui |
| `APP_IPHONE_55` | iPhone 5.5" (iPhone 8 Plus, 7 Plus, 6s Plus) | Oui | Oui |
| `APP_IPHONE_47` | iPhone 4.7" (iPhone SE 3e gén., 8, 7, 6s) | Oui | Oui |
| `APP_IPHONE_40` | iPhone 4" (iPhone SE 1re gén., 5s, 5c) | Oui | Oui |
| `APP_IPHONE_35` | iPhone 3.5" (iPhone 4s et antérieurs) | Oui | Oui |
| `APP_IPAD_PRO_3GEN_11` | iPad Pro 11" | Oui | Oui |
| `APP_IPAD_PRO_129` | iPad Pro 12.9" (1re/2e gén.) | Oui | Oui |
| `APP_IPAD_105` | iPad 10.5" (iPad Air 3e gén., iPad Pro 10.5") | Oui | Oui |
| `APP_IPAD_97` | iPad 9.7" (iPad 6e gén. et antérieurs) | Oui | Oui |
| `APP_DESKTOP` | Mac | Oui | Oui |
| `APP_APPLE_TV` | Apple TV | Oui | Oui |
| `APP_APPLE_VISION_PRO` | Apple Vision Pro | Oui | Oui |
| `APP_WATCH_ULTRA` | Apple Watch Ultra | Oui | Non |
| `APP_WATCH_SERIES_10` | Apple Watch Series 10 | Oui | Non |
| `APP_WATCH_SERIES_7` | Apple Watch Series 7 | Oui | Non |
| `APP_WATCH_SERIES_4` | Apple Watch Series 4 | Oui | Non |
| `APP_WATCH_SERIES_3` | Apple Watch Series 3 | Oui | Non |
| `IMESSAGE_APP_IPHONE_67` | iMessage iPhone 6.7" | Oui | Non |
| `IMESSAGE_APP_IPHONE_61` | iMessage iPhone 6.1" | Oui | Non |
| `IMESSAGE_APP_IPHONE_65` | iMessage iPhone 6.5" | Oui | Non |
| `IMESSAGE_APP_IPHONE_58` | iMessage iPhone 5.8" | Oui | Non |
| `IMESSAGE_APP_IPHONE_55` | iMessage iPhone 5.5" | Oui | Non |
| `IMESSAGE_APP_IPHONE_47` | iMessage iPhone 4.7" | Oui | Non |
| `IMESSAGE_APP_IPHONE_40` | iMessage iPhone 4" | Oui | Non |
| `IMESSAGE_APP_IPAD_PRO_3GEN_129` | iMessage iPad Pro 12.9" (3e gén.+) | Oui | Non |
| `IMESSAGE_APP_IPAD_PRO_3GEN_11` | iMessage iPad Pro 11" | Oui | Non |
| `IMESSAGE_APP_IPAD_PRO_129` | iMessage iPad Pro 12.9" (1re/2e gén.) | Oui | Non |
| `IMESSAGE_APP_IPAD_105` | iMessage iPad 10.5" | Oui | Non |
| `IMESSAGE_APP_IPAD_97` | iMessage iPad 9.7" | Oui | Non |

</details>

:::note
Les types d'affichage Watch et iMessage ne prennent en charge que les captures d'écran -- les fichiers vidéo dans ces dossiers sont ignorés avec un avertissement. L'option `--replace` supprime tous les éléments existants dans chaque ensemble correspondant avant le téléversement.
:::

## Utilisation avec app-store-screenshots

[app-store-screenshots](https://github.com/keremerkan/ascelerate/tree/main/skills/app-store-screenshots) est un skill compagnon pour les agents de codage IA qui génère des captures d'écran App Store prêtes pour la production. Il crée une page Next.js qui produit des mises en page marketing de style publicitaire utilisant des captures d'écran encadrées par `ascelerate screenshot frame` et les exporte sous forme de fichier zip prêt à être téléversé via `ascelerate apps media upload` :

```
en-US/APP_IPHONE_67/01_hero.png
en-US/APP_IPAD_PRO_3GEN_129/01_hero.png
de-DE/APP_IPHONE_67/01_hero.png
```

Installez le skill pour votre agent de codage IA :

```bash
npx skills add keremerkan/ascelerate
```

Téléversez le zip exporté directement :

```bash
ascelerate apps media upload <bundle-id> --folder screenshots.zip --replace
```

## Vérifier et retenter les médias bloqués

Parfois, des captures d'écran ou des aperçus restent bloqués en « traitement » après le téléversement. Utilisez `media verify` pour vérifier le statut et éventuellement retenter les éléments bloqués :

```bash
# Vérifier le statut de toutes les captures d'écran et aperçus
ascelerate apps media verify <bundle-id>

# Vérifier une version spécifique
ascelerate apps media verify <bundle-id> --version 2.1.0

# Retenter les éléments bloqués en utilisant les fichiers locaux du dossier de médias
ascelerate apps media verify <bundle-id> --folder media/
```

Sans `--folder`, la commande affiche un rapport de statut en lecture seule. Les ensembles dont tous les éléments sont complets affichent une ligne compacte ; les ensembles avec des éléments bloqués s'étendent pour montrer chaque fichier et son état. Avec `--folder`, elle propose de retenter les éléments bloqués en les supprimant et en les re-téléversant depuis les fichiers locaux correspondants, en préservant l'ordre de position d'origine.
