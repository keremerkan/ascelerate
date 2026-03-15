---
sidebar_position: 11
title: Provisioning-Profile
---

# Provisioning-Profile

Alle Profilbefehle unterstützen den interaktiven Modus — Argumente sind optional.

## Auflisten

```bash
asc profiles list
asc profiles list --type IOS_APP_STORE --state ACTIVE
```

## Details

```bash
asc profiles info
asc profiles info "My App Store Profile"
```

## Herunterladen

```bash
asc profiles download
asc profiles download "My App Store Profile" --output ./profiles/
```

## Erstellen

```bash
# Vollständig interaktiv
asc profiles create

# Nicht-interaktiv
asc profiles create --name "My Profile" --type IOS_APP_STORE --bundle-id com.example.MyApp --certificates all
```

`--certificates all` verwendet alle Zertifikate der passenden Familie (Distribution, Development oder Developer ID). Sie können auch Seriennummern angeben: `--certificates ABC123,DEF456`.

## Löschen

```bash
asc profiles delete
asc profiles delete "My App Store Profile"
```

## Erneuern

Erneuern Sie Profile, indem Sie sie löschen und mit den neuesten Zertifikaten der passenden Familie neu erstellen:

```bash
# Interaktiv: aus allen Profilen auswählen (zeigt Status)
asc profiles reissue

# Ein bestimmtes Profil nach Name erneuern
asc profiles reissue "My Profile"

# Alle ungültigen Profile erneuern
asc profiles reissue --all-invalid

# Alle Profile unabhängig vom Status erneuern
asc profiles reissue --all

# Alle erneuern, alle aktivierten Geräte für Dev/Ad-hoc verwenden
asc profiles reissue --all --all-devices

# Bestimmte Zertifikate anstelle der automatischen Erkennung verwenden
asc profiles reissue --all --to-certs ABC123,DEF456
```
