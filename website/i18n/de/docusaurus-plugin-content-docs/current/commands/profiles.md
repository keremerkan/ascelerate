---
sidebar_position: 11
title: Provisioning-Profile
---

# Provisioning-Profile

Alle Profilbefehle unterstützen den interaktiven Modus — Argumente sind optional.

## Auflisten

```bash
ascelerate profiles list
ascelerate profiles list --type IOS_APP_STORE --state ACTIVE
```

## Details

```bash
ascelerate profiles info
ascelerate profiles info "My App Store Profile"
```

## Herunterladen

```bash
ascelerate profiles download
ascelerate profiles download "My App Store Profile" --output ./profiles/
```

## Erstellen

```bash
# Vollständig interaktiv
ascelerate profiles create

# Nicht-interaktiv
ascelerate profiles create --name "My Profile" --type IOS_APP_STORE --bundle-id com.example.MyApp --certificates all
```

`--certificates all` verwendet alle Zertifikate der passenden Familie (Distribution, Development oder Developer ID). Sie können auch Seriennummern angeben: `--certificates ABC123,DEF456`.

## Löschen

```bash
ascelerate profiles delete
ascelerate profiles delete "My App Store Profile"
```

## Erneuern

Erneuern Sie Profile, indem Sie sie löschen und mit den neuesten Zertifikaten der passenden Familie neu erstellen:

```bash
# Interaktiv: aus allen Profilen auswählen (zeigt Status)
ascelerate profiles reissue

# Ein bestimmtes Profil nach Name erneuern
ascelerate profiles reissue "My Profile"

# Alle ungültigen Profile erneuern
ascelerate profiles reissue --all-invalid

# Alle Profile unabhängig vom Status erneuern
ascelerate profiles reissue --all

# Alle erneuern, alle aktivierten Geräte für Dev/Ad-hoc verwenden
ascelerate profiles reissue --all --all-devices

# Bestimmte Zertifikate anstelle der automatischen Erkennung verwenden
ascelerate profiles reissue --all --to-certs ABC123,DEF456
```
