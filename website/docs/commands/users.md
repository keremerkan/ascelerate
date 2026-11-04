---
sidebar_position: 22
title: Users
---

# Users

The team's people and pending invitations: their roles, the apps they see, and whether they may use Certificates, Identifiers & Profiles. People are named by their **email** or ID, apps by bundle ID or alias. Changing roles or removing someone needs an Admin key.

## List

```bash
ascelerate users
ascelerate users info someone@example.com
ascelerate users invitations
```

`users` lists everyone with their roles, how many apps they see and their access to Certificates, Identifiers & Profiles; `info` shows one person with their apps. `invitations` lists the invitations not accepted yet, with their expiry. All three take `--json`.

## Change

```bash
ascelerate users update someone@example.com --roles developer,marketing
ascelerate users update someone@example.com --apps com.example.app,myalias
ascelerate users update someone@example.com --all-apps --provisioning true
ascelerate users remove someone@example.com
```

`--roles` replaces their roles (`admin`, `finance`, `sales`, `marketing`, `app-manager`, `developer`, `access-to-reports`, `customer-support`, `create-apps`, …). `--apps` replaces the apps they see; `--all-apps` gives them every app. Each command lists what would change and asks first. `remove` takes them off the team at once.

## Invite

```bash
ascelerate users invite --email someone@example.com --first-name Ada --last-name Lovelace --roles developer --apps com.example.app
ascelerate users cancel-invitation someone@example.com
```

App Store Connect emails the invitation as soon as it's created. Without `--apps` they see every app; `--provisioning` gives access to Certificates, Identifiers & Profiles.
