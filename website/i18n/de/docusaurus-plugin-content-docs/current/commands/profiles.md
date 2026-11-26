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

Ohne `--to-certs` erhält jedes Profil alle Zertifikate, die zu seinem Typ passen, nicht nur die bisherigen. `--to-certs` nennt genaue Zertifikate über Seriennummer oder Namen (ein Name muss genau ein Zertifikat bezeichnen), und jedes Profil muss sie aufnehmen können. Entwicklungs- und Ad-hoc-Profile behalten ihre eigenen aktivierten Geräte oder erhalten mit `--all-devices` alle aktivierten Geräte, soweit sie zur Plattform des Profils passen. All das wird geprüft, bevor ein Profil gelöscht wird.

Abgelaufene Zertifikate kommen nie in ein neu ausgestelltes Profil, mit oder ohne `--to-certs`.

## Weitere Optionen

Optionen, die die Beispiele oben nicht zeigen:

- `profiles create` `--devices`: Gerätenamen oder UDIDs, durch Kommas getrennt, oder all (Entwicklungs- und Ad-hoc-Profile)
