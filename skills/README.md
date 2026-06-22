# ascelerate-skill

The AI coding skill for [**ascelerate**](https://github.com/keremerkan/ascelerate) — a Swift command-line tool for the App Store Connect API.

It teaches your AI coding agent how to drive the `ascelerate` CLI: app submissions, localizations, screenshots, builds, provisioning, in-app purchases, subscriptions, customer reviews, in-app events, custom product pages, and release workflows.

## Install

```bash
npx ascelerate-skill
```

You'll get an interactive picker for whichever agents are installed on your machine:

- **Claude Code** → `~/.claude/skills/ascelerate/SKILL.md`
- **Cursor** → `~/.cursor/rules/ascelerate.md`
- **Windsurf** → `~/.windsurf/rules/ascelerate.md`
- **GitHub Copilot** → `~/.github/instructions/ascelerate.md`

The installer fetches the latest skill file from GitHub each time, so you always get the current version.

## Uninstall

```bash
npx ascelerate-skill --uninstall
```

## Claude Code shortcut

If you use **Claude Code** and have the `ascelerate` binary installed, you can install or update the skill directly — no `npx` needed:

```bash
ascelerate install-skill
```

This installs to `~/.claude/skills/` only. For **Cursor, Windsurf, and GitHub Copilot**, use `npx ascelerate-skill` (above) — that's the only way to install the skill for those agents.

## Links

- **ascelerate** CLI: https://github.com/keremerkan/ascelerate
- **Documentation**: https://ascelerate.dev

MIT © Kerem Erkan
