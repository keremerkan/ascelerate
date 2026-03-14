---
sidebar_position: 3
title: Aliases
---

# Aliases

Instead of typing full bundle IDs every time, you can create short aliases:

```bash
# Add an alias (interactive app picker)
asc alias add myapp

# Now use the alias anywhere you'd use a bundle ID
asc apps info myapp
asc apps versions myapp
asc apps localizations view myapp

# List all aliases
asc alias list

# Remove an alias
asc alias remove myapp
```

Aliases are stored in `~/.asc/aliases.json`. Any argument that doesn't contain a dot is looked up as an alias — real bundle IDs (which always contain dots) work unchanged.

:::tip
Aliases work with all app, IAP, subscription, and build commands. Provisioning commands (`devices`, `certs`, `bundle-ids`, `profiles`) use a different identifier domain and don't resolve aliases.
:::
