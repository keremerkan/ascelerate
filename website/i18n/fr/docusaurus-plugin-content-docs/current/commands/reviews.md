---
sidebar_position: 13
title: Avis clients
---

# Avis clients

Consultez les avis clients et gérez les réponses du développeur. Les avis eux-mêmes sont en lecture seule — vous pouvez uniquement publier, remplacer ou supprimer la **réponse du développeur**.

## Lister

```bash
ascelerate reviews list <bundle-id>
ascelerate reviews list <bundle-id> --rating 1 --sort critical --unanswered --limit 20
ascelerate reviews list <bundle-id> --territory USA
```

Le tableau affiche l'identifiant de l'avis, la note en étoiles, la date, le territoire, la présence d'une réponse et le titre.

- `--rating` — filtrer par note en étoiles (1–5).
- `--territory` — filtrer par territoire de l'avis (par ex. `USA`).
- `--sort` — `recent` (par défaut), `oldest`, `critical` (note la plus basse en premier) ou `best` (la plus haute en premier).
- `--unanswered` — uniquement les avis sans réponse publiée.
- `--limit` — nombre maximal d'avis à afficher (50 par défaut, 200 au maximum).

## Détails

```bash
ascelerate reviews info <review-id>
```

Affiche le texte complet de l'avis et la réponse du développeur, le cas échéant. Les identifiants d'avis proviennent de `reviews list`.

## Répondre

```bash
ascelerate reviews respond <review-id> --body "Merci pour votre retour ! Nous avons corrigé cela dans la dernière mise à jour."
```

Publie une réponse du développeur. Si l'avis a déjà une réponse, elle est remplacée après confirmation.

## Supprimer une réponse

```bash
ascelerate reviews delete-response <review-id>
```
