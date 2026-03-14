---
sidebar_position: 9
title: Certificates
---

# Certificates

All certificate commands support interactive mode — arguments are optional.

## List

```bash
asc certs list
asc certs list --type DISTRIBUTION
```

## Details

```bash
# Interactive picker
asc certs info

# By serial number or display name
asc certs info "Apple Distribution: Example Inc"
```

## Create

```bash
# Interactive type picker, auto-generates RSA key pair and CSR
asc certs create

# Specify type
asc certs create --type DISTRIBUTION

# Use your own CSR
asc certs create --type DEVELOPMENT --csr my-request.pem
```

When no `--csr` is provided, the command auto-generates an RSA key pair and CSR, then imports everything into the login keychain.

## Revoke

```bash
# Interactive picker
asc certs revoke

# By serial number
asc certs revoke ABC123DEF456
```
