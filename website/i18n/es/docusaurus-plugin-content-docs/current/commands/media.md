---
sidebar_position: 4
title: Capturas y vistas previas
---

# Capturas de pantalla y vistas previas de la app

## Descargar

```bash
ascelerate apps media download <bundle-id>
ascelerate apps media download <bundle-id> --folder my-media/ --version 2.1.0
ascelerate apps media download <bundle-id> --locale en-US,tr
```

De forma predeterminada, descarga en `<bundle-id>-media/`, con la misma estructura de carpetas que espera la subida.

`--locale` limita la descarga a los idiomas indicados (por ejemplo, `--locale en-US,tr`). También se guardan las capturas de pantalla de iPhone Duo y las imágenes de cabecera y de resultados de búsqueda.

## Subir

```bash
# Subir desde una carpeta
ascelerate apps media upload <bundle-id> media/

# Subir desde un archivo comprimido (admite zip, tar y tar.gz)
ascelerate apps media upload <bundle-id> screenshots.zip

# Subir a una versión concreta (añada --platform para las apps de compra universal)
ascelerate apps media upload <bundle-id> media/ --version 2.1.0
ascelerate apps media upload <bundle-id> media/ --version 2.1.0 --platform macos

# Reemplazar el contenido existente de los conjuntos correspondientes antes de subir
ascelerate apps media upload <bundle-id> media/ --replace

# Modo interactivo: elegir una carpeta o un archivo comprimido del directorio actual
ascelerate apps media upload <bundle-id>
```

Si se omite el argumento de la carpeta, el comando muestra una lista numerada con todos los subdirectorios y archivos comprimidos del directorio actual para que elija uno. Los archivos comprimidos (zip, tar, tar.gz) se extraen automáticamente antes de la subida.

La línea de cada archivo empieza con su posición dentro de la ejecución (`[57/203]`). En un terminal, la línea muestra además cuánto se ha subido del archivo mientras se envía.

## Estructura de carpetas

Organice su carpeta multimedia con subcarpetas por idioma y por tipo de pantalla:

```
media/
├── en-US/
│   ├── APP_IPHONE_67/
│   │   ├── 01_home.png
│   │   ├── 02_settings.png
│   │   └── preview.mp4
│   └── APP_IPAD_PRO_3GEN_129/
│       └── 01_home.png
└── de-DE/
    └── APP_IPHONE_67/
        ├── 01_home.png
        └── 02_settings.png
```

- **Nivel 1:** código de idioma (por ejemplo, `en-US`, `de-DE`, `ja`)
- **Nivel 2:** nombre de la carpeta del tipo de pantalla (consulte la tabla siguiente)
- **Nivel 3:** archivos multimedia; las imágenes (`.png`, `.jpg`, `.jpeg`) se convierten en capturas de pantalla y los vídeos (`.mp4`, `.mov`), en vistas previas de la app
- Los archivos se suben por orden alfabético de nombre
- Los archivos no admitidos se omiten con una advertencia

## Tipos de pantalla

App Store Connect exige capturas de pantalla **`APP_IPHONE_67`** para las apps de iPhone y **`APP_IPAD_PRO_3GEN_129`** para las apps de iPad. Todos los demás tipos de pantalla son opcionales.

| Nombre de la carpeta | Dispositivo | Capturas de pantalla | Vistas previas |
|---|---|---|---|
| `APP_IPHONE_67` | iPhone de 6,7" (iPhone 17 Pro Max, 16 Pro Max, 15 Pro Max) | **Obligatorio** | Sí |
| `APP_IPAD_PRO_3GEN_129` | iPad Pro de 12,9" (3.ª generación o posterior) | **Obligatorio** | Sí |

<details>
<summary>Todos los tipos de pantalla opcionales</summary>

| Nombre de la carpeta | Dispositivo | Capturas de pantalla | Vistas previas |
|---|---|---|---|
| `APP_IPHONE_61` | iPhone de 6,1" (iPhone 17 Pro, 16 Pro, 15 Pro) | Sí | Sí |
| `APP_IPHONE_65` | iPhone de 6,5" (iPhone 11 Pro Max, XS Max) | Sí | Sí |
| `APP_IPHONE_58` | iPhone de 5,8" (iPhone 11 Pro, X, XS) | Sí | Sí |
| `APP_IPHONE_55` | iPhone de 5,5" (iPhone 8 Plus, 7 Plus, 6s Plus) | Sí | Sí |
| `APP_IPHONE_47` | iPhone de 4,7" (iPhone SE de 3.ª generación, 8, 7, 6s) | Sí | Sí |
| `APP_IPHONE_40` | iPhone de 4" (iPhone SE de 1.ª generación, 5s, 5c) | Sí | Sí |
| `APP_IPHONE_35` | iPhone de 3,5" (iPhone 4s y anteriores) | Sí | Sí |
| `APP_IPHONE_DUO` | iPhone Duo (consulte [más abajo](#iphone-duo)) | Sí | No |
| `PRODUCT_PAGE_HEADER` | Cabecera de la página de producto (consulte [más abajo](#header-and-search-results)) | Sí | No |
| `APP_STORE_SEARCH_RESULTS` | Resultados de búsqueda del App Store (consulte [más abajo](#header-and-search-results)) | Sí | No |
| `APP_IPAD_PRO_3GEN_11` | iPad Pro de 11" | Sí | Sí |
| `APP_IPAD_PRO_129` | iPad Pro de 12,9" (1.ª y 2.ª generación) | Sí | Sí |
| `APP_IPAD_105` | iPad de 10,5" (iPad Air de 3.ª generación, iPad Pro de 10,5") | Sí | Sí |
| `APP_IPAD_97` | iPad de 9,7" (iPad de 6.ª generación y anteriores) | Sí | Sí |
| `APP_DESKTOP` | Mac | Sí | Sí |
| `APP_APPLE_TV` | Apple TV | Sí | Sí |
| `APP_APPLE_VISION_PRO` | Apple Vision Pro | Sí | Sí |
| `APP_WATCH_ULTRA` | Apple Watch Ultra | Sí | No |
| `APP_WATCH_SERIES_10` | Apple Watch Series 10 | Sí | No |
| `APP_WATCH_SERIES_7` | Apple Watch Series 7 | Sí | No |
| `APP_WATCH_SERIES_4` | Apple Watch Series 4 | Sí | No |
| `APP_WATCH_SERIES_3` | Apple Watch Series 3 | Sí | No |
| `IMESSAGE_APP_IPHONE_67` | iMessage iPhone de 6,7" | Sí | No |
| `IMESSAGE_APP_IPHONE_61` | iMessage iPhone de 6,1" | Sí | No |
| `IMESSAGE_APP_IPHONE_65` | iMessage iPhone de 6,5" | Sí | No |
| `IMESSAGE_APP_IPHONE_58` | iMessage iPhone de 5,8" | Sí | No |
| `IMESSAGE_APP_IPHONE_55` | iMessage iPhone de 5,5" | Sí | No |
| `IMESSAGE_APP_IPHONE_47` | iMessage iPhone de 4,7" | Sí | No |
| `IMESSAGE_APP_IPHONE_40` | iMessage iPhone de 4" | Sí | No |
| `IMESSAGE_APP_IPAD_PRO_3GEN_129` | iMessage iPad Pro de 12,9" (3.ª generación o posterior) | Sí | No |
| `IMESSAGE_APP_IPAD_PRO_3GEN_11` | iMessage iPad Pro de 11" | Sí | No |
| `IMESSAGE_APP_IPAD_PRO_129` | iMessage iPad Pro de 12,9" (1.ª y 2.ª generación) | Sí | No |
| `IMESSAGE_APP_IPAD_105` | iMessage iPad de 10,5" | Sí | No |
| `IMESSAGE_APP_IPAD_97` | iMessage iPad de 9,7" | Sí | No |

</details>

:::note
Los tipos de pantalla de Watch e iMessage solo admiten capturas de pantalla: los vídeos de esas carpetas se omiten con una advertencia. La opción `--replace` elimina todo el contenido existente de cada conjunto correspondiente antes de subir el nuevo.
:::

### iPhone Duo

App Store Connect no tiene un conjunto de capturas de pantalla para iPhone Duo. ascelerate sube los archivos de una carpeta `APP_IPHONE_DUO` a la biblioteca multimedia de la app y los coloca en la localización de la versión, en el orden de los archivos. Se aceptan los tamaños 2853×2007 o 2007×2853 (pantalla interior, desplegado) y 2034×1398 o 1398×2034 (pantalla exterior); cualquier otro tamaño se rechaza antes de subir nada. Con `--replace`, primero se eliminan las capturas de pantalla de iPhone Duo existentes en cada idioma.

La carpeta también puede contener vistas previas de la app para iPhone Duo (`.mp4`, `.m4v` o `.mov`): 1920×886 o 886×1920, de 15 a 30 segundos a 23–30 fps y con pista de audio. Se añaden después de las vistas previas que ya tenga el idioma; con `--replace`, estas se eliminan primero. Las capturas de pantalla y las vistas previas se reemplazan por separado, y solo cuando la carpeta contiene archivos de ese tipo.

Si un archivo sigue fallando tras los reintentos, `media upload` vuelve a colocar las capturas de pantalla o vistas previas de iPhone Duo de ese idioma al final de la ejecución, para que se mantengan en el orden de los archivos. `media verify` las muestra con sus nombres de archivo y su estado de procesamiento; si se le indica la carpeta multimedia, también señala los idiomas cuyos archivos u orden difieren de los de la carpeta (ejecute `media upload` con `--replace` para corregirlos). `media download` guarda las capturas de pantalla con sus propios nombres de archivo, y `media prune` nunca las elimina.

### Cabecera de la página de producto y resultados de búsqueda {#header-and-search-results}

Otras dos carpetas se suben a través de la biblioteca multimedia. Cada una contiene una imagen o un vídeo por idioma que no está ligado a ninguna clase de dispositivo: la versión lo muestra en todos los dispositivos (iPhone, iPad, iPhone Duo) y sirve para las versiones de cualquier plataforma.

- `PRODUCT_PAGE_HEADER`: la imagen o el vídeo de la parte superior de la página de producto. Un PNG de 3840×1646 o 5244×2950, o un vídeo de 3840×1646 de 5 a 30 segundos a 30 o 60 fps.
- `APP_STORE_SEARCH_RESULTS`: se muestra junto a la app en los resultados de búsqueda del App Store. Un JPG o PNG con proporción 3:2, de 1920×1280 a 3840×2560, o un PNG de 5244×2950; o bien un vídeo 3:2 en el mismo rango de tamaños, de 5 a 30 segundos a 30 o 60 fps.

Al subir se reemplaza la imagen o el vídeo actual del idioma, con o sin `--replace`; el anterior solo se elimina después de que se haya subido el nuevo. Un vídeo nuevo permanece en procesamiento durante unos minutos, como muestra `media verify`. `media download` guarda las imágenes; App Store Connect no ofrece ningún enlace de descarga para estos vídeos.

Las páginas de producto personalizadas admiten los mismos archivos mediante `product-pages media upload` con `--display-type PRODUCT_PAGE_HEADER`, `APP_STORE_SEARCH_RESULTS` o `APP_IPHONE_DUO`.

## Diseñar imágenes para el App Store {#designing-app-store-images}

`ascelerate screenshot setup-prompt --design` muestra instrucciones para que un agente de programación con IA cree un generador de diseños: una pequeña app web en la carpeta `app-store-screenshots/` del proyecto que convierte capturas de pantalla enmarcadas (`ascelerate screenshot frame`) en imágenes publicitarias para el App Store con titulares en todos los idiomas, y las exporta con la estructura que admite `media upload`:

```
export/en-US/APP_IPHONE_67/01_hero.png
export/en-US/APP_IPAD_PRO_3GEN_129/01_hero.png
export/de-DE/APP_IPHONE_67/01_hero.png
```

```bash
ascelerate apps media upload <bundle-id> export --platform ios --replace
```

La skill [app-store-screenshots](https://github.com/keremerkan/ascelerate/tree/main/skills/app-store-screenshots) (`npx skills add keremerkan/ascelerate`) remite a los agentes a esas mismas instrucciones.

## Verificar y reintentar contenido bloqueado

A veces, las capturas de pantalla o las vistas previas se quedan bloqueadas en «procesando» tras la subida. Use `media verify` para comprobar su estado y, si lo desea, reintentar los elementos bloqueados:

```bash
# Comprobar el estado de todas las capturas de pantalla y vistas previas
ascelerate apps media verify <bundle-id>

# Comprobar una versión concreta
ascelerate apps media verify <bundle-id> --version 2.1.0

# Reintentar los elementos bloqueados con los archivos locales de la carpeta multimedia
ascelerate apps media verify <bundle-id> media/
```

Sin argumento de carpeta, el comando muestra un informe de estado de solo lectura. Los conjuntos cuyos elementos están todos completos se resumen en una sola línea; los que tienen elementos bloqueados se despliegan para mostrar cada archivo y su estado. Con un argumento de carpeta, el comando ofrece reintentar los elementos bloqueados: los elimina y los vuelve a subir desde los archivos locales correspondientes, conservando su posición original.

Una captura de pantalla también cuenta como bloqueada cuando figura como completa pero su ubicación en la biblioteca multimedia sigue en procesamiento. App Review rechaza una versión en ese estado («Asset is being processed»), y el reintento con la carpeta vuelve a subir esa captura de pantalla.

## Eliminar conjuntos obsoletos

`--replace` al subir solo vacía los conjuntos que coinciden con una carpeta local: los conjuntos del servidor para tamaños de pantalla que ya no utiliza conservan sus capturas de pantalla antiguas. `media prune` elimina los conjuntos que no tienen una carpeta local de idioma y tipo de pantalla correspondiente, tras mostrarlos con su número de elementos y pedir confirmación:

```bash
ascelerate apps media prune <bundle-id> media/
ascelerate apps media prune <bundle-id> media/ --version 2.1.0 --platform ios
```

Los idiomas sin carpeta local se omiten por completo: el comando solo elimina conjuntos dentro de los idiomas que la carpeta gestiona realmente.

## Quitar imágenes de la biblioteca multimedia

`media remove` quita de la versión un tipo de elemento de la biblioteca multimedia: la imagen o el vídeo de `PRODUCT_PAGE_HEADER` o `APP_STORE_SEARCH_RESULTS`, o las capturas de pantalla de `APP_IPHONE_DUO` (`--previews` para sus vistas previas de la app). Actúa sobre los idiomas indicados con `--locale` o sobre todos ellos, y muestra lo que ha encontrado antes de pedir confirmación:

```bash
ascelerate apps media remove <bundle-id> PRODUCT_PAGE_HEADER --locale en-US
ascelerate apps media remove <bundle-id> APP_STORE_SEARCH_RESULTS
ascelerate apps media remove <bundle-id> APP_IPHONE_DUO --locale en-US,tr --version 2.1.0
ascelerate apps media remove <bundle-id> APP_IPHONE_DUO --previews --locale en-US
```

## Limpiar la biblioteca multimedia

Cada app tiene una biblioteca multimedia con las imágenes y los vídeos que se han subido, y las versiones los comparten: las capturas de pantalla de una versión nueva son las imágenes de la versión anterior, y las versiones antiguas conservan las suyas. Por eso, una imagen o un vídeo sigue en uso mientras alguna versión (antiguas incluidas), página de producto personalizada o evento lo tenga colocado. Cuando ascelerate elimina una ubicación (`media remove`, `media upload --replace` o al reemplazar una imagen de cabecera o de resultados de búsqueda), también elimina la imagen o el vídeo si ya nada lo utiliza y nunca ha pasado por App Review.

Aun así, subidas anteriores pueden haber dejado imágenes y vídeos sin usar en la biblioteca. `media library` cuenta las imágenes y los vídeos y muestra los que no se usan; con `--delete-unused`, los elimina tras pedir confirmación:

```bash
ascelerate apps media library <bundle-id>
ascelerate apps media library <bundle-id> --delete-unused
ascelerate apps media library <bundle-id> --only APP_IPHONE_DUO --delete-unused
```

`--only` limita la lista a las imágenes que encajan con los tipos indicados, según la categoría del recurso y su tamaño en píxeles: `PRODUCT_PAGE_HEADER`, `APP_STORE_SEARCH_RESULTS`, `APP_IPHONE_DUO`, un tipo de pantalla de capturas como `APP_IPHONE_67` (los tamaños proceden de App Store Connect) o `UNFINISHED_UPLOADS` para las subidas cuyo archivo nunca llegó. Así, la biblioteca puede limpiarse un tipo de dispositivo cada vez. Las imágenes con menos de una hora de antigüedad se conservan siempre, ya que una subida en curso podría estar a punto de colocarlas, y si una ejecución alcanza el límite horario de la API de App Store Connect, se detiene y le indica que vuelva a ejecutarla más tarde.

Las imágenes y los vídeos que han pasado por App Review nunca se eliminan, estén colocados o no, y cada uno se vuelve a comprobar justo antes de eliminarlo.
