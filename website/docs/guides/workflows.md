---
sidebar_position: 1
title: Workflows
---

# Workflows

Chain multiple commands into a single automated run with a workflow file:

```bash
ascelerate run-workflow release.txt
ascelerate run-workflow release.txt --yes   # skip all prompts (CI/CD)
ascelerate run-workflow                     # interactively select from .workflow/.txt files
```

A workflow file is a plain text file with one command per line (without the `ascelerate` prefix). Lines starting with `#` are comments, blank lines are ignored. Both `.workflow` and `.txt` extensions are supported.

## Example

`release.txt` for submitting version 2.1.0 of a sample app:

```
# Release workflow for MyApp v2.1.0

# Create the new version on App Store Connect
apps create-version com.example.MyApp 2.1.0

# Build, validate, and upload
builds archive --scheme MyApp
builds validate --latest --bundle-id com.example.MyApp
builds upload --latest --bundle-id com.example.MyApp

# Wait for the build to finish processing
builds await-processing com.example.MyApp

# Update localizations and attach the build
apps localizations import com.example.MyApp --file localizations.json
apps build attach-latest com.example.MyApp

# Submit for review
apps review submit com.example.MyApp
```

## Confirmation behavior

Without `--yes`, the workflow asks for confirmation before starting, and individual commands still prompt where they normally would (e.g., before submitting for review). With `--yes`, all prompts are skipped for fully unattended execution.

## Nesting

Workflows can call other workflows (`run-workflow` inside a workflow file). Circular references are detected and prevented.

## Build pipeline integration

`builds upload` sets an internal variable so that subsequent `await-processing` and `build attach-latest` automatically target the just-uploaded build, avoiding race conditions with API propagation delay.
