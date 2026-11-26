---
sidebar_position: 9
title: Certificats
---

# Certificats

Toutes les commandes de certificats prennent en charge le mode interactif -- les arguments sont facultatifs.

## Lister

```bash
ascelerate certs list
ascelerate certs list --type DISTRIBUTION
```

## Détails

```bash
# Sélecteur interactif
ascelerate certs info

# Par numéro de série ou nom d'affichage
ascelerate certs info "Apple Distribution: Example Inc"
```

## Créer

```bash
# Sélecteur de type interactif, génère automatiquement une paire de clés RSA et un CSR
ascelerate certs create

# Spécifier le type
ascelerate certs create --type DISTRIBUTION

# Utiliser votre propre CSR
ascelerate certs create --type DEVELOPMENT --csr my-request.pem
```

La clé privée est écrite (lisible par vous seul) et le dossier de sortie vérifié avant que le certificat soit demandé ; si la demande échoue, la clé est retirée. Un certificat créé à partir de `--csr` est enregistré lui aussi, sous `<numéro de série>.cer` sans `--output`. Après l'import dans le trousseau, la commande propose de supprimer les fichiers locaux ; avec `--output` ou `--yes`, ils sont conservés, sauf si vous passez `--delete-local-files`.

Lorsqu'aucun `--csr` n'est fourni, la commande génère automatiquement une paire de clés RSA et un CSR, puis importe le tout dans le trousseau de connexion.

## Révoquer

```bash
# Sélecteur interactif
ascelerate certs revoke

# Par numéro de série
ascelerate certs revoke ABC123DEF456
```

## Autres options

Options que les exemples ci-dessus ne montrent pas :

- `certs list` `--display-name` : seulement les certificats portant ce nom affiché
