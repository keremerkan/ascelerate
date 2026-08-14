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
Pour les applications en achat universel (une seule fiche App Store couvrant iOS, macOS, tvOS et/ou visionOS), la même chaîne de version peut exister une fois par plateforme. `create-version` et `review submit` ciblent iOS par défaut -- passez `--platform macos` (ou `tvos`, `visionos`) pour viser une autre plateforme. Toutes les autres commandes liées à une version (localisations, médias, association de build, vérifications préalables, informations et pièces jointes d'examen, `resolve-issues`/`cancel-submission`, déploiement progressif) acceptent elles aussi une option `--platform` facultative ; sans elle, elles demandent de choisir dès qu'une version (ou une soumission d'examen active) correspond à plusieurs plateformes -- avec `--yes`, elles refusent en affichant une indication au lieu de demander.
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

### Soumettre pour examen

```bash
ascelerate apps review submit <bundle-id>
ascelerate apps review submit <bundle-id> --version 2.1.0
ascelerate apps review submit <bundle-id> --platform macos
```

Lors de la soumission, la commande détecte automatiquement les achats intégrés et les abonnements avec des modifications en attente et propose de les soumettre en même temps que la version de l'application.

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

La commande vérifie l'état de la version, l'association du build, puis parcourt chaque langue pour vérifier les champs de localisation (description, nouveautés, mots-clés, URL d'assistance), les champs d'informations de l'application (nom, sous-titre, URL de politique de confidentialité) et les captures d'écran :

```
Preflight checks for MyApp v2.1.0 (Prepare for Submission)

Check                                Status
──────────────────────────────────────────────────────────────────
Version state                        ✓ Prepare for Submission
Build attached                       ✓ Build 42

en-US (English (United States))
  App info                           ✓ All fields filled
  Localizations                      ✓ All fields filled
  Screenshots                        ✓ 2 sets, 10 screenshots

de-DE (German (Germany))
  App info                           ✗ Missing: Privacy Policy URL
  Localizations                      ✗ Missing: What's New
  Screenshots                        ✗ No screenshots
──────────────────────────────────────────────────────────────────
Result: 5 passed, 3 failed
```

La vérification des nouveautés est ignorée lorsque l'application n'a pas encore de version publiée — ce champ n'existe que pour les mises à jour, pas pour une première version.

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

# Activer aussi pour les tests sandbox
ascelerate apps subscription-grace-period <bundle-id> --sandbox-opt-in true
```

Valeurs valides pour `--duration` : `THREE_DAYS`, `SIXTEEN_DAYS`, `TWENTY_EIGHT_DAYS`. Valeurs valides pour `--renewal-type` : `ALL_RENEWALS`, `PAID_TO_PAID_ONLY`.
