---
sidebar_position: 16
title: Rapports
---

# Rapports

Téléchargez les rapports Ventes et tendances, financiers et App Analytics. Les rapports de ventes et financiers sont fournis par Apple au format TSV compressé en gzip — `ascelerate` les décompresse et affiche un résumé (ou enregistre le fichier brut). App Analytics est récupéré via le flux de demande de rapport asynchrone d'Apple.

:::note Numéro de vendeur
`reports sales` et `reports finance` nécessitent votre **numéro de vendeur** (App Store Connect → Paiements et rapports financiers, par ex. `80012345`). Enregistrez-le une fois avec `ascelerate configure`, ou passez `--vendor-number` à chaque commande. `reports analytics` n'en a pas besoin.
:::

## Sales

Unités (téléchargements), revenus et activité des achats intégrés/abonnements. Affiche par défaut un résumé analysé, regroupé par application et par type de produit ; ajoutez `--raw` pour afficher le TSV ou `--output` pour l'enregistrer.

```bash
ascelerate reports sales
ascelerate reports sales --frequency WEEKLY
ascelerate reports sales --frequency MONTHLY --date 2026-05
ascelerate reports sales --frequency YEARLY --date 2025 --bundle-id com.example.App
ascelerate reports sales --frequency DAILY --date 2026-06-20 --output sales.tsv
```

- `--frequency` — `DAILY`, `WEEKLY`, `MONTHLY` ou `YEARLY` (par défaut `DAILY`).
- `--date` — `YYYY-MM-DD` pour quotidien/hebdomadaire (hebdomadaire = le dimanche qui clôt la semaine), `YYYY-MM` pour mensuel, `YYYY` pour annuel. Par défaut, la période complète la plus récente.
- `--type` — type de rapport (par défaut `SALES`) ; les autres incluent `SUBSCRIPTION`, `SUBSCRIBER`, `SUBSCRIPTION_EVENT`, `INSTALLS`, `PRE_ORDER`.
- `--sub-type` — `SUMMARY` (par défaut), `DETAILED`, `SUMMARY_TERRITORY`, `SUMMARY_CHANNEL`, `SUMMARY_INSTALL_TYPE`.
- `--bundle-id` — limite le résumé à une seule application (ou un alias).
- `--vendor-number` — remplace le numéro de vendeur configuré.
- `--output` / `--raw` — enregistre le TSV brut dans un fichier, ou l'affiche au lieu d'un résumé.

Le résumé regroupe les unités par titre et par **identifiant de type de produit** — utile, car un même rapport mélange les premiers téléchargements (`1*`/`3*`), les mises à jour (`7*`) et les achats intégrés (`IA*`). Utilisez `--raw` pour les données complètes.

## Finance

Unités et revenus partenaires pour une période fiscale, par région.

```bash
ascelerate reports finance --date 2026-05 --region US
ascelerate reports finance --date 2026-05 --region US --type FINANCE_DETAIL --output finance.tsv
```

- `--date` — période fiscale au format `YYYY-MM`, où le mois correspond à la **période fiscale d'Apple (01–12)**, et non à un mois calendaire. Obligatoire.
- `--region` — code de région, par ex. `US`, `EU`, `GB`, `JP`, `AU`, `WW` (monde entier). Obligatoire.
- `--type` — `FINANCIAL` (par défaut) ou `FINANCE_DETAIL`.
- `--vendor-number`, `--output`, `--raw` — comme ci-dessus.

Le résumé totalise la quantité par titre et les revenus par devise.

## Analytics

Données de rapport App Analytics — téléchargements, impressions, vues de la page produit, sessions, et plus encore. Apple les génère de manière asynchrone : la commande trouve (ou crée, après confirmation) une demande de rapport pour l'application, puis télécharge les segments du rapport.

```bash
ascelerate reports analytics <bundle-id>
ascelerate reports analytics <bundle-id> --category APP_USAGE --granularity WEEKLY
ascelerate reports analytics <bundle-id> --report-name "App Store Discovery and Engagement Detailed" --output ./analytics
```

- `--category` — `APP_STORE_ENGAGEMENT` (par défaut), `APP_USAGE`, `COMMERCE`, `FRAMEWORK_USAGE`, `PERFORMANCE`.
- `--granularity` — `DAILY` (par défaut), `WEEKLY`, `MONTHLY`.
- `--report-name` — sélectionne un rapport spécifique lorsqu'une catégorie en contient plusieurs.
- `--processing-date` — l'instance à télécharger (`YYYY-MM-DD`) ; par défaut, la plus récente.
- `--ongoing` — utilise une demande de rapport continue plutôt qu'un instantané ponctuel.
- `--output` — répertoire pour les fichiers de segments téléchargés (par défaut `./<app>-analytics`).

Un instantané fraîchement créé n'est pas prêt immédiatement — Apple a besoin de temps pour le générer. Relancez la commande après quelques minutes pour télécharger les segments.

:::info Notes
L'API App Store Connect n'expose pas le nombre de notes agrégé ni la moyenne/l'histogramme des notes en étoiles — uniquement les avis individuels (voir [Avis clients](./reviews.md)). Pour les chiffres de téléchargement et de revenus, utilisez les rapports ci-dessus.
:::
