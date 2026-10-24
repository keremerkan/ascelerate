---
sidebar_position: 3
title: Alias
---

# Alias

En lugar de escribir el Bundle ID completo cada vez, puede crear alias cortos:

```bash
# Añadir un alias (selector interactivo de apps)
ascelerate alias add myapp

# Ahora puede usar el alias en cualquier lugar donde usaría un Bundle ID
ascelerate apps info myapp
ascelerate apps versions myapp
ascelerate apps localizations view myapp

# Listar todos los alias
ascelerate alias list

# Eliminar un alias
ascelerate alias remove myapp
```

Los alias se guardan en `~/.ascelerate/aliases.json`. Cualquier argumento que no contenga un punto se busca como alias; los Bundle ID reales (que siempre contienen puntos) funcionan sin cambios.

:::tip
Los alias funcionan con todos los comandos de apps, compras dentro de la app, suscripciones y compilaciones. Los comandos de suministro (`devices`, `certs`, `bundle-ids`, `profiles`) usan un ámbito de identificadores distinto y no resuelven alias.
:::
