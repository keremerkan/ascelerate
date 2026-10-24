---
sidebar_position: 17
title: TestFlight
---

# TestFlight

Gestione de principio a fin las pruebas beta en TestFlight: grupos de prueba, probadores, distribución de compilaciones, notas de Qué probar, revisión beta y comentarios de los probadores.

Los comandos que actúan sobre una compilación usan de forma predeterminada la última compilación no caducada. Indique `--build <number>` para elegir una compilación concreta y `--platform` para deshacer la ambigüedad cuando una app de compra universal comparte números de compilación entre plataformas.

## Grupos de prueba

```bash
ascelerate testflight groups list <bundle-id>
ascelerate testflight groups info <bundle-id> "External Testers"
ascelerate testflight groups create <bundle-id> --name "Friends" --public-link --public-link-limit 100
ascelerate testflight groups update <bundle-id> "Friends" --public-link false
ascelerate testflight groups update <bundle-id> "Friends" --mac false --vision-pro true
ascelerate testflight groups delete <bundle-id> "Friends"
```

`groups list` muestra el tipo de cada grupo, su enlace público, el límite de probadores y si admite comentarios. `groups info` añade los probadores del grupo y las compilaciones asignadas. `create` acepta `--internal` para crear un grupo interno (miembros del equipo) y `--all-builds` para darle acceso automático a todas las compilaciones; los grupos externos pueden activar un enlace público de invitación con un límite de probadores opcional. `update` también admite `--mac` y `--vision-pro`, que indican si los probadores pueden ejecutar las compilaciones para iPhone e iPad del grupo en Mac con Apple silicon y en Apple Vision Pro.

Los nombres de grupo no distinguen entre mayúsculas y minúsculas. Si omite el nombre, podrá elegir el grupo en una lista interactiva.

### Asignar compilaciones

```bash
# De forma predeterminada, la última compilación no caducada
ascelerate testflight groups add-build <bundle-id> "Friends"
ascelerate testflight groups add-build <bundle-id> "Friends" --build 123
ascelerate testflight groups remove-build <bundle-id> "Friends" --build 123
```

### Criterios de selección

Los grupos con enlace público que tienen criterios de selección pueden modificarlos o eliminarlos. Apple ya no permite añadir criterios nuevos a un grupo (y App Store Connect tampoco los muestra ya), por lo que `set` solo sustituye los existentes:

```bash
# Ver los criterios actuales y las opciones de dispositivo y sistema operativo que admite Apple
ascelerate testflight groups criteria view <bundle-id> "Friends" --options

# Sustituir los criterios: FAMILY[:MIN[:MAX]], con límites inclusivos
ascelerate testflight groups criteria set <bundle-id> "Friends" --filter IPHONE:18.0 --filter IPAD:17.0:26

# Eliminar todos los criterios
ascelerate testflight groups criteria clear <bundle-id> "Friends"
```

Familias válidas: `IPHONE`, `IPAD`, `MAC`, `APPLE_TV`, `APPLE_WATCH`, `VISION`.

## Probadores

```bash
ascelerate testflight testers list <bundle-id>
ascelerate testflight testers list <bundle-id> --group "Friends"

# Al añadirlo, se envía la invitación de TestFlight en los grupos externos
ascelerate testflight testers add <bundle-id> --email tester@example.com --first-name Jane --group "Friends"

# Quitar de un grupo o de toda la app
ascelerate testflight testers remove <bundle-id> tester@example.com --group "Friends"
ascelerate testflight testers remove <bundle-id> tester@example.com

# Volver a enviar el correo de invitación
ascelerate testflight testers invite <bundle-id> tester@example.com
```

En `add` e `import`, `--group` admite varios nombres de grupo separados por comas.

### Importación masiva

```bash
ascelerate testflight testers import <bundle-id> --file testers.csv --group "Friends"
```

El archivo contiene un probador por línea: `email[,first name[,last name]]`. Se omiten las líneas en blanco, las que empiezan por `#` y una fila de encabezado inicial, de modo que el formato CSV que exporta la interfaz web de App Store Connect funciona tal cual. Las filas con errores se indican al final sin interrumpir el resto del lote.

## Compilaciones y distribución

```bash
# Todas las compilaciones con sus estados de TestFlight
ascelerate testflight builds <bundle-id>
ascelerate testflight builds <bundle-id> --platform ios --limit 50

# Series de versiones preliminares
ascelerate testflight versions <bundle-id>

# Estado completo de una compilación
ascelerate testflight status <bundle-id> --build 123
```

`builds` muestra de cada compilación el estado de procesamiento, los estados de las pruebas internas y externas y la fecha de caducidad. `status` añade, para una sola compilación, el ajuste de notificación automática y el estado de la revisión beta. Ambos aceptan `--json` para obtener una salida legible por máquinas ([convenciones](../guides/automation.md#json-output)).

```bash
# Hacer caducar una compilación para que los probadores ya no puedan instalarla
ascelerate testflight expire <bundle-id> --build 123

# Avisar a los probadores de que hay una compilación disponible
ascelerate testflight notify <bundle-id>

# Activar o desactivar la notificación automática de una compilación
ascelerate testflight auto-notify <bundle-id> --enabled false
```

## Qué probar

Las notas de prueba se guardan por compilación y por idioma:

```bash
ascelerate testflight whats-new view <bundle-id>

# Un idioma, o todos los idiomas existentes si se omite --locale
ascelerate testflight whats-new set <bundle-id> --text "Try the new map filters" --locale en-US
ascelerate testflight whats-new set <bundle-id> --text "Try the new map filters"

# Ida y vuelta a través de JSON
ascelerate testflight whats-new export <bundle-id> --output notes.json
ascelerate testflight whats-new import <bundle-id> --file notes.json
```

El formato JSON es el mismo que el de los demás comandos de localización:

```json
{
  "en-US": { "whatsNew": "Try the new map filters" },
  "de-DE": { "whatsNew": "Testen Sie die neuen Kartenfilter" }
}
```

## Revisión beta

Las pruebas externas requieren una revisión beta de cada compilación:

```bash
ascelerate testflight submit <bundle-id> --build 123
ascelerate testflight status <bundle-id> --build 123
```

La información de la app beta y los datos para la revisión se definen a nivel de app:

```bash
# Descripción de la app beta y correo para comentarios, por idioma
ascelerate testflight app-info view <bundle-id>
ascelerate testflight app-info update <bundle-id> --locale en-US --feedback-email me@example.com
ascelerate testflight app-info export <bundle-id> --output beta-app-info.json
ascelerate testflight app-info import <bundle-id> --file beta-app-info.json

# Contacto y cuenta de demostración para el equipo de revisión beta
ascelerate testflight review-info <bundle-id>
ascelerate testflight review-info <bundle-id> --demo-account-name demo@example.com --demo-account-required true

# Acuerdo de licencia beta personalizado (--text "" vuelve al acuerdo estándar de Apple)
ascelerate testflight eula <bundle-id>
ascelerate testflight eula <bundle-id> --file eula.txt
```

## Comentarios de los probadores

Informes de fallos y comentarios con capturas que los probadores envían a través de TestFlight:

```bash
ascelerate testflight feedback crashes list <bundle-id>
ascelerate testflight feedback crashes info <submission-id>
ascelerate testflight feedback crashes log <submission-id> --output crash.log
ascelerate testflight feedback crashes delete <submission-id>

ascelerate testflight feedback screenshots list <bundle-id>
ascelerate testflight feedback screenshots info <submission-id>
ascelerate testflight feedback screenshots download <bundle-id> [submission-id] --output feedback.zip
ascelerate testflight feedback screenshots delete <submission-id>
```

`list` admite los filtros `--build` y `--platform`. `info` muestra todo el contexto del dispositivo: modelo, versión del sistema operativo, idioma, tipo de conexión, batería, espacio libre en disco y el comentario del probador. `log` muestra el registro del fallo o lo guarda con `--output`. `download` empaqueta en un archivo zip las capturas y el comentario de un envío; si omite el ID del envío, podrá elegirlo en una lista paginada de los envíos de la app. Las URL de las capturas caducan al cabo de unos días, así que descargue los comentarios que quiera conservar.
