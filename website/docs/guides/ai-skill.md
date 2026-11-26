---
sidebar_position: 3
title: AI Coding Skill
---

# AI Coding Skill

ascelerate ships with a skill file that gives AI coding agents (Claude Code, Grok Build, Cursor, Windsurf, GitHub Copilot) full knowledge of all commands, JSON formats, and workflows.

## Install via the binary

```bash
ascelerate install-skill          # install/update for every detected agent
ascelerate install-skill --all    # include all supported agents (e.g. Copilot)
```

Auto-detects Claude Code, Grok Build (which reads the Claude Code skill path natively), Cursor, and Windsurf (and GitHub Copilot with `--all`), installs or updates the skill for each, and checks for outdated skills on each run to prompt you after upgrades. To remove from every agent:

```bash
ascelerate install-skill --uninstall
```

## Install via npx (any AI coding agent)

```bash
npx ascelerate-skill
```

This presents an interactive menu to select your agent and installs the skill to the appropriate directory. Both installers fetch the skill file from GitHub at the release matching their version (`install-skill`: the binary's, `npx`: the package's), so it describes the commands that release has; when that release has none, they take the one on `main` and say so.

To remove:

```bash
npx ascelerate-skill --uninstall
```

## What the skill enables

With the skill installed, your AI coding agent can:

- Run any ascelerate command on your behalf
- Build workflow files for your release process
- Manage localizations across multiple languages
- Handle the full archive → upload → submit pipeline
- Work with provisioning profiles, certificates, and devices
