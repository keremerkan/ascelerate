---
sidebar_position: 9
title: Zertifikate
---

# Zertifikate

Alle Zertifikatsbefehle unterstützen den interaktiven Modus — Argumente sind optional.

## Auflisten

```bash
asc certs list
asc certs list --type DISTRIBUTION
```

## Details

```bash
# Interaktive Auswahl
asc certs info

# Nach Seriennummer oder Anzeigename
asc certs info "Apple Distribution: Example Inc"
```

## Erstellen

```bash
# Interaktive Typauswahl, generiert automatisch RSA-Schlüsselpaar und CSR
asc certs create

# Typ angeben
asc certs create --type DISTRIBUTION

# Eigene CSR verwenden
asc certs create --type DEVELOPMENT --csr my-request.pem
```

Wenn kein `--csr` angegeben wird, generiert der Befehl automatisch ein RSA-Schlüsselpaar und eine CSR und importiert alles in den Anmelde-Schlüsselbund.

## Widerrufen

```bash
# Interaktive Auswahl
asc certs revoke

# Nach Seriennummer
asc certs revoke ABC123DEF456
```
