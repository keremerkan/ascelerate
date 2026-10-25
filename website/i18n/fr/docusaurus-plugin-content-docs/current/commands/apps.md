---
sidebar_position: 1
title: Applications
---

# Applications

## Lister les applications

```bash
ascelerate apps list
```

## Détails d'une application

```bash
ascelerate apps info <bundle-id>
```

## Lister les versions

```bash
ascelerate apps versions <bundle-id>
```

Les commandes `apps list`, `apps info` et `apps versions` acceptent toutes `--json` pour une sortie lisible par machine ([conventions](../guides/automation.md#json-output)).

## Créer une version

```bash
ascelerate apps create-version <bundle-id> <version-string>
ascelerate apps create-version <bundle-id> 2.1.0 --platform ios --release-type manual
```

L'option `--release-type` est facultative -- son omission reprend le paramètre de la version précédente.

:::note Achat universel
Pour les applications en achat universel (une seule fiche App Store couvrant iOS, macOS, tvOS et/ou visionOS), la même chaîne de version peut exister une fois par plateforme. `create-version` et `review submit` ciblent iOS par défaut -- passez `--platform macos` (ou `tvos`, `visionos`) pour viser une autre plateforme. Toutes les autres commandes liées à une version (localisations, médias, association de build, vérifications préalables, informations et pièces jointes d'examen, `resolve-issues`/`cancel-submission`, déploiement progressif, publication manuelle) acceptent elles aussi une option `--platform` facultative ; sans elle, elles demandent de choisir dès qu'une version (ou une soumission d'examen active) correspond à plusieurs plateformes -- avec `--yes`, elles refusent en affichant une indication au lieu de demander.
:::

## Copyright

```bash
ascelerate apps copyright <bundle-id>
ascelerate apps copyright <bundle-id> --set "2026 Your Name" --version 2.1.0 --platform macos
```

Sans `--set`, la mention de copyright actuelle est affichée. La mise à jour nécessite que la version soit dans un état modifiable.

## Examen

### Vérifier le statut d'examen

```bash
ascelerate apps review status <bundle-id>
ascelerate apps review status <bundle-id> --version 2.1.0
```

Ajoutez `--json` pour obtenir les soumissions — y compris l'état de chaque élément — au format JSON lisible par machine.

### Soumettre pour examen {#submit-for-review}

```bash
ascelerate apps review submit <bundle-id>
ascelerate apps review submit <bundle-id> --version 2.1.0
ascelerate apps review submit <bundle-id> --platform macos
```

Lors de la soumission, la commande détecte automatiquement les achats intégrés et les abonnements avec des modifications en attente et propose de les soumettre en même temps que la version de l'application. Les modifications en attente sont lues dans l'historique des versions de chaque produit (une version à l'état « Prepare for Submission », « Ready for Review » ou dans un état rejeté), ce qui permet de détecter aussi les modifications limitées aux captures d'écran. `apps review status` associe les éléments des soumissions actives à la version de l'application ou au produit auxquels ils se rapportent.

### Résoudre les éléments rejetés

Après avoir corrigé les problèmes et répondu dans le Centre de résolution :

```bash
ascelerate apps review resolve-issues <bundle-id>
```

### Annuler la soumission

```bash
ascelerate apps review cancel-submission <bundle-id>
```

### Informations pour l'examen de l'app

Affichez ou mettez à jour les coordonnées, le compte de démonstration et les notes fournis à l'examen de l'app. Sans option, les valeurs actuelles sont affichées ; passez une option de champ pour la mettre à jour (les champs omis restent inchangés).

```bash
ascelerate apps review info <bundle-id>
ascelerate apps review info <bundle-id> --contact-email vous@example.com --demo-account-name reviewer --demo-account-password "hunter2" --demo-account-required true --notes "Étapes de test…"

# Pièces jointes (vidéos de démo, documents, etc.)
ascelerate apps review attachment list <bundle-id>
ascelerate apps review attachment upload <bundle-id> demo.mp4
ascelerate apps review attachment delete <attachment-id>
```

## Vérifications préalables

Avant de soumettre pour examen, exécutez `preflight` pour vérifier que tous les champs requis sont remplis pour chaque langue :

```bash
# Vérifier la dernière version modifiable
ascelerate apps review preflight <bundle-id>

# Vérifier une version spécifique
ascelerate apps review preflight <bundle-id> --version 2.1.0
```

La commande vérifie l'état et le build de la version (traité, avec la conformité à l'exportation renseignée), le copyright, le contact et la connexion pour App Review, ainsi que la catégorie principale, les droits sur le contenu, le prix et la disponibilité de l'application. Elle parcourt ensuite chaque langue : informations de l'application (nom et, dans la langue principale, URL de politique de confidentialité), textes de la version (description et mots-clés dans chaque langue, URL d'assistance dans la langue principale) et captures d'écran. Une langue sans captures d'écran propres affiche celles de la langue principale sur l'App Store : seule la langue principale en a donc besoin :

```
Preflight checks for MyApp v2.1.0 (Prepare for Submission)

Check                                Status
──────────────────────────────────────────────────────────────────
Version state                        ✓ Prepare for Submission
Build attached                       ✓ Build 42
Copyright                            ✓ 2026 Your Name
Review contact                       ✓ Jane Doe, jane@example.com
Sign-in                              ✓ Not required
Category                             ✓ Productivity
Content rights                       ✓ Does Not Use Third Party Content
Price                                ✓ Set
Availability                         ✓ 175 territories

en-US (English (United States))
  App info                           ✓ All fields filled
  Localizations                      ✓ All fields filled
  Screenshots                        ✓ 2 sets, 10 screenshots

de-DE (German (Germany))
  App info                           ✓ All fields filled
  Localizations                      ✗ Missing: Keywords, What's New
  Screenshots                        ✓ None (uses en-US's)
──────────────────────────────────────────────────────────────────
Result: 14 passed, 1 failed
```

Les achats intégrés et les abonnements sont vérifiés pour leurs prix et un état compatible avec une soumission. Un produit que vous avez retiré de la vente (Developer Removed from Sale) est indiqué comme ignoré (–) et ne fait pas échouer la vérification ; la ligne de résultat le compte à part.

Les nouveautés ne sont vérifiées que pour les mises à jour, c'est-à-dire lorsqu'une version de la même plateforme a déjà été publiée. Une publication sur une autre plateforme ne compte pas : la première version Mac d'une app iOS n'en a pas besoin.

La commande se termine avec un code de sortie non nul lorsqu'une vérification échoue, ce qui la rend adaptée aux pipelines CI et aux fichiers de workflow. Avec `--json`, elle émet un rapport structuré au lieu du tableau — un booléen `passed` plus une entrée par vérification (`group`, `name`, `passed`, `detail`) — tout en conservant le même comportement de code de sortie, afin que les pipelines CI puissent signaler exactement quelle vérification a échoué.

## Déploiement progressif

```bash
# Voir le statut du déploiement progressif
ascelerate apps phased-release <bundle-id>

# Activer le déploiement progressif (démarre inactif, s'active quand la version est publiée)
ascelerate apps phased-release <bundle-id> --enable

# Mettre en pause, reprendre ou terminer un déploiement progressif
ascelerate apps phased-release <bundle-id> --pause
ascelerate apps phased-release <bundle-id> --resume
ascelerate apps phased-release <bundle-id> --complete

# Supprimer entièrement le déploiement progressif
ascelerate apps phased-release <bundle-id> --disable
```

## Publication manuelle

Lorsque l'option de publication d'une version est définie sur manuelle, la version approuvée reste en « Pending Developer Release » (en attente de publication par le développeur) jusqu'à ce que vous la publiiez :

```bash
# Publier la version en attente de publication par le développeur
ascelerate apps release <bundle-id>

# Cibler une version ou une plateforme spécifique
ascelerate apps release <bundle-id> --version 2.1.0 --platform macos
```

## Déclarations d'accessibilité

L'App Store indique les fonctionnalités d'accessibilité qu'une application prend en charge, déclarées par famille d'appareils : VoiceOver, Contrôle vocal, Texte plus grand, Interface sombre, Différencier sans la couleur, Contraste suffisant, Réduction des animations, Sous-titres et Audiodescriptions.

```bash
# Voir les déclarations (brouillon ou publiées) par famille d'appareils
ascelerate apps accessibility <bundle-id>

# Déclarer ce que l'application prend en charge sur iPhone, et le publier
ascelerate apps accessibility set <bundle-id> --device iphone --supports voiceover,larger-text,dark-interface --publish

# Publier les déclarations en brouillon telles quelles
ascelerate apps accessibility publish <bundle-id>
```

`set` déclare la liste complète : les fonctionnalités que vous omettez sont déclarées comme non prises en charge (`--supports none` n'en déclare aucune). Familles d'appareils : `iphone`, `ipad`, `mac`, `apple-tv`, `apple-watch`, `vision`. Sans `--publish`, la déclaration reste un brouillon. La publication d'une déclaration modifiée remplace celle qui était publiée ; `--all` liste aussi les déclarations remplacées. Ne déclarez que ce sur quoi les utilisateurs peuvent compter dans les tâches courantes de l'application.

## Disponibilité territoriale

```bash
# Voir dans quels territoires l'application est disponible
ascelerate apps availability <bundle-id>

# Afficher les noms complets des pays
ascelerate apps availability <bundle-id> --verbose

# Rendre des territoires disponibles ou indisponibles
ascelerate apps availability <bundle-id> --add CHN,RUS
ascelerate apps availability <bundle-id> --remove CHN
```

## Prix de l'application

```bash
# Prix de base, prix fixés manuellement et changements prévus (--all : tous les territoires ; --json)
ascelerate apps pricing <bundle-id>
ascelerate apps pricing tiers <bundle-id> --territory USA

# Prix de base, immédiatement ou à partir d'une date (dans la devise du territoire de base ; 0 pour gratuit)
ascelerate apps pricing set <bundle-id> --price 0.99
ascelerate apps pricing set <bundle-id> --price 1.99 --start-date 2026-12-01

# Prix manuels : un territoire, conserver les prix actuels d'Apple ou les rendre à Apple
ascelerate apps pricing override <bundle-id> --territory FRA --price 0.99
ascelerate apps pricing keep <bundle-id> --territories all
ascelerate apps pricing remove <bundle-id> --territories FRA,DEU

# Changement de prix temporaire (promotion) et suppression d'un changement prévu
ascelerate apps pricing sale <bundle-id> --territories all --price 0.49 --start-date 2026-12-20 --end-date 2026-12-27
ascelerate apps pricing cancel <bundle-id> --territory USA --start-date 2026-12-01

# Copier un calendrier de prix vers une autre application (format de iap pricing export)
ascelerate apps pricing export <bundle-id> --output prices.json
ascelerate apps pricing import <other-bundle-id> --file prices.json
```

Apple calcule les prix des autres territoires à partir du prix de base et peut les ajuster selon les taxes et les taux de change ; un prix fixé manuellement reste tel quel. Pour plusieurs territoires, `sale` prend le prix dans la devise du territoire de base et applique ailleurs les prix comparables d'Apple ; ensuite, le prix précédent s'applique de nouveau dans chaque territoire. `import` remplace l'ensemble du calendrier de prix.

## Déclarations de chiffrement

```bash
# Voir les déclarations de chiffrement existantes
ascelerate apps encryption <bundle-id>

# Créer une nouvelle déclaration de chiffrement
ascelerate apps encryption <bundle-id> --create --description "Uses HTTPS for API communication"
ascelerate apps encryption <bundle-id> --create --description "Uses AES encryption" --proprietary-crypto --third-party-crypto
```

## EULA

```bash
# Voir l'EULA actuel (ou voir que l'EULA standard d'Apple s'applique)
ascelerate apps eula <bundle-id>

# Définir un EULA personnalisé à partir d'un fichier texte
ascelerate apps eula <bundle-id> --file eula.txt

# Supprimer l'EULA personnalisé (revient à l'EULA standard d'Apple)
ascelerate apps eula <bundle-id> --delete
```

## Période de grâce d'abonnement

La période de grâce permet aux abonnés de conserver l'accès pendant une courte fenêtre après un échec de paiement de renouvellement, pendant qu'Apple retente la facturation. Le paramètre s'applique à toute l'application.

```bash
# Voir la configuration actuelle
ascelerate apps subscription-grace-period <bundle-id>

# Activer pour la production avec une fenêtre de 16 jours, s'applique à tous les renouvellements
ascelerate apps subscription-grace-period <bundle-id> \
  --opt-in true --duration SIXTEEN_DAYS --renewal-type ALL_RENEWALS

# Tests sandbox uniquement (la production reste désactivée)
ascelerate apps subscription-grace-period <bundle-id> \
  --sandbox-opt-in true --duration THREE_DAYS --renewal-type ALL_RENEWALS
```

Valeurs valides pour `--duration` : `THREE_DAYS`, `SIXTEEN_DAYS`, `TWENTY_EIGHT_DAYS`. Valeurs valides pour `--renewal-type` : `ALL_RENEWALS`, `PAID_TO_PAID_ONLY`.

La production ne peut pas être activée sans la sandbox : `--opt-in` active aussi la sandbox, avec 16 jours pour tous les renouvellements sauf indication contraire. Désactiver les deux efface la durée et le type de renouvellement.

## Achat simplifié (Streamlined Purchasing)

L'achat simplifié permet aux clients d'acheter les abonnements de l'application en dehors de celle-ci, par exemple sur sa page produit de l'App Store. Il est activé par défaut et s'applique à tous les abonnements de l'application. Apple ne le laisse désactiver que si la dernière build approuvée de l'application utilise l'API StoreKit `PurchaseIntent` ; les clients s'abonnent alors depuis l'application.

```bash
# Afficher
ascelerate apps streamlined-purchasing <bundle-id>

# Désactiver
ascelerate apps streamlined-purchasing <bundle-id> --enabled false
```
