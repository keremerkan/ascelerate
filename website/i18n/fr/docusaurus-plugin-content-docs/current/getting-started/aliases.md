---
sidebar_position: 3
title: Alias
---

# Alias

Au lieu de saisir des bundle IDs complets à chaque fois, vous pouvez créer des alias courts :

```bash
# Ajouter un alias (sélecteur d'application interactif)
ascelerate alias add myapp

# Utilisez ensuite l'alias partout où vous utiliseriez un bundle ID
ascelerate apps info myapp
ascelerate apps versions myapp
ascelerate apps localizations view myapp

# Lister tous les alias
ascelerate alias list

# Supprimer un alias
ascelerate alias remove myapp
```

Les alias sont stockés dans `~/.ascelerate/aliases.json`. Tout argument ne contenant pas de point est recherché comme alias -- les vrais bundle IDs (qui contiennent toujours des points) fonctionnent sans modification.

:::tip
Les alias fonctionnent avec toutes les commandes d'applications, d'achats intégrés, d'abonnements et de builds. Les commandes de provisionnement (`devices`, `certs`, `bundle-ids`, `profiles`) utilisent un domaine d'identifiants différent et ne résolvent pas les alias.
:::
