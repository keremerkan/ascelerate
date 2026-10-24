---
sidebar_position: 18
title: Optimización de la página de producto
---

# Optimización de la página de producto

Pruebe capturas de pantalla, vistas previas de la app e iconos de app alternativos frente a su página de producto original del App Store. Una prueba muestra hasta tres **variantes** (versiones distintas de la página) a una parte de los visitantes del App Store y compara sus tasas de conversión con las de la página original. Las pruebas y las variantes se indican por su **nombre** o su ID.

## Listar e inspeccionar

```bash
ascelerate experiments <bundle-id>
ascelerate experiments info <bundle-id> "Screenshot order"
```

`info` muestra el estado de la prueba, su porcentaje de tráfico y sus fechas, así como cada variante con sus idiomas y su contenido multimedia por idioma. Ambos comandos admiten `--json`.

## Crear una prueba

```bash
ascelerate experiments create <bundle-id> --name "Screenshot order" --traffic 50 --treatment "Map first" --treatment "Alerts first"
```

`--traffic` es el porcentaje de visitantes del App Store que ven una de las variantes. Se reparte a partes iguales entre ellas, y el resto de los visitantes ve la página original. `--platform` es `ios` de forma predeterminada.

## Variantes

```bash
ascelerate experiments treatments add <bundle-id> "Screenshot order" --name "Icon B" --app-icon AppIconB
ascelerate experiments treatments update <bundle-id> "Screenshot order" "Icon B" --name "Blue icon"
ascelerate experiments treatments delete <bundle-id> "Screenshot order" "Blue icon"
ascelerate experiments treatments remove-locale <bundle-id> "Screenshot order" "Map first" --locale de-DE
```

`--app-icon` prueba un icono de app alternativo, que debe estar incluido como icono alternativo en la compilación publicada. En un idioma que una variante no cubre se muestra la página original, incluso a los visitantes que participan en la prueba.

## Contenido multimedia

```bash
ascelerate experiments media list <bundle-id> "Screenshot order"
ascelerate experiments media upload <bundle-id> "Screenshot order" "Map first" --locale en-US --display-type APP_IPHONE_67 01.png
ascelerate experiments media upload <bundle-id> "Screenshot order" "Map first" --locale en-US --preview-type APP_IPHONE_67 preview.mp4
ascelerate experiments media delete <bundle-id> "Screenshot order" <media-id>
```

Las subidas funcionan como las del [contenido multimedia de las páginas de producto personalizadas](product-pages.md): las imágenes van a los conjuntos de capturas de pantalla según `--display-type`, los vídeos a los conjuntos de vistas previas de la app según `--preview-type`, y `PRODUCT_PAGE_HEADER`, `APP_STORE_SEARCH_RESULTS` y `APP_IPHONE_DUO` pasan por la biblioteca multimedia. El idioma de la variante se crea con la primera subida.

:::note
Un idioma nuevo de una variante empieza como una **copia del contenido multimedia de la página original**: App Store Connect lo rellena con las capturas de pantalla y las vistas previas de la versión actual. Lo que suba se añade después de esa copia, así que elimine las capturas copiadas que vaya a sustituir (`media list` muestra sus ID).
:::

## Revisión, inicio y detención

```bash
ascelerate experiments submit <bundle-id> "Screenshot order"
ascelerate experiments start <bundle-id> "Screenshot order"
ascelerate experiments stop <bundle-id> "Screenshot order"
```

Una prueba con contenido multimedia nuevo necesita pasar por App Review antes de poder empezar (`info` lo indica). `submit` crea un envío a App Review que solo contiene la prueba y lo envía. Si ya existe para la plataforma un borrador de envío con otros elementos (por ejemplo, una versión de la app), la prueba se añade a él y va a revisión junto con ellos mediante [`apps review submit`](apps.md#submit-for-review). Una vez aprobada la prueba, `start` la inicia y `stop` la finaliza. Los resultados se muestran en App Store Connect.

## Actualizar y eliminar

```bash
ascelerate experiments update <bundle-id> "Screenshot order" --traffic 30
ascelerate experiments delete <bundle-id> "Screenshot order"
```

Cambie una sola cosa en cada variante (por ejemplo, la primera captura de pantalla o el icono) para que el resultado le indique qué cambio marcó la diferencia.
