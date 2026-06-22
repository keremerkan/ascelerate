---
sidebar_position: 3
title: KI-Coding-Skill
---

# KI-Coding-Skill

ascelerate wird mit einer Skill-Datei ausgeliefert, die KI-Coding-Agenten (Claude Code, Cursor, Windsurf, GitHub Copilot) vollständiges Wissen über alle Befehle, JSON-Formate und Workflows vermittelt.

## Installation über die Binary

```bash
ascelerate install-skill          # für jeden erkannten Agenten installieren/aktualisieren
ascelerate install-skill --all    # alle unterstützten Agenten einbeziehen (z. B. Copilot)
```

Erkennt Claude Code, Cursor und Windsurf automatisch (und GitHub Copilot mit `--all`), installiert oder aktualisiert den Skill für jeden und prüft bei jedem Aufruf, ob der Skill veraltet ist. Zum Entfernen bei allen Agenten:

```bash
ascelerate install-skill --uninstall
```

## Installation über npx (beliebiger KI-Coding-Agent)

```bash
npx ascelerate-skill
```

Dies zeigt ein interaktives Menü zur Auswahl Ihres Agenten und installiert den Skill im entsprechenden Verzeichnis. Die Skill-Datei wird von GitHub abgerufen und ist daher immer aktuell.

Zum Entfernen:

```bash
npx ascelerate-skill --uninstall
```

## Was der Skill ermöglicht

Mit dem installierten Skill kann Ihr KI-Coding-Agent:

- Jeden asc-Befehl in Ihrem Auftrag ausführen
- Workflow-Dateien für Ihren Release-Prozess erstellen
- Lokalisierungen über mehrere Sprachen hinweg verwalten
- Die gesamte Pipeline von Archivierung über Upload bis zur Einreichung abwickeln
- Mit Provisioning-Profilen, Zertifikaten und Geräten arbeiten
