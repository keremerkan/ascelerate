---
sidebar_position: 1
title: Applications
---

# Applications

## Lister les applications

```bash
asc apps list
```

## Détails d'une application

```bash
asc apps info <bundle-id>
```

## Lister les versions

```bash
asc apps versions <bundle-id>
```

## Créer une version

```bash
asc apps create-version <bundle-id> <version-string>
asc apps create-version <bundle-id> 2.1.0 --platform ios --release-type manual
```

L'option `--release-type` est facultative -- son omission reprend le paramètre de la version précédente.

## Examen

### Vérifier le statut d'examen

```bash
asc apps review status <bundle-id>
asc apps review status <bundle-id> --version 2.1.0
```

### Soumettre pour examen

```bash
asc apps review submit <bundle-id>
asc apps review submit <bundle-id> --version 2.1.0
```

Lors de la soumission, la commande détecte automatiquement les achats intégrés et les abonnements avec des modifications en attente et propose de les soumettre en même temps que la version de l'application.

### Résoudre les éléments rejetés

Après avoir corrigé les problèmes et répondu dans le Centre de résolution :

```bash
asc apps review resolve-issues <bundle-id>
```

### Annuler la soumission

```bash
asc apps review cancel-submission <bundle-id>
```

## Vérifications préalables

Avant de soumettre pour examen, exécutez `preflight` pour vérifier que tous les champs requis sont remplis pour chaque langue :

```bash
# Vérifier la dernière version modifiable
asc apps review preflight <bundle-id>

# Vérifier une version spécifique
asc apps review preflight <bundle-id> --version 2.1.0
```

La commande vérifie l'état de la version, l'association du build, puis parcourt chaque langue pour vérifier les champs de localisation (description, nouveautés, mots-clés), les champs d'informations de l'application (nom, sous-titre, URL de politique de confidentialité) et les captures d'écran :

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

La commande se termine avec un code de sortie non nul lorsqu'une vérification échoue, ce qui la rend adaptée aux pipelines CI et aux fichiers de workflow.

## Déploiement progressif

```bash
# Voir le statut du déploiement progressif
asc apps phased-release <bundle-id>

# Activer le déploiement progressif (démarre inactif, s'active quand la version est publiée)
asc apps phased-release <bundle-id> --enable

# Mettre en pause, reprendre ou terminer un déploiement progressif
asc apps phased-release <bundle-id> --pause
asc apps phased-release <bundle-id> --resume
asc apps phased-release <bundle-id> --complete

# Supprimer entièrement le déploiement progressif
asc apps phased-release <bundle-id> --disable
```

## Disponibilité territoriale

```bash
# Voir dans quels territoires l'application est disponible
asc apps availability <bundle-id>

# Afficher les noms complets des pays
asc apps availability <bundle-id> --verbose

# Rendre des territoires disponibles ou indisponibles
asc apps availability <bundle-id> --add CHN,RUS
asc apps availability <bundle-id> --remove CHN
```

## Déclarations de chiffrement

```bash
# Voir les déclarations de chiffrement existantes
asc apps encryption <bundle-id>

# Créer une nouvelle déclaration de chiffrement
asc apps encryption <bundle-id> --create --description "Uses HTTPS for API communication"
asc apps encryption <bundle-id> --create --description "Uses AES encryption" --proprietary-crypto --third-party-crypto
```

## EULA

```bash
# Voir l'EULA actuel (ou voir que l'EULA standard d'Apple s'applique)
asc apps eula <bundle-id>

# Définir un EULA personnalisé à partir d'un fichier texte
asc apps eula <bundle-id> --file eula.txt

# Supprimer l'EULA personnalisé (revient à l'EULA standard d'Apple)
asc apps eula <bundle-id> --delete
```
