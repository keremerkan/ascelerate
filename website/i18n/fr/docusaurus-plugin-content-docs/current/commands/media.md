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
ascelerate apps media upload <bundle-id> media/

# Téléverser depuis une archive (zip, tar, tar.gz supportés)
ascelerate apps media upload <bundle-id> screenshots.zip

# Téléverser vers une version spécifique (ajoutez --platform pour les applications en achat universel)
ascelerate apps media upload <bundle-id> media/ --version 2.1.0
ascelerate apps media upload <bundle-id> media/ --version 2.1.0 --platform macos

# Remplacer les médias existants dans les ensembles correspondants avant le téléversement
ascelerate apps media upload <bundle-id> media/ --replace

# Mode interactif : choisir un dossier ou une archive depuis le répertoire courant
ascelerate apps media upload <bundle-id>
```

Lorsque l'argument dossier est omis, la commande liste tous les sous-répertoires et fichiers d'archive du répertoire courant sous forme de sélecteur numéroté. Les archives (zip, tar, tar.gz) sont extraites automatiquement avant le téléversement.

Chaque ligne de fichier commence par sa position dans l'exécution (`[57/203]`). Dans un terminal, la ligne indique aussi la part du fichier déjà téléversée pendant l'envoi.

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
| `APP_IPHONE_DUO` | iPhone Duo (voir [ci-dessous](#iphone-duo)) | Oui | Non |
| `PRODUCT_PAGE_HEADER` | En-tête de la page produit (voir [ci-dessous](#header-and-search-results)) | Oui | Non |
| `APP_STORE_SEARCH_RESULTS` | Résultats de recherche de l'App Store (voir [ci-dessous](#header-and-search-results)) | Oui | Non |
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

### iPhone Duo

App Store Connect ne propose pas d'ensemble de captures d'écran pour l'iPhone Duo. ascelerate téléverse les fichiers d'un dossier `APP_IPHONE_DUO` dans la bibliothèque de ressources de l'application, puis les place dans la localisation de la version, dans l'ordre des fichiers. Les tailles acceptées sont 2853×2007 ou 2007×2853 (écran intérieur, déplié) et 2034×1398 ou 1398×2034 (écran extérieur) ; les autres tailles sont refusées avant tout téléversement. Avec `--replace`, les captures iPhone Duo existantes de chaque locale sont d'abord supprimées.

Si un fichier échoue encore après les nouvelles tentatives, `media upload` replace les captures iPhone Duo de cette localisation à la fin de l'exécution, afin de conserver l'ordre des fichiers. `media verify` liste les captures iPhone Duo avec leur nom de fichier et leur état de traitement ; avec le dossier de médias, il signale aussi les localisations dont les captures iPhone Duo diffèrent du dossier par leurs fichiers ou leur ordre (relancez `media upload` avec `--replace` pour les corriger). Les aperçus d'application pour l'iPhone Duo ne sont pas encore pris en charge, `media download` n'inclut pas les captures iPhone Duo et `media prune` ne les supprime jamais.

### En-tête de la page produit et résultats de recherche {#header-and-search-results}

Deux autres dossiers sont téléversés via la bibliothèque de ressources. Chacun contient une image par localisation, qui n'est liée à aucune classe d'appareil : la version l'affiche sur tous les appareils (iPhone, iPad, iPhone Duo), et les deux fonctionnent pour les versions de toutes les plateformes.

- `PRODUCT_PAGE_HEADER` : l'image en haut de la page produit. PNG en 3840×1646 ou 5244×2950.
- `APP_STORE_SEARCH_RESULTS` : l'image affichée avec l'application dans les résultats de recherche de l'App Store. JPG ou PNG au format 3:2, de 1920×1280 à 3840×2560, ou PNG en 5244×2950.

Un téléversement remplace l'image actuelle de la localisation, avec ou sans `--replace` ; l'ancienne n'est supprimée qu'une fois la nouvelle téléversée. Les vidéos pour ces emplacements ne sont pas encore prises en charge. `media verify` les vérifie comme les captures iPhone Duo.

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
ascelerate apps media upload <bundle-id> screenshots.zip --replace
```

## Vérifier et retenter les médias bloqués

Parfois, des captures d'écran ou des aperçus restent bloqués en « traitement » après le téléversement. Utilisez `media verify` pour vérifier le statut et éventuellement retenter les éléments bloqués :

```bash
# Vérifier le statut de toutes les captures d'écran et aperçus
ascelerate apps media verify <bundle-id>

# Vérifier une version spécifique
ascelerate apps media verify <bundle-id> --version 2.1.0

# Retenter les éléments bloqués en utilisant les fichiers locaux du dossier de médias
ascelerate apps media verify <bundle-id> media/
```

Sans argument dossier, la commande affiche un rapport de statut en lecture seule. Les ensembles dont tous les éléments sont complets affichent une ligne compacte ; les ensembles avec des éléments bloqués s'étendent pour montrer chaque fichier et son état. Avec un argument dossier, elle propose de retenter les éléments bloqués en les supprimant et en les re-téléversant depuis les fichiers locaux correspondants, en préservant l'ordre de position d'origine.

## Purger les ensembles obsolètes

`--replace` lors du téléversement ne vide que les ensembles correspondant à un dossier local -- les ensembles côté serveur pour des tailles d'écran que vous ne fournissez plus conservent leurs captures d'écran obsolètes. `media prune` supprime les ensembles sans dossier local correspondant (locale/type d'affichage), après les avoir listés avec le nombre d'éléments et demandé confirmation :

```bash
ascelerate apps media prune <bundle-id> media/
ascelerate apps media prune <bundle-id> media/ --version 2.1.0 --platform ios
```

Les locales sans dossier local sont entièrement ignorées -- la commande ne purge qu'au sein des locales réellement gérées par le dossier.

## Retirer des images de la bibliothèque de ressources

`media remove` retire de la version un type d'image de la bibliothèque de ressources : `PRODUCT_PAGE_HEADER`, `APP_STORE_SEARCH_RESULTS` ou `APP_IPHONE_DUO`. La commande agit sur les localisations indiquées avec `--locale` ou sur toutes, et liste ce qu'elle a trouvé avant de demander confirmation :

```bash
ascelerate apps media remove <bundle-id> PRODUCT_PAGE_HEADER --locale en-US
ascelerate apps media remove <bundle-id> APP_STORE_SEARCH_RESULTS
ascelerate apps media remove <bundle-id> APP_IPHONE_DUO --locale en-US,tr --version 2.1.0
```

## Nettoyer la bibliothèque de ressources

Chaque application a une bibliothèque de ressources qui contient ses images téléversées, et les versions les partagent : les captures d'une nouvelle version sont les images de la version précédente, et les anciennes versions conservent les leurs. Une image reste donc utilisée tant qu'une version (ancienne comprise), une page produit personnalisée ou un événement la place. Quand ascelerate retire un placement (`media remove`, `media upload --replace` ou le remplacement d'une image d'en-tête ou de résultats de recherche), il supprime aussi l'image si plus rien ne l'utilise et qu'elle n'est jamais passée par l'App Review.

Des téléversements antérieurs peuvent malgré tout avoir laissé des images inutilisées dans la bibliothèque. `media library` compte les images et liste celles qui sont inutilisées ; avec `--delete-unused`, il les supprime après confirmation :

```bash
ascelerate apps media library <bundle-id>
ascelerate apps media library <bundle-id> --delete-unused
ascelerate apps media library <bundle-id> --only APP_IPHONE_DUO --delete-unused
```

`--only` limite la liste aux images qui correspondent aux types indiqués, d'après leur catégorie de ressource et leur taille en pixels : `PRODUCT_PAGE_HEADER`, `APP_STORE_SEARCH_RESULTS`, `APP_IPHONE_DUO`, un type d'affichage de captures comme `APP_IPHONE_67` (les tailles viennent d'App Store Connect) ou `UNFINISHED_UPLOADS` pour les téléversements dont le fichier n'est jamais arrivé. La bibliothèque peut ainsi être nettoyée type d'appareil par type d'appareil. Les images de moins d'une heure sont toujours conservées, car un téléversement en cours peut être sur le point de les placer, et une exécution qui atteint la limite horaire de l'API d'App Store Connect s'arrête et vous invite à la relancer plus tard.

Les images passées par l'App Review ne sont jamais supprimées, qu'elles soient placées ou non, et chaque image est revérifiée juste avant sa suppression.
