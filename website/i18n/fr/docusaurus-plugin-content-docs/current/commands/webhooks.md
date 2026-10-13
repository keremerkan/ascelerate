---
sidebar_position: 20
title: Webhooks
---

# Webhooks

Faites envoyer par App Store Connect les événements d'une application à votre serveur au moment où ils se produisent : changements d'état d'examen, téléversements de builds, états des builds en test externe TestFlight et retours des testeurs. Les webhooks sont désignés par leur **nom** ou leur identifiant.

## Lister

```bash
ascelerate webhooks <bundle-id>
```

## Créer

```bash
ascelerate webhooks create <bundle-id> --name "Release bot" --url https://example.com/hook \
  --events app-store-version-app-version-state-updated,build-upload-state-updated
```

`--events` accepte une liste séparée par des virgules ou `all`. Parmi les types d'événements :

| Événement | Envoyé lorsque |
|---|---|
| `app-store-version-app-version-state-updated` | L'état d'examen App Review ou de publication d'une version change |
| `build-upload-state-updated` | L'état d'un téléversement de build change |
| `build-beta-detail-external-build-state-updated` | L'état TestFlight externe d'un build change |
| `beta-feedback-crash-submission-created` | Un testeur envoie un retour sur un plantage |
| `beta-feedback-screenshot-submission-created` | Un testeur envoie un retour avec capture d'écran |

`ascelerate webhooks create --help` liste tous les types, y compris les événements liés aux ressources en arrière-plan (Background Assets) et à la distribution alternative.

Apple signe chaque requête avec le secret du webhook. Sans `--secret`, `create` en génère un aléatoirement et ne l'affiche qu'une seule fois : enregistrez-le sur votre serveur, car App Store Connect ne le montre plus jamais. `--disabled` crée le webhook sans l'activer.

## Tester et déboguer

```bash
ascelerate webhooks ping <bundle-id> "Release bot"
ascelerate webhooks deliveries <bundle-id> "Release bot"
ascelerate webhooks deliveries <bundle-id> "Release bot" --state failed
ascelerate webhooks redeliver <delivery-id>
```

`ping` envoie un événement de test. `deliveries` liste les livraisons récentes avec le type d'événement, le statut HTTP renvoyé par votre serveur et l'éventuelle erreur (`--state succeeded|failed|pending`, `--limit`, `--json`). Une fois votre serveur corrigé, `redeliver` renvoie l'événement d'une livraison.

## Mettre à jour et supprimer

```bash
ascelerate webhooks update <bundle-id> "Release bot" --enabled false
ascelerate webhooks update <bundle-id> "Release bot" --events all --url https://example.com/new-hook
ascelerate webhooks delete <bundle-id> "Release bot"
```

`--events` remplace toute la liste ; `--secret` définit un nouveau secret de signature.
