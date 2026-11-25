---
sidebar_position: 3
title: Aliase
---

# Aliase

Anstatt jedes Mal vollständige Bundle IDs einzugeben, können Sie kurze Aliase erstellen:

```bash
# Alias hinzufügen (interaktive App-Auswahl)
ascelerate alias add myapp

# Den Alias überall verwenden, wo Sie eine Bundle ID angeben würden
ascelerate apps info myapp
ascelerate apps versions myapp
ascelerate apps localizations view myapp

# Alle Aliase auflisten
ascelerate alias list

# Alias entfernen
ascelerate alias remove myapp
```

Aliase werden in `~/.ascelerate/aliases.json` gespeichert. Jedes Argument ohne Punkt wird als Alias-Name interpretiert — echte Bundle IDs (die immer Punkte enthalten) funktionieren unverändert. Eine Datei, die sich nicht lesen lässt, wird gemeldet statt als leer behandelt, damit eine fehlerhafte Bearbeitung von Hand nicht überschrieben wird.

:::tip
Aliase funktionieren mit allen App-, IAP-, Abonnement- und Build-Befehlen. Provisioning-Befehle (`devices`, `certs`, `bundle-ids`, `profiles`) verwenden eine andere Kennung und lösen keine Aliase auf.
:::
