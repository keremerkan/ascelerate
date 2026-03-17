---
sidebar_position: 3
title: AI Coding Skill
---

# AI Coding Skill

ascelerate ships with a skill file that gives AI coding agents (Claude Code, Cursor, Windsurf, GitHub Copilot) full knowledge of all commands, JSON formats, and workflows.

## Install via the binary (Claude Code only)

```bash
ascelerate install-skill
```

The tool checks for outdated skills on each run and prompts you to update after upgrades. To remove:

```bash
ascelerate install-skill --uninstall
```

## Install via npx (any AI coding agent)

```bash
npx ascelerate-skill
```

This presents an interactive menu to select your agent and installs the skill to the appropriate directory. The skill file is fetched from GitHub, so it's always up to date.

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
