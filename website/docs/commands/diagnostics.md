---
sidebar_position: 16
title: Diagnostics
---

# Diagnostics

What Xcode's Organizer shows, from users' devices that share analytics with developers: a build's top hangs, slow launches and disk writes with their call stacks, and the app's performance and power metrics across versions. Without `--build`, the build of the version on the App Store.

## Signatures

```bash
ascelerate diagnostics <bundle-id>
ascelerate diagnostics <bundle-id> --type hangs --build 2041
```

The build's hang, launch and disk-write signatures, heaviest first within each type, with their weight and trend against earlier versions. `--type` takes `hangs`, `launches` or `disk-writes` (comma-separated for several).

## Logs

```bash
ascelerate diagnostics logs <signature-id>
ascelerate diagnostics logs <signature-id> --frames 0
```

Each sampled event with its device, OS and app version, then its call stacks; the frame App Store Connect blames is marked with ▶. `--frames` limits the frames per call stack (40 by default, 0 for all).

## Metrics

```bash
ascelerate diagnostics metrics <bundle-id>
ascelerate diagnostics metrics <bundle-id> --type launch,hang --all
```

Each metric (launch time, hang rate, peak memory, disk writes, battery, terminations, animation, storage) per app version, for all devices at the typical (50th) and 90th percentiles; `--all` adds each device model. Apple's regressions and upward trends come first. `--build` shows one build's metrics.

All three take `--json`.
