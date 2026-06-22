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

## Already have the CLI?

If you've installed the `ascelerate` binary, you can install or update the skill for your agents directly — no `npx` needed:

```bash
ascelerate install-skill            # install/update for every detected agent
ascelerate install-skill --all      # include all supported agents (e.g. Copilot)
ascelerate install-skill --uninstall
```

It auto-detects **Claude Code**, **Cursor**, and **Windsurf**, installs/updates the skill for each (and **GitHub Copilot** with `--all`), and stamps each install with the version so the CLI can tell you when the skill is out of date.

## Links

- **ascelerate** CLI: https://github.com/keremerkan/ascelerate
- **Documentation**: https://ascelerate.dev

MIT © Kerem Erkan
