---
sidebar_position: 1
title: Instalación
---

# Instalación

## Requisitos

- macOS 15 o posterior
- Swift 6.2 o posterior (solo para compilar desde el código fuente)

## Homebrew

```bash
brew install ascelerate
```

En los Mac con Apple silicon, Homebrew instala un binario ya compilado; en los Mac con Intel, lo compila desde el código fuente.

:::note
Si instaló ascelerate antes desde el tap `keremerkan/tap`, `brew update` lo traslada a la fórmula propia de Homebrew. El tap ya no lo incluye.
:::

## Script de instalación

```bash
curl -fsSL https://raw.githubusercontent.com/keremerkan/ascelerate/main/install.sh | bash
```

Descarga la última versión, comprueba que esté firmada con el Developer ID de ascelerate y la instala en `/usr/local/bin` (creando la carpeta si hace falta), para lo cual le pedirá su contraseña. Solo para Apple silicon. Más adelante puede actualizarla con `sudo ascelerate update`.

## Descarga manual

Descargue la última versión desde [GitHub Releases](https://github.com/keremerkan/ascelerate/releases):

```bash
curl -L https://github.com/keremerkan/ascelerate/releases/latest/download/ascelerate-macos-arm64.tar.gz -o ascelerate.tar.gz
tar xzf ascelerate.tar.gz
sudo mkdir -p /usr/local/bin
sudo mv ascelerate /usr/local/bin/
```

El binario está firmado con el Developer ID de ascelerate (AKE Software GmbH) y notarizado por Apple, así que macOS lo ejecuta sin mostrar ninguna advertencia. `codesign -dv /usr/local/bin/ascelerate` muestra la firma; `sudo ascelerate update` instala las versiones posteriores.

:::note
Los binarios ya compilados solo se ofrecen para Apple silicon (arm64). En un Mac con Intel, compile ascelerate desde el código fuente.
:::

## Compilar desde el código fuente

```bash
git clone https://github.com/keremerkan/ascelerate.git
cd ascelerate
swift build -c release
strip .build/release/ascelerate
cp .build/release/ascelerate /usr/local/bin/
```

:::note
La compilación en modo release tarda varios minutos porque compila el cliente de App Store Connect que ascelerate genera a partir de la especificación OpenAPI de Apple. `strip` elimina los símbolos de depuración y reduce el binario de unos 156 MB a unos 41 MB.
:::

## Autocompletado del shell

Configure el autocompletado con el tabulador para subcomandos y opciones (compatible con zsh y bash):

```bash
ascelerate install-completions
```

El comando detecta su shell y lo configura todo automáticamente. Reinicie el shell o abra una pestaña nueva para activarlo.

## Skill para agentes de programación con IA (opcional)

Si utiliza un agente de programación con IA como Claude Code, Cursor, Windsurf o GitHub Copilot, puede instalar un archivo de skill que le da un conocimiento completo de todos los comandos y workflows de ascelerate:

```bash
ascelerate install-skill    # agentes detectados (Claude Code/Cursor/Windsurf; +Copilot con --all)
npx ascelerate-skill        # cualquier agente de programación con IA (no necesita la CLI)
```

Consulte la guía [Skill para agentes de programación con IA](../guides/ai-skill.md) para más detalles.

## Comprobar la versión

```bash
ascelerate version     # Muestra el número de versión
ascelerate --version   # Igual que el anterior
ascelerate -v          # Igual que el anterior
```
