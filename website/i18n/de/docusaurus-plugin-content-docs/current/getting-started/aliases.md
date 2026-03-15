---
sidebar_position: 3
title: Aliase
---

# Aliase

Anstatt jedes Mal vollständige Bundle IDs einzugeben, können Sie kurze Aliase erstellen:

```bash
# Alias hinzufügen (interaktive App-Auswahl)
asc alias add myapp

# Den Alias überall verwenden, wo Sie eine Bundle ID angeben würden
asc apps info myapp
asc apps versions myapp
asc apps localizations view myapp

# Alle Aliase auflisten
asc alias list

# Alias entfernen
asc alias remove myapp
```

Aliase werden in `~/.asc/aliases.json` gespeichert. Jedes Argument ohne Punkt wird als Alias-Name interpretiert — echte Bundle IDs (die immer Punkte enthalten) funktionieren unverändert.

:::tip
Aliase funktionieren mit allen App-, IAP-, Abonnement- und Build-Befehlen. Provisioning-Befehle (`devices`, `certs`, `bundle-ids`, `profiles`) verwenden eine andere Kennung und lösen keine Aliase auf.
:::
