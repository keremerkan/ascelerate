---
sidebar_position: 21
title: Apple Ads
---

# Apple Ads

Gérez vos campagnes Apple Ads (anciennement Search Ads) depuis la ligne de commande grâce à l'API Apple Ads Platform : rapports de performances, campagnes, groupes d'annonces, mots-clés et mots-clés négatifs, enchères et budgets, recommandations d'Apple et données de recherche de mots-clés. Les applications sont rapprochées de celles d'App Store Connect : `--app` accepte donc les mêmes Bundle ID et [alias](../getting-started/aliases.md) que toutes les autres commandes. Les campagnes et les groupes d'annonces sont désignés par leur **nom** (sans tenir compte de la casse) ou leur identifiant ; un nom inconnu affiche la liste des noms valides.

Chaque commande qui modifie quelque chose demande d'abord une confirmation (`-y` la passe), et `--dry-run` affiche les requêtes exactes sans les envoyer ([exécution à blanc](../guides/automation.md#dry-run)). Les modifications engagent de l'argent réel : essayez-les d'abord avec `--dry-run`. Les montants sont exprimés dans la devise du compte publicitaire.

## Configuration

Apple Ads utilise ses propres identifiants, distincts de votre clé d'API App Store Connect :

1. Dans Apple Ads, ouvrez **Réglages du compte → Gestion des utilisateurs**, invitez un utilisateur avec un rôle **API** (par exemple API Account Manager) et acceptez l'invitation avec le compte Apple de cet utilisateur.
2. Lancez la configuration :

```bash
ascelerate ads configure
```

ascelerate crée la paire de clés et affiche la clé publique. Connectez-vous à Apple Ads avec l'utilisateur API, collez la clé dans **Réglages du compte → API**, puis saisissez l'identifiant client (client ID), l'identifiant d'équipe (team ID) et l'identifiant de clé (key ID) qui y sont affichés. ascelerate liste ensuite les comptes publicitaires auxquels l'utilisateur a accès et enregistre celui que vous choisissez dans une section `ads` de `~/.ascelerate/config.json`. `--new-key` crée une nouvelle paire de clés.

```bash
ascelerate ads accounts          # comptes publicitaires et rôles de l'utilisateur API
```

## Rapports

```bash
ascelerate ads reports campaigns --days 30
ascelerate ads reports campaigns --from 2026-09-01 --to 2026-09-30 --app myapp
ascelerate ads reports campaigns --campaign "MyApp US" --by device
ascelerate ads reports adgroups --campaign "MyApp US"
ascelerate ads reports ads --campaign "MyApp US"
ascelerate ads reports keywords --campaign "MyApp US"
ascelerate ads reports search-terms --app myapp --days 14
```

| Rapport | Lignes |
|---|---|
| `campaigns` | Campagnes ; `--by age gender device country region city` les ventile |
| `adgroups` | Groupes d'annonces (par exemple pour comparer des groupes de test) |
| `ads` | Annonces, c'est-à-dire la page produit vers laquelle chaque groupe d'annonces envoie les taps |
| `keywords` | Mots-clés, avec l'enchère suggérée par Apple |
| `search-terms` | Ce que les utilisateurs ont réellement recherché, le mot-clé correspondant, et s'il provient de vos mots-clés ou de Search Match |

Tous les rapports acceptent `--days N` (aujourd'hui compris) ou `--from`/`--to`, ainsi que `--app`, `--campaign`, `--all` (pour inclure les lignes sans activité) et `--json`. Les dates suivent le fuseau horaire du compte publicitaire. Pour prendre une décision, comparez des journées complètes : les chiffres du jour sont encore en train d'arriver.

Chaque ligne indique les dépenses, les impressions, les taps, les installations, le taux de tap (TTR), le coût moyen par tap (CPT) et par installation (CPI), ainsi que deux taux de conversion :

- **CR (Tap)** : les installations qui suivent un tap, divisées par le nombre de taps. Mesure la capacité de votre page produit à convertir les personnes qui ont touché l'annonce.
- **CR (Total)** : toutes les installations, y compris les installations après affichage (des personnes qui ont vu l'annonce puis installé l'application plus tard sans la toucher), divisées par le nombre de taps. Ce taux peut dépasser 100 %.

:::note
Apple ne connaît l'âge, le genre et la localisation plus fine que le pays que pour les utilisateurs qui ont autorisé les publicités personnalisées : ces ventilations reviennent donc presque entièrement en « Unknown ». Les ventilations par appareil sont complètes. Les termes de recherche qu'Apple masque pour protéger la confidentialité apparaissent sous la forme « (low volume) ».
:::

## Campagnes

```bash
ascelerate ads campaigns list --app myapp
ascelerate ads campaigns pause "MyApp US"
ascelerate ads campaigns resume "MyApp US"
ascelerate ads campaigns budget "MyApp US" --daily 120
ascelerate ads campaigns bid "MyApp US Max Conv" --amount 2.50
```

`list` affiche pour chaque campagne son statut, ses pays, son budget quotidien et son mode d'enchère (Manual CPT ou Max Conversions). Pour une campagne Max Conversions, `bid` fixe le montant maximal qu'elle peut payer lors d'une enchère : déterminez-le d'après ce que vaut une installation pour vous, car un plafond inférieur au coût par tap habituel du pays prive la campagne de trafic.

### Créer une campagne

```bash
ascelerate ads campaigns create --like "MyApp US" --name "MyApp US Max Conv" --max-conversions --bid 2.50 --daily 25
ascelerate ads campaigns create --app myapp --name "MyApp DE" --country DE --daily 20 --default-bid 1.00 --search-match off
```

La campagne est créée **en pause**, avec son groupe d'annonces : un groupe automatisé pour Max Conversions, ou un groupe manuel avec `--default-bid`. `--like` reprend l'application, les pays et les réglages d'une campagne existante. `--enabled` la démarre immédiatement.

```bash
ascelerate ads campaigns target-cpa --app myapp --country US
```

Affiche le coût cible par installation suggéré par Apple pour une nouvelle campagne Max Conversions.

:::tip
Les campagnes d'une même application dans un même pays ne se font pas concurrence : Apple n'en admet qu'une seule à chaque enchère. Une nouvelle campagne lancée à côté d'une campagne active ne reçoit donc que le trafic restant. Pour tester une nouvelle campagne, déplacez-y le trafic, par exemple en limitant l'ancienne au nom de votre marque.
:::

## Groupes d'annonces

```bash
ascelerate ads adgroups --campaign "MyApp US"
ascelerate ads adgroups create --campaign "MyApp US" --name "Exact" --search-match off
ascelerate ads adgroups create --campaign "MyApp US" --name "Adults" --like "US Ad Group" --min-age 25
ascelerate ads adgroups update "Exact" --campaign "MyApp US" --default-bid 1.20
ascelerate ads adgroups pause "Exact" --campaign "MyApp US"
ascelerate ads adgroups resume "Exact" --campaign "MyApp US"
```

`create` reprend la tarification, les enchères et le ciblage d'un groupe d'annonces existant (`--like`, ou le seul groupe de la campagne) ; le groupe est créé **en pause**, sauf avec `--enabled`. `--min-age`/`--max-age` ciblent les âges de 18 à 64 ans (sans `--max-age`, le ciblage couvre 65 ans et plus). Le ciblage par âge n'atteint que les utilisateurs qui ont autorisé les publicités personnalisées, et Apple n'attribue pas à la campagne, dans les autres outils, les installations issues de groupes d'annonces ciblés par âge : jugez donc ces groupes sur leurs chiffres Apple Ads.

## Mots-clés et mots-clés négatifs

```bash
ascelerate ads keywords list --campaign "MyApp US"
ascelerate ads keywords add --campaign "MyApp US" --match exact --bid 1.50 "qr scanner" "barcode reader"
ascelerate ads keywords bid --campaign "MyApp US" --bid 1.25 "qr scanner"
ascelerate ads keywords pause --campaign "MyApp US" "barcode reader"
ascelerate ads keywords copy --campaign "MyApp US" --from "US Ad Group" --to "Exact"

ascelerate ads negatives list --campaign "MyApp US"
ascelerate ads negatives add --campaign "MyApp US" "free wifi"
ascelerate ads negatives add --campaign "MyApp US" --ad-group "Discovery" --match broad "wifi"
ascelerate ads negatives remove --campaign "MyApp US" "free wifi"
```

`--ad-group` désigne le groupe d'annonces lorsqu'une campagne en compte plusieurs. Les mots-clés négatifs s'appliquent à la campagne, sauf si `--ad-group` est indiqué, et sont en correspondance exacte, sauf avec `--match broad`. `keywords add` ignore les mots-clés qui existent déjà. Les campagnes Max Conversions fixent elles-mêmes leurs enchères : les enchères par mot-clé ne s'y appliquent pas.

## Quoi modifier

```bash
ascelerate ads opportunities --app myapp
ascelerate ads opportunities --campaign "MyApp US" --days 60 --min-taps 20 --brand "my app"
```

`opportunities` compare les termes de recherche d'une campagne (par défaut, les 30 derniers jours complets) avec ses mots-clés et ses propres moyennes, et propose :

- **Ajouter comme mot-clé exact** : un terme de recherche qui convertit à un bon coût par installation, sans mot-clé exact qui lui soit propre.
- **Lui donner sa propre enchère** : un terme qui convertit en profitant de l'enchère d'un autre mot-clé, à un coût plus élevé.
- **Exclure** : un terme qui génère des dépenses réelles sans aucune installation, ou dont le coût ou le taux de conversion est nettement moins bon.

Les recherches portant sur le nom de votre application sont exclues des moyennes et ne sont jamais proposées comme mots-clés négatifs ; ajoutez les autres graphies de votre marque avec `--brand`. Considérez les résultats comme des pistes et vérifiez que chaque terme correspond bien à votre application avant d'agir.

```bash
ascelerate ads recommendations
ascelerate ads recommendations apply <id>
ascelerate ads recommendations dismiss <id>
```

Les recommandations d'Apple en cours (modifications du budget quotidien et du CPA cible), avec le résultat attendu.

```bash
ascelerate ads history --app myapp --days 7
```

Toutes les modifications apportées aux campagnes, aux groupes d'annonces, aux mots-clés et aux mots-clés négatifs au cours des six derniers mois, y compris celles faites sur le site Apple Ads ou par Apple, avec les anciennes et les nouvelles valeurs. Utile avant d'interpréter une variation des performances.

## Recherche de mots-clés

```bash
ascelerate ads keywords suggest --app myapp --seed "qr code" "barcode" --country US GB
ascelerate ads keywords popularity --app myapp --country US --term "qr code" "qr scanner"
ascelerate ads keywords popularity --genre PRODUCTIVITY_UTILITIES --country US --contains scanner
ascelerate ads insights impression-share --app myapp --country US --weeks 4
```

- `suggest` renvoie les suggestions de mots-clés d'Apple pour vos termes de départ, avec leur popularité et les endroits où vous les ciblez déjà.
- `popularity` indique la popularité des termes de recherche dans un pays (de 1 à 100) et dans la catégorie de l'application. Les termes absents du classement de la catégorie sont listés à part.
- `impression-share` affiche votre part d'impressions publicitaires et votre rang pour les termes de recherche sur lesquels vos annonces sont apparues : une faible part sur un terme populaire qui convertit est une marge de progression, et une part inférieure à 100 % sur le nom de votre propre marque signifie que des concurrents enchérissent dessus.

Ces données de popularité sont également utiles pour choisir les mots-clés App Store (ASO).

## Annonces et pages de produit personnalisées

```bash
ascelerate ads product-pages --app myapp
ascelerate ads ads --campaign "MyApp US"
ascelerate ads ads create --campaign "MyApp US" --ad-group "Scanner" --product-page "Scanner Page" --enabled
ascelerate ads ads pause "Scanner Page ad" --campaign "MyApp US"
```

Une annonce envoie les taps d'un groupe d'annonces vers une page produit. Les groupes d'annonces sans annonce de votre part utilisent la page produit par défaut. Pour diriger les recherches liées à un besoin précis vers une [page de produit personnalisée](product-pages.md), donnez-leur un groupe d'annonces dédié (`adgroups create`, `keywords add`) et créez-lui une annonce. Une seule annonce est diffusée par groupe d'annonces : `--enabled` met donc en pause celle qui était diffusée jusque-là. Apple examine les nouvelles annonces ; `ads ads` affiche leur état d'examen.

## Avec un agent IA

Le [skill ascelerate](../guides/ai-skill.md) apprend aux agents de codage IA à lire ces rapports et à savoir quand proposer des modifications. Vous pouvez ainsi demander à un agent de passer en revue vos campagnes sur toutes vos applications, de trouver des mots-clés à ajouter ou à exclure, ou d'expliquer une variation des performances. Chaque commande accepte `--json`, et les agents ont pour consigne de vous montrer les modifications proposées et d'utiliser `--dry-run` avant d'envoyer quoi que ce soit.
