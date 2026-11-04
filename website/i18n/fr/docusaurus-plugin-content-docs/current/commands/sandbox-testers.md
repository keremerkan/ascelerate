---
sidebar_position: 7
title: Testeurs sandbox
---

# Testeurs sandbox

Les comptes Apple qui achètent des achats intégrés et des abonnements dans le sandbox. Un testeur est désigné par son **compte Apple** (adresse e-mail) ou son identifiant. La création et la suppression de testeurs se font dans App Store Connect (Utilisateurs et accès > Sandbox) ; l’API ne le permet pas.

## Lister

```bash
ascelerate sandbox-testers
ascelerate sandbox-testers --json
```

Pour chaque testeur : compte Apple, nom, storefront, vitesse de renouvellement de ses abonnements, interruption de ses achats et compatibilité avec Apple Pay.

## Modifier

```bash
ascelerate sandbox-testers update tester@example.com --renewal-rate 3m
ascelerate sandbox-testers update tester@example.com --territory DEU --interrupt-purchases true
```

`--territory` définit le storefront (un code de territoire à trois lettres). `--interrupt-purchases` interrompt les achats pour une étape supplémentaire, comme accepter des conditions ou mettre à jour le paiement. `--renewal-rate` définit la vitesse de renouvellement d’un abonnement mensuel pour le testeur : `1h`, `30m`, `15m`, `5m` ou `3m` (les autres durées en proportion). La commande liste les modifications et demande confirmation.

## Effacer l’historique d’achats

```bash
ascelerate sandbox-testers clear-history tester@example.com other@example.com
ascelerate sandbox-testers clear-history --all
```

Oublie les achats intégrés et les abonnements des testeurs, pour qu’ils puissent être achetés de nouveau depuis le début. La commande demande confirmation.
