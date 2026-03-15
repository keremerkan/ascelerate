---
sidebar_position: 9
title: Certificats
---

# Certificats

Toutes les commandes de certificats prennent en charge le mode interactif -- les arguments sont facultatifs.

## Lister

```bash
asc certs list
asc certs list --type DISTRIBUTION
```

## Détails

```bash
# Sélecteur interactif
asc certs info

# Par numéro de série ou nom d'affichage
asc certs info "Apple Distribution: Example Inc"
```

## Créer

```bash
# Sélecteur de type interactif, génère automatiquement une paire de clés RSA et un CSR
asc certs create

# Spécifier le type
asc certs create --type DISTRIBUTION

# Utiliser votre propre CSR
asc certs create --type DEVELOPMENT --csr my-request.pem
```

Lorsqu'aucun `--csr` n'est fourni, la commande génère automatiquement une paire de clés RSA et un CSR, puis importe le tout dans le trousseau de connexion.

## Révoquer

```bash
# Sélecteur interactif
asc certs revoke

# Par numéro de série
asc certs revoke ABC123DEF456
```
