---
sidebar_position: 9
title: Zertifikate
---

# Zertifikate

Alle Zertifikatsbefehle unterstützen den interaktiven Modus — Argumente sind optional.

## Auflisten

```bash
ascelerate certs list
ascelerate certs list --type DISTRIBUTION
```

## Details

```bash
# Interaktive Auswahl
ascelerate certs info

# Nach Seriennummer oder Anzeigename
ascelerate certs info "Apple Distribution: Example Inc"
```

## Erstellen

```bash
# Interaktive Typauswahl, generiert automatisch RSA-Schlüsselpaar und CSR
ascelerate certs create

# Typ angeben
ascelerate certs create --type DISTRIBUTION

# Eigene CSR verwenden
ascelerate certs create --type DEVELOPMENT --csr my-request.pem
```

Wenn kein `--csr` angegeben wird, generiert der Befehl automatisch ein RSA-Schlüsselpaar und eine CSR und importiert alles in den Anmelde-Schlüsselbund.

## Widerrufen

```bash
# Interaktive Auswahl
ascelerate certs revoke

# Nach Seriennummer
ascelerate certs revoke ABC123DEF456
```
