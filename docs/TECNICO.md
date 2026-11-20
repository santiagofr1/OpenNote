# Documentación técnica de OpenNote

Este documento describe cómo está organizado OpenNote por dentro: el código, el formato de los
archivos, las medidas de la hoja y cómo se corren los tests. Para compilar y contribuir, ver
[CONTRIBUTING.md](../CONTRIBUTING.md).

## Plataformas

OpenNote está hecho con Flutter. Apunta a Android (tablet) y a Linux (PC).

## Estructura del código

El código está dividido por capas. Cada capa usa solo las de arriba:

- `lib/domain/` — datos puros: medidas de la hoja, trazos, cuadernos (`Notebook`, `SheetMeta`),
  carpetas (`Folder`, mover/borrar/buscar), el cuaderno abierto en memoria (`NotebookDoc`, con las
  operaciones de hojas) y herramientas.
- `lib/data/` — archivos (`Storage`, códec binario `sheet_codec`, migración), exportar PDF/PNG,
  importar imágenes/audio/PDF.
- `lib/rendering/` — dibujo de trazos, papel, hojas completas (miniaturas y PDF) y capas del editor.
- `lib/editor/` — editor del cuaderno (toda la tira): `page_editor.dart` coordina; entrada del lápiz
  (`ink`), selección, deshacer (`history`), textos, elementos, zoom (`viewport`, `touch_gestures`),
  tirar para agregar hoja, barra acoplable (`dock_layout`, `toolbar`) y menús.
- `lib/screens/` — biblioteca y cuaderno abierto (panel de hojas, búsqueda, estilo, menús).
- `lib/widgets/`, `lib/theme/` — diálogos compartidos y tema.
- `lib/main.dart`, `lib/app.dart` — arranque.

## Fondos en milímetros de A4

La hoja mide 1000 x 1414 unidades lógicas = 210 x 297 mm (1 mm = 1000/210 unidades;
`lib/domain/geometry.dart`).

El rayado (7 / 8 / 10 mm, margen rojo a 25 mm) y la cuadrícula / puntos (5 / 7 mm, centrados) salen
de `lib/domain/paper_layout.dart`. El mismo dibujo se usa en el editor, en las miniaturas, en los PNG
y en el PDF (página A4 llena), así que al imprimir al 100 % las medidas son reales.

El texto con teclado se apoya en el renglón de su propia hoja.

### Texto con formato
- Modelo puro en `lib/domain/rich_text.dart`: `TextBlock.body` es un `RichBody` (lista de `Para`: estilo
  normal/título/subtítulo, lista ninguna/viñeta/numerada/tareas, sangría 0..4, alineación; cada uno con `Run`s
  de negrita, cursiva, subrayado, tachado, color y resaltado). Inmutable: cada operación (`toggle`, `setList`,
  `enter`, `backspaceAtStart`, `replaceRange`, `indent`, `numbering`) devuelve un cuerpo nuevo. Los rangos son
  posiciones globales (un salto de línea entre párrafos).
- JSON: sin formato se guarda igual que antes (`text`); con formato agrega `rich` (y deja `text` de respaldo). Un
  texto viejo (solo `text`) se carga como párrafos normales partiendo por `\n`: no hay migración. Búsqueda y
  portapapeles usan `TextBlock.text` (texto plano).
- Dibujo: `lib/rendering/text_layout.dart` (`paraLayout`, `layoutBlock`) lo comparten el editor y las miniaturas /
  PNG / PDF. Los títulos usan letra más grande pero el interlineado queda en un renglón (caen sobre el rayado);
  la casilla de tareas se dibuja con trazos.
- Edición (`lib/editor/rich_editing.dart`): un `TextField` por párrafo, no uno solo. Se eligió así porque la
  alineación, la sangría y el marcador son por párrafo y un campo único solo tiene una alineación; además
  Enter / retroceso al principio parten y unen campos sin tocar el caret nativo. A cambio no hay selección que
  cruce párrafos con el dedo (el formato de párrafo aplica al párrafo con foco; las operaciones del modelo ya
  aceptan rangos entre párrafos). Cada campo lleva un carácter guía invisible (U+200B) al principio: si el teclado
  del celular lo borra, es un retroceso al principio. `RichController.buildTextSpan` pinta los tramos y el valor
  que escribe el usuario se pasa al modelo (`userEdit`) heredando el formato del carácter anterior o el pendiente
  (negrita sin selección).
- Barra de formato (`format_bar.dart`): botones que no toman el foco (`canRequestFocus: false` +
  `TextFieldTapRegion`), así el teclado no se cierra.
- El tecladito de la barra crea un bloque debajo de lo último visible de la hoja que se ve; en modo texto reabre el
  teclado en el último bloque editado. Los bloques vacíos se borran al perder el foco.

## Almacenamiento (formato 3)

### Estructura de carpetas

```
apuntes/index.json                                  cuadernos y carpetas
apuntes/notebooks/<cuaderno>/notebook.json          orden de las hojas y sus datos
apuntes/notebooks/<cuaderno>/sheets/<hoja>.sheet    contenido de cada hoja (binario)
apuntes/media/                                      imágenes y audios (compartidos por todos los cuadernos)
apuntes/prefs.json                                  herramientas
```

- `index.json` (`"format": 3`): cuadernos (id, nombre, favorito, PIN, fondo, papel y espaciado por
  defecto, última hoja, carpeta) y carpetas (id, nombre, padre).
- `notebook.json`: por cada hoja, id, título, marcador, fondo, papel, espaciado (`spacing`, en mm;
  opcional), `rev` y `updated`.

### Modelo en memoria

En memoria el cuaderno es un solo `NotebookDoc`: trazos, textos y elementos en coordenadas globales de
la tira. La hoja `k` ocupa `y` de `k * kSheetStep` a `k * kSheetStep + kSheetH`. Cada elemento
pertenece a la hoja que contiene su borde de arriba.

Al guardar se parte por hoja (coordenadas locales), y al leer se rearma la tira.

### Formato `.sheet`

- Cabecera `"ONS"` + versión + `zlib( JSON )`. El JSON tiene los textos, los elementos y los atributos
  de los trazos, más los puntos.
- Puntos: x e y enteros en décimas, primero en zigzag-varint y después delta de delta; la presión va en
  1 byte.
- Una hoja llena de letra ronda 2 bytes por punto, unas 10 veces menos que el JSON anterior.

**Orden de dibujo y selección.** Hay un solo orden para trazos, textos, imágenes, notas y audios. En
`lib/domain/z_order.dart`, `Layered` define el campo `z` de cada elemento, `sortByZ` ordena, `zRuns` agrupa las
tandas de trazos (dentro de cada tanda el resaltador va primero) y `computeReorder` calcula el cambio de Traer al
frente / Subir uno / Bajar uno / Enviar al fondo. `NotebookDoc.drawOrder()` da el orden, `nextZ()` el `z` más alto
para lo nuevo y `reorder()` aplica el cambio (deshacible). `sheet_codec` guarda `z` en cada elemento de la hoja como
0..n-1 de abajo hacia arriba; si falta (archivos viejos) vale 0 y el desempate por tipo es imágenes/notas/audio,
trazos, textos. La selección ventana/captura está en `Selection.selectIn`: `Selection.capture` es true cuando el
arrastre va de derecha a izquierda; en ese caso toma todo lo que toca el recuadro, con `Stroke.touchesRect` y
`segmentIntersectsRect` (`geometry.dart`) para cortar contra el recorrido real del trazo.

### Guardado

- Guardar codifica las hojas en otro isolate y escribe solo las que cambiaron (compara un hash con el
  último guardado), más `notebook.json` si cambió algo de las hojas.
- Las hojas borradas se eliminan.
- Escritura atómica (temporal + rename). Los guardados de un mismo cuaderno se hacen de a uno y se
  juntan.

### Migración

Al leer un índice viejo (`pages/<id>.json`) se migra automáticamente: cada página se aplana en sus
hojas. El título de la página pasa a la primera hoja, salvo "Primera página", "Página N" o la fecha por
defecto.

La carpeta `pages/` queda en `legacy_pages_backup/`. Si la migración se corta, se rehace desde cero (el
índice nuevo se escribe al final).

## Compilar e instalar en la tablet

```
./build_install.sh
```

Requisitos:

- Flutter en `~/flutter`.
- Android SDK en `~/Android/Sdk`.
- JDK 21 en `~/Android/jdk21`.

## Actualizaciones

`lib/domain/version.dart` parsea y compara versiones (`v1.0.12`; prereleases y tags raros se ignoran).
`lib/data/updates.dart` consulta `GET https://api.github.com/repos/santiagofr1/OpenNote/releases/latest`
(sin autenticación, `User-Agent: OpenNote-app`, con `dart:io`), elige el asset `.apk` y compara el tag con
`versionName` (`package_info_plus`). Cualquier error o un 404 (repo privado) es "sin información" y no muestra nada.

- Automático: al abrir la biblioteca, solo Android release (no en debug `.test` ni en tests), si está activado y
  pasaron 24 h. `updLastCheck`, `updSkipped` y `updAuto` se guardan en `prefs.json` (`Storage.savePrefs` mezcla
  las claves, así no pisa las de las herramientas).
- Manual: ⋮ de la biblioteca → "Buscar actualizaciones" (ignora el plazo y la versión omitida).
- Actualizar: descarga a `cache/updates/` con progreso cancelable, verifica el tamaño y abre el instalador por el
  canal `opennote/updater` (`MainActivity.kt`) con un `FileProvider` (`res/xml/file_paths.xml`). Si falta el permiso
  "instalar apps desconocidas" abre esa pantalla para OpenNote. Permisos: `INTERNET`, `REQUEST_INSTALL_PACKAGES`.
- Los tests reemplazan `Updates.check/download/install` (como `Pickers`).
- Android exige que el APK nuevo esté firmado con la misma clave que el instalado (ver `docs/RELEASES.md`).

## Tests

- `flutter test test/`: lógica pura, en la PC. No necesita la tablet.
- `./run_tests.sh`: tests de integración en la tablet. Corren con el build debug
  (`com.apuntes.apuntes.test`, "OpenNote Test"), que es otra app con datos propios. Antes y después
  verifica que OpenNote y sus cuadernos sigan intactos.
- `BACKUP=1 ./run_tests.sh` además baja un backup a `~/apuntes_app_backup/`.
