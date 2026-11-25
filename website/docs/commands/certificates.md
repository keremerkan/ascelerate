---
sidebar_position: 9
title: Certificates
---

# Certificates

All certificate commands support interactive mode — arguments are optional.

## List

```bash
ascelerate certs list
ascelerate certs list --type DISTRIBUTION
```

## Details

```bash
# Interactive picker
ascelerate certs info

# By serial number or display name
ascelerate certs info "Apple Distribution: Example Inc"
```

## Create

```bash
# Interactive type picker, auto-generates RSA key pair and CSR
ascelerate certs create

# Specify type
ascelerate certs create --type DISTRIBUTION

# Use your own CSR
ascelerate certs create --type DEVELOPMENT --csr my-request.pem
```

The private key is written (readable by you only) and the output folder checked before the certificate is requested; if the request fails, the key is removed again. A certificate made from `--csr` is saved too, as `<serial>.cer` without `--output`. After the keychain import the command offers to delete the local files; with `--output` or `--yes` they stay, unless you pass `--delete-local-files`.

When no `--csr` is provided, the command auto-generates an RSA key pair and CSR, then imports everything into the login keychain.

## Revoke

```bash
# Interactive picker
ascelerate certs revoke

# By serial number
ascelerate certs revoke ABC123DEF456
```
