---
sidebar_position: 1
title: Installation
---

# Installation

## Requirements

- macOS 13+
- Swift 6.0+ (only for building from source)

## Homebrew

```bash
brew tap keremerkan/tap
brew install asc-cli
```

The tap provides a pre-built binary for Apple Silicon Macs, so installation is instant.

## Install script

```bash
curl -sSL https://raw.githubusercontent.com/keremerkan/asc-cli/main/install.sh | bash
```

Downloads the latest release, installs to `/usr/local/bin`, and removes the quarantine attribute automatically. Apple Silicon only.

## Download manually

Download the latest release from [GitHub Releases](https://github.com/keremerkan/asc-cli/releases):

```bash
curl -L https://github.com/keremerkan/asc-cli/releases/latest/download/asc-macos-arm64.tar.gz -o asc.tar.gz
tar xzf asc.tar.gz
mv asc /usr/local/bin/
```

Since the binary is not signed or notarized, macOS will quarantine it on first download. Remove the quarantine attribute:

```bash
xattr -d com.apple.quarantine /usr/local/bin/asc
```

:::note
Pre-built binaries are provided for Apple Silicon (arm64) only. Intel Mac users should build from source.
:::

## Build from source

```bash
git clone https://github.com/keremerkan/asc-cli.git
cd asc-cli
swift build -c release
strip .build/release/asc
cp .build/release/asc /usr/local/bin/
```

:::note
The release build takes a few minutes because the [asc-swift](https://github.com/aaronsky/asc-swift) dependency includes ~2500 generated source files covering the entire App Store Connect API surface. `strip` removes debug symbols, reducing the binary from ~175 MB to ~59 MB.
:::

## Shell completions

Set up tab completion for subcommands, options, and flags (supports zsh and bash):

```bash
asc install-completions
```

This detects your shell and configures everything automatically. Restart your shell or open a new tab to activate.

## Check your version

```bash
asc version     # Prints version number
asc --version   # Same as above
asc -v          # Same as above
```
