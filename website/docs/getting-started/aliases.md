---
sidebar_position: 3
title: Aliases
---

# Aliases

Instead of typing full bundle IDs every time, you can create short aliases:

```bash
# Add an alias (interactive app picker)
ascelerate alias add myapp

# Now use the alias anywhere you'd use a bundle ID
ascelerate apps info myapp
ascelerate apps versions myapp
ascelerate apps localizations view myapp

# List all aliases
ascelerate alias list

# Remove an alias
ascelerate alias remove myapp
```

Aliases are stored in `~/.ascelerate/aliases.json`. Any argument that doesn't contain a dot is looked up as an alias — real bundle IDs (which always contain dots) work unchanged.

:::tip
Aliases work with all app, IAP, subscription, and build commands. Provisioning commands (`devices`, `certs`, `bundle-ids`, `profiles`) use a different identifier domain and don't resolve aliases.
:::
