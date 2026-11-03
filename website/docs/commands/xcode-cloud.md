---
sidebar_position: 21
title: Xcode Cloud
---

# Xcode Cloud

Follow and start Xcode Cloud builds: your products, their workflows, each build run with its actions, issues, test results and artifacts.

A **product** is made in Xcode the first time you connect a repository (**Integrate > Create Workflow**); the API can't make one. After that, everything here works from the command line. A product is referenced by its app's **bundle ID** (or alias), its name or its ID; a workflow by its **name** or ID; a build run by its **number** or ID.

## Products

```bash
ascelerate xcode-cloud products
```

Lists the team's products (apps and frameworks) with their bundle ID and repository.

## Workflows

```bash
ascelerate xcode-cloud workflows <bundle-id>
ascelerate xcode-cloud workflows info <bundle-id> "Release"
ascelerate xcode-cloud workflows update <bundle-id> "Default" --manual-only
ascelerate xcode-cloud workflows disable <bundle-id> "Nightly"
ascelerate xcode-cloud workflows enable <bundle-id> "Nightly"
ascelerate xcode-cloud workflows delete <bundle-id> "Old workflow"
```

`info` shows a workflow's start conditions (branch and tag changes, pull requests, schedules, and what may be started by hand), its actions (build, test, analyze, archive with scheme, platform and distribution), and the repository, project, Xcode and macOS versions it uses. `update --manual-only` stops a workflow from starting on its own (branch and tag changes, pull requests, a schedule) and keeps what may be started by hand. A workflow that's turned off starts no builds. Deleting a workflow keeps its build runs.

## Build runs

```bash
ascelerate xcode-cloud runs <bundle-id>                         # newest first
ascelerate xcode-cloud runs <bundle-id> --workflow "Release" --limit 50
ascelerate xcode-cloud runs info <bundle-id> 42                 # details and actions
ascelerate xcode-cloud runs issues <bundle-id> 42 [--errors]
ascelerate xcode-cloud runs tests <bundle-id> 42 [--failed]
ascelerate xcode-cloud runs artifacts <bundle-id> 42
ascelerate xcode-cloud runs artifacts <bundle-id> 42 --type LOG_BUNDLE --download ./logs
```

Each run shows its state, the branch, tag or pull request built, the commit, how long it took, and its error, warning and test failure counts. `issues` lists each action's errors and warnings with file and line; `tests` lists test results per destination (device and OS), with the failure message of each failed test. `artifacts` lists logs, archives, result bundles and products; `--download` saves them (`--type` narrows them down).

## Start a build

```bash
ascelerate xcode-cloud start <bundle-id> "Release" --branch main
ascelerate xcode-cloud start <bundle-id> "Release" --tag v2.1
ascelerate xcode-cloud start <bundle-id> "PR checks" --pull-request 128
ascelerate xcode-cloud rerun <bundle-id> 42 [--clean]
```

`start` builds the branch, tag or pull request you name; without one, Xcode Cloud builds what the workflow's start condition allows by hand. `rerun` builds an earlier run's commit again with its workflow. `--clean` builds without the cache. The API can't cancel a build.

## Repositories & Xcode versions

```bash
ascelerate xcode-cloud repositories
ascelerate xcode-cloud xcode-versions
```

`xcode-versions` lists the Xcode versions Xcode Cloud offers, with the macOS versions each runs on.

All list and info commands take `--json`.
