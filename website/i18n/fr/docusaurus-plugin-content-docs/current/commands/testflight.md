---
sidebar_position: 17
title: TestFlight
---

# TestFlight

Gérez les tests bêta TestFlight de bout en bout : groupes bêta, testeurs, distribution des builds, notes What to Test, examen bêta et retours des testeurs.

Les commandes portant sur un build utilisent par défaut le build le plus récent non expiré. Passez `--build <numéro>` pour cibler un build précis, et `--platform` pour lever l'ambiguïté lorsqu'une application en achat universel partage le même numéro de build entre plusieurs plateformes.

## Groupes bêta

```bash
ascelerate testflight groups list <bundle-id>
ascelerate testflight groups info <bundle-id> "External Testers"
ascelerate testflight groups create <bundle-id> --name "Friends" --public-link --public-link-limit 100
ascelerate testflight groups update <bundle-id> "Friends" --public-link false
ascelerate testflight groups delete <bundle-id> "Friends"
```

`groups list` affiche pour chaque groupe son type, son lien public, sa limite de testeurs et son réglage de retours. `groups info` y ajoute les testeurs du groupe et les builds qui lui sont associés. `create` accepte `--internal` pour un groupe interne (membres de l'équipe) et `--all-builds` pour lui donner un accès automatique à tous les builds ; les groupes externes peuvent activer un lien d'invitation public avec une limite de testeurs facultative.

Les noms de groupes sont comparés sans tenir compte de la casse. Omettez le nom pour choisir dans une liste interactive.

### Associer des builds

```bash
# Par défaut, le build le plus récent non expiré est utilisé
ascelerate testflight groups add-build <bundle-id> "Friends"
ascelerate testflight groups add-build <bundle-id> "Friends" --build 123
ascelerate testflight groups remove-build <bundle-id> "Friends" --build 123
```

### Critères de recrutement

Les groupes disposant d'un lien public peuvent restreindre l'accès selon la famille d'appareils et la version du système :

```bash
# Afficher les critères actuels, ainsi que les options appareil/OS acceptées par Apple
ascelerate testflight groups criteria view <bundle-id> "Friends" --options

# Remplacer les critères : FAMILY[:MIN[:MAX]] avec bornes incluses
ascelerate testflight groups criteria set <bundle-id> "Friends" --filter IPHONE:18.0 --filter IPAD:17.0:26

# Supprimer tous les critères
ascelerate testflight groups criteria clear <bundle-id> "Friends"
```

Familles d'appareils valides : `IPHONE`, `IPAD`, `MAC`, `APPLE_TV`, `APPLE_WATCH`, `VISION`.

## Testeurs

```bash
ascelerate testflight testers list <bundle-id>
ascelerate testflight testers list <bundle-id> --group "Friends"

# L'ajout envoie l'invitation TestFlight pour les groupes externes
ascelerate testflight testers add <bundle-id> --email tester@example.com --first-name Jane --group "Friends"

# Retirer d'un groupe, ou de toute l'application
ascelerate testflight testers remove <bundle-id> tester@example.com --group "Friends"
ascelerate testflight testers remove <bundle-id> tester@example.com

# Renvoyer l'e-mail d'invitation
ascelerate testflight testers invite <bundle-id> tester@example.com
```

Avec `add` et `import`, l'option `--group` accepte plusieurs noms de groupes séparés par des virgules.

### Importation groupée

```bash
ascelerate testflight testers import <bundle-id> --file testers.csv --group "Friends"
```

Le fichier contient un testeur par ligne : `email[,prénom[,nom]]`. Les lignes vides, les lignes commençant par `#` et une ligne d'en-tête initiale sont ignorées ; le format CSV exporté par l'interface web d'App Store Connect fonctionne tel quel. Les lignes en échec sont signalées à la fin, sans interrompre le reste de l'importation.

## Builds et distribution

```bash
# Tous les builds avec leurs états TestFlight
ascelerate testflight builds <bundle-id>
ascelerate testflight builds <bundle-id> --platform ios --limit 50

# Versions préliminaires
ascelerate testflight versions <bundle-id>

# État complet d'un build
ascelerate testflight status <bundle-id> --build 123
```

`builds` liste pour chaque build son état de traitement, ses états de test interne et externe et sa date d'expiration. `status` y ajoute, pour un seul build, le réglage de notification automatique et l'état de l'examen bêta. Ces deux commandes acceptent `--json` pour une sortie lisible par machine ([conventions](../guides/automation.md#json-output)).

```bash
# Faire expirer un build pour que les testeurs ne puissent plus l'installer
ascelerate testflight expire <bundle-id> --build 123

# Notifier les testeurs qu'un build est disponible
ascelerate testflight notify <bundle-id>

# Activer ou désactiver la notification automatique pour un build
ascelerate testflight auto-notify <bundle-id> --enabled false
```

## What to Test

Les notes de test sont enregistrées par build et par langue :

```bash
ascelerate testflight whats-new view <bundle-id>

# Une seule langue, ou toutes les langues existantes si --locale est omis
ascelerate testflight whats-new set <bundle-id> --text "Essayez les nouveaux filtres de carte" --locale fr-FR
ascelerate testflight whats-new set <bundle-id> --text "Essayez les nouveaux filtres de carte"

# Export et import via JSON
ascelerate testflight whats-new export <bundle-id> --output notes.json
ascelerate testflight whats-new import <bundle-id> --file notes.json
```

Le format JSON suit celui des autres commandes de localisation :

```json
{
  "en-US": { "whatsNew": "Try the new map filters" },
  "fr-FR": { "whatsNew": "Essayez les nouveaux filtres de carte" }
}
```

## Examen bêta

Les tests externes exigent un examen bêta pour chaque build :

```bash
ascelerate testflight submit <bundle-id> --build 123
ascelerate testflight status <bundle-id> --build 123
```

Les informations de l'application bêta et les détails d'examen s'appliquent au niveau de l'application :

```bash
# Description de l'application bêta et e-mail de retours, par langue
ascelerate testflight app-info view <bundle-id>
ascelerate testflight app-info update <bundle-id> --locale fr-FR --feedback-email moi@example.com
ascelerate testflight app-info export <bundle-id> --output beta-app-info.json
ascelerate testflight app-info import <bundle-id> --file beta-app-info.json

# Contact et compte de démonstration pour l'équipe d'examen bêta
ascelerate testflight review-info <bundle-id>
ascelerate testflight review-info <bundle-id> --demo-account-name demo@example.com --demo-account-required true

# Contrat de licence bêta personnalisé (--text "" rétablit le contrat standard d'Apple)
ascelerate testflight eula <bundle-id>
ascelerate testflight eula <bundle-id> --file eula.txt
```

## Retours des testeurs

Les retours de plantage et de capture d'écran envoyés par les testeurs via TestFlight :

```bash
ascelerate testflight feedback crashes list <bundle-id>
ascelerate testflight feedback crashes info <submission-id>
ascelerate testflight feedback crashes log <submission-id> --output crash.log
ascelerate testflight feedback crashes delete <submission-id>

ascelerate testflight feedback screenshots list <bundle-id>
ascelerate testflight feedback screenshots info <submission-id>
ascelerate testflight feedback screenshots download <bundle-id> [submission-id] --output feedback.zip
ascelerate testflight feedback screenshots delete <submission-id>
```

`list` accepte les filtres `--build` et `--platform`. `info` affiche le contexte complet de l'appareil : modèle, version du système, langue, type de connexion, niveau de batterie, espace disque libre et commentaire du testeur. `log` affiche le journal de plantage ou l'enregistre avec `--output`. `download` regroupe les captures d'écran et le commentaire d'un envoi dans une archive zip ; si l'identifiant d'envoi est omis, une liste paginée des envois de l'application vous permet d'en choisir un. Les URL des captures expirent au bout de quelques jours : téléchargez les retours que vous souhaitez conserver.
