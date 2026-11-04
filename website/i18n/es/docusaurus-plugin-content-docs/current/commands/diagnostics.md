---
sidebar_position: 16
title: Diagnósticos
---

# Diagnósticos

Lo que muestra el Organizer de Xcode, desde los dispositivos de los usuarios que comparten análisis con los desarrolladores: los principales bloqueos, inicios lentos y escrituras en disco de una compilación con sus pilas de llamadas, y las métricas de rendimiento y energía de la app a lo largo de sus versiones. Sin `--build`, la compilación de la versión en el App Store.

## Firmas

```bash
ascelerate diagnostics <bundle-id>
ascelerate diagnostics <bundle-id> --type hangs --build 2041
```

Las firmas de bloqueos, inicios y escrituras en disco de la compilación, por peso dentro de cada tipo, con su tendencia frente a versiones anteriores. `--type` acepta `hangs`, `launches` o `disk-writes` (separados por comas para varios).

## Registros

```bash
ascelerate diagnostics logs <signature-id>
ascelerate diagnostics logs <signature-id> --frames 0
```

Cada evento muestreado con su dispositivo, sistema operativo y versión de la app, y luego sus pilas de llamadas; el frame al que App Store Connect atribuye el problema se marca con ▶. `--frames` limita los frames por pila de llamadas (40 por omisión, 0 para todos).

## Métricas

```bash
ascelerate diagnostics metrics <bundle-id>
ascelerate diagnostics metrics <bundle-id> --type launch,hang --all
```

Cada métrica (tiempo de inicio, tasa de bloqueos, memoria máxima, escrituras en disco, batería, terminaciones, animación, almacenamiento) por versión de la app, para todos los dispositivos en los percentiles típico (50) y 90; `--all` añade cada modelo de dispositivo. Primero aparecen las regresiones y tendencias al alza de Apple. `--build` muestra las métricas de una compilación.

Los tres aceptan `--json`.
