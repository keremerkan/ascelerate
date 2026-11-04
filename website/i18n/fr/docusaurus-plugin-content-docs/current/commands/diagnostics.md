---
sidebar_position: 16
title: Diagnostics
---

# Diagnostics

Ce qu’affiche l’Organizer d’Xcode, à partir des appareils des utilisateurs qui partagent leurs analyses avec les développeurs : les principaux blocages, lancements lents et écritures disque d’un build avec leurs piles d’appels, et les métriques de performances et d’énergie de l’app au fil des versions. Sans `--build`, le build de la version sur l’App Store.

## Signatures

```bash
ascelerate diagnostics <bundle-id>
ascelerate diagnostics <bundle-id> --type hangs --build 2041
```

Les signatures de blocages, de lancements et d’écritures disque du build, par poids pour chaque type, avec leur tendance par rapport aux versions précédentes. `--type` accepte `hangs`, `launches` ou `disk-writes` (séparés par des virgules pour plusieurs).

## Journaux

```bash
ascelerate diagnostics logs <signature-id>
ascelerate diagnostics logs <signature-id> --frames 0
```

Chaque événement échantillonné avec son appareil, son OS et la version de l’app, puis ses piles d’appels ; la frame mise en cause par App Store Connect est marquée par ▶. `--frames` limite les frames par pile d’appels (40 par défaut, 0 pour toutes).

## Métriques

```bash
ascelerate diagnostics metrics <bundle-id>
ascelerate diagnostics metrics <bundle-id> --type launch,hang --all
```

Chaque métrique (temps de lancement, taux de blocage, mémoire maximale, écritures disque, batterie, arrêts, animation, stockage) par version de l’app, pour tous les appareils au percentile typique (50e) et au 90e ; `--all` ajoute chaque modèle d’appareil. Les régressions et tendances à la hausse signalées par Apple viennent en premier. `--build` montre les métriques d’un build.

Les trois acceptent `--json`.
