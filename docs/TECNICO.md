# Documentación técnica de OpenNote

Este documento describe cómo está organizado OpenNote por dentro: el código, el formato de los
archivos, las medidas de la hoja y cómo se corren los tests. Para compilar y contribuir, ver
[CONTRIBUTING.md](../CONTRIBUTING.md).

## Plataformas

OpenNote está hecho con Flutter. Apunta a Android (tablet) y a Linux (PC).

### Tablets y lápices

- **Probado:** solo en Galaxy Tab S6 Lite (SM-P620) con Android 16. Ahí andan la presión y el botón del S Pen
  para borrar.
- **Cómo se lee el lápiz:** todo en Dart (`lib/editor/ink.dart`), sin código nativo. Es lápiz si
  `PointerDeviceKind.stylus` o `invertedStylus`. Borra si es `invertedStylus` (la punta goma de algunos lápices),
  si tiene `kPrimaryStylusButton` o `kSecondaryStylusButton` apretado, o con el botón derecho del mouse. Son
  constantes genéricas de Android (`TOOL_TYPE_STYLUS`/`ERASER`, `BUTTON_STYLUS_PRIMARY`/`SECONDARY`, API 23),
  así que en principio sirven para cualquier lápiz activo.
- **Galaxy Tab S, sin probar:** S8, S9 y S10 (no las FE) traen S Pen con Bluetooth. S9 FE, S10 FE y S11 lo
  traen sin Bluetooth, y la S11 tiene pantalla de 120 Hz. El botón lateral debería llegar igual que en la S6 Lite,
  pero no está confirmado modelo por modelo. Un issue viejo de Flutter (#87013, 2021) reportó que en una S6 Lite
  2020 el botón no llegaba. En la SM-P620 sí llega.
- **USI 2.0 y otras marcas** (Lenovo, Xiaomi, OnePlus): sin datos todavía.
- **Para probar una tablet nueva:** escribir con presión, borrar con el botón, probar la punta goma si la tiene, y
  hacer trazos rápidos para ver si se cortan (flutter/flutter#196867 menciona muestras de movimiento perdidas).
- **minSdk:** hoy se hereda de Flutter (`flutter.minSdkVersion` en `android/app/build.gradle.kts`). Conviene
  fijarlo en 26 (Android 8, cerca del 99 % de los equipos en uso).

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

#### Carga perezosa de hojas

El cuaderno no se lee entero: `NotebookDoc.sheets` (los `SheetMeta`) siempre están todas, pero los elementos
(`strokes` / `texts` / `items`) solo existen de las hojas **cargadas** (`loadedSheets`, ids de hoja). Una hoja sin
cargar es, para la app, lo que dice su archivo en disco.

- **Al abrir** (`Storage.openNotebook(nb, around: nb.last)`): se lee `notebook.json` y solo las hojas de la última
  vista ±2. `Storage.loadNotebook` (cargar todo) queda para los tests y lo que necesite el cuaderno entero.
- **Cargar / soltar**: `Storage.loadSheets(doc, ids)` lee y decodifica en otro isolate y las pone en su lugar
  (`NotebookDoc.attachSheet`: coordenadas globales = local + `índice * kSheetStep`, sin marcar nada sucio; si la hoja ya
  estaba cargada no hace nada, nunca pisa lo de memoria). `Storage.unloadSheets(doc, ids, canUnload:)` las suelta
  (`detachSheet`).
- **Quién decide** (`PageEditor`, ver `_syncLoaded` / `_unloadFar`): se cargan las hojas del rango armado
  (`_range`: lo que se ve más un margen) más `kLoadMargin` = 2 de cada lado; se sueltan las que quedan a más de
  `kKeepMargin` = 6 hojas del rango (la diferencia evita cargar y soltar en loop), un rato después de scrollear. Una hoja
  visible sin cargar muestra el papel y "Cargando la hoja N…"; el lápiz y las herramientas la ignoran hasta que cargue.
- **Nunca se suelta una hoja** que: tiene cambios sin guardar (o hay un guardado en curso), no tiene archivo conocido
  en disco, su contenido no tiene la misma huella (`sheetDigest`: todo lo que se guarda, sin el ruido de 1e-13 de mover hojas) que el archivo (si difiere se la marca para guardar y no se suelta), tiene
  selección o arrastre, un texto o nota con foco, un trazo o borrador en curso, un audio, un elemento caído
  encima (`misplacedSheets`), o la tocan acciones del historial de deshacer / rehacer (`EditAction.sheetIds`: mientras
  una acción esté en el historial sus hojas quedan fijadas; con historial largo se sueltan menos hojas, a propósito).

**Regla de oro: nunca perder datos.** Una hoja no cargada NUNCA se escribe. `Storage._saveNow` solo toma hojas
cargadas (`splitSheets` ni siquiera devuelve las otras; hay un `assert` y una guarda que no escribe y loguea), también
en el primer guardado y con todo sucio: las coordenadas en cada archivo son locales, así que mover, insertar o
borrar hojas no cambia el contenido de las no cargadas (solo `notebook.json`). Al borrar una hoja sin cargar se
borra su archivo (la `Storage` recuerda qué ids figuran en `notebook.json`). Los hashes de las no cargadas son
desconocidos hasta leer su archivo.

Qué pasa con el resto de la app cuando no está todo en memoria:
- **Seleccionar todo**: solo lo de las hojas cargadas (las visibles y las cercanas).
- **Un elemento que cae en una hoja sin cargar** (arrastre, pegado): el movimiento se deshace si la hoja no cargó al
  soltar; si igual llega, la hoja se anota en `misplacedSheets`, el editor la carga enseguida y al cargarla se marca para
  guardar (el elemento y lo del disco quedan juntos).
- **Miniaturas del panel**: las de hojas no cargadas se leen de disco (`SheetThumbCache`, últimas 16, clave con `rev`).
- **Búsqueda** (`searchNotebookAll`): memoria para las cargadas y, para las demás, `Storage.readSheetTexts` (otro isolate,
  una hoja por vez, solo se devuelven los textos). Tocar un resultado carga esa hoja y va ahí.
- **PDF / PNG** (`sheetSource`): hoja por hoja; las no cargadas se leen de disco (con la de arriba, por si un trazo se
  pasa) y se sueltan. Lo cargado y sin guardar se exporta desde memoria.
- **Duplicar cuaderno**: se copian los archivos (`Storage.copyNotebookFiles`), sin decodificar nada.
- **Duplicar una hoja** sin cargar: se carga primero (una sola hoja) y se duplica en memoria.
- Los z (`Layered.z`) de una hoja que se carga van arriba de los de memoria: el orden *dentro* de cada hoja es el del
  archivo, pero lo que se arrastra de una hoja a otra conserva su z, así que su capa respecto a lo que ya había en la
  hoja de destino depende del orden de carga (solo cambia cómo se superponen; se guarda lo que se vio).

#### Imágenes de la tinta al desplazar (etapa 4)

Impeller no tiene caché de pictures: una hoja con mucha tinta vectorial se vuelve a rasterizar en cada cuadro del scroll.
`SheetImageCache` (`lib/rendering/sheet_image_cache.dart`) la reemplaza por imágenes (una textura) mientras la tinta está
quieta; `InkPainter` (`ink_layers.dart`) decide qué dibujar. Tandas con menos de 1500 puntos no se cachean.

- **Prefetch**: `PageEditor._updatePrefetch` calcula, al scrollear, las hojas visibles y las 3 siguientes en el sentido del
  movimiento (`SheetImageCache.prefetchPlan`; quieto: solo las visibles) y se las pasa a `prefetch`. Se generan sin esperar
  los 300 ms de quietud (que siguen valiendo para una hoja visible que no estaba en el plan). El plan se reelige en cada
  paso, así que lo que dejó de ser relevante no se genera. `_calcRange` arma al menos una hoja más en el sentido del
  scroll (hace falta un painter armado para grabar la hoja).
- **Franjas adaptativas**: la imagen de una tanda se parte en franjas horizontales que se generan de a una. La cantidad
  sale de los puntos (`SheetImageCache.stripCountFor`): ~`maxPointsPerStrip` = 3000 por franja (se cuenta con los bounds
  de los trazos; uno que cruza varias franjas cuenta en todas; tolerancia 25%), mínimo 4 y máximo 32 (1000 puntos: 4;
  46k: ~16; 200k: 32). Por qué: la traza real en la tablet (Galaxy Tab S6 Lite, Impeller, scroll de 12 s en 50 hojas
  de ~46k puntos) dio que con 4 franjas fijas grabar una franja (`ON cache grabar franja`, hilo UI) costaba 15-27 ms
  y estaba en 37 de los 39 cuadros UI lentos, y su `toImage` (`ON cache toImage franja`, hilo raster) 35-96 ms, que
  competían con el cuadro (cuadros raster de 26-60 ms). Con ~3000 puntos por franja cada trabajo baja a ~1/4 (grabar
  ~2-4 ms), a costa de más trabajos por hoja. `stripCount` fijo sigue existiendo para tests (1 = imagen entera).
  El compuesto es igual (hasta el redondeo) a la imagen entera (`strip_adaptive_test.dart`, `image_prefetch_test.dart`).
- **Prioridad** (`SheetImageCache._nextJob`): (1) las franjas de las hojas visibles que intersectan el viewport ahora
  (el editor pasa, por hoja visible, la fracción de su alto que se ve: `setVisible(..., fractions:)`), (2) el resto de las
  franjas de las visibles, (3) las hojas siguientes del plan (3 por delante, `prefetchAhead`) en orden, (4) tandas
  quietas fuera del plan. Dentro de una hoja, en el sentido del scroll.
- **Varios trabajos por cuadro, un solo `toImage`**: el primer trabajo se programa en el post-frame con
  `SchedulerBinding.scheduleTask` (prioridad de animación; con `idle` no corre durante un fling). Cuando termina, si
  el UI del último cuadro (medido desde el vsync) más lo grabado por los trabajos desde entonces está por debajo de 8 ms
  (`maxFrameMs`) y no se llegó a 4 trabajos en el cuadro (`maxJobsPerFrame`), el siguiente arranca enseguida, sin
  esperar al próximo cuadro. Si no hay presupuesto espera al post-frame y, si ese cuadro gastó más de 8 ms, se posterga
  (hasta 4 veces seguidas). No se genera con el lápiz o un pellizco en curso (`busy`). Nunca hay dos `toImage` a la vez
  (el raster es un solo hilo; `maxRasterInFlight` lo cuenta en los tests). Referencia de la última traza en la tablet:
  build p99 ~7 ms, `toImage` de franja ~7 ms en raster, ~15 franjas/s con un trabajo por cuadro; el encadenado apunta a
  multiplicar eso mientras el UI tenga holgura.
- **Quieto = urgente**: el editor marca `still` 120 ms después del último movimiento de scroll (y al abrir). Con `still`
  y franjas faltantes en una hoja visible no hay presupuesto ni espera al cuadro: se generan una tras otra hasta
  completar (pruebas: `strip_adaptive_test.dart`; `app_test.dart` verifica que en <= 1,5 s las visibles quedan en
  modo image).
- **Hoja que todavía no se ve**: si una tanda cacheable tiene franjas sin generar y su hoja no está en
  `visibleSheets`, `InkPainter` dibuja solo las franjas listas (nada si no hay ninguna) (antes la pintaba vectorial, ~40 ms una vez por hoja nueva que entra al
  rango armado sin verse) y solo deja registrado `record` / `want` para el prefetch. Al pasar a visible
  (`SheetImageCache.setVisible`, que llama `_updatePrefetch`) se repinta. Con `visibleSheets` vacío (primer cuadro,
  tests sin scroll) se dibuja como siempre: nunca queda una hoja visible en blanco.
- **Sin miniatura borrosa**: se sacó la miniatura de 320 px (quedaba estirada a ~1650 px y grabada salteando puntos,
  y como las franjas no alcanzaban al ritmo del scroll, las hojas visibles pasaban mucho tiempo borrosas). Regla: la
  nitidez manda. En una hoja visible lo que falta se dibuja vectorial recortado a las franjas faltantes (`onlyVector`);
  el costo se paga generando antes (plan de 3 hojas) y más rápido (varios trabajos por cuadro), no bajando la calidad.
  Una hoja no visible con franjas faltantes dibuja solo las listas. Al editar la hoja se descarta todo y va
  vectorial, así el trazo nuevo se ve al instante.
- **Presupuesto**: 12 tandas y 192 MB de franjas (antes 8 y 112 MB). Una hoja a ~1650 px de ancho son ~15,4 MB; la
  ventana protegida es hasta 3 visibles + 3 de prefetch + 1 detrás (el editor la protege además del plan) = 7 hojas
  ~108 MB, con margen de tandas para hojas con varias tandas y de bytes para zoom hasta ~1,3x. Techo de ~192 MB sobre
  4 GB. LRU por uso; las hojas visibles, las del plan y la de atrás nunca se desalojan (si no entra, esa tanda queda
  vectorial). Una tanda desalojada no se regenera por quietud mientras esté fuera de la ventana.
- **Medición** (`integration_test/perf_test.dart`): por cuadro se anota si había una hoja visible en vectorial y si hubo generación (contadores baratos de la caché) y se reporta cuántos de los > 16 ms caen en cada grupo.
  En el modo comparación solo cuentan los cuadros desde el primer cambio de offset hasta 500 ms después del último, y se
  informa el recorrido total (suma de |delta| por cuadro).

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

- Guardar codifica en otro isolate solo las hojas sucias (`NotebookDoc.takeDirty`; los mapas de elementos avisan
  qué hoja tocó cada alta/baja, y lo que se cambia en el lugar se marca con `markDirtyElement`) y escribe las que
  cambiaron (compara un hash con el último guardado), más `notebook.json` si cambió algo de las hojas. Solo se
  guardan hojas cargadas (ver Carga perezosa).
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
- Notas: el workflow arma el cuerpo del Release con `git log --first-parent` (en main, un renglón por merge de rama).
  `userNotes` (`updates.dart`) lo limpia para el diálogo: deja solo los renglones "- ", quita metadatos, merges de
  main, tests y docs, y le saca el prefijo "Merge feat/xxx: ".
- Los tests reemplazan `Updates.check/download/install` (como `Pickers`).
- Android exige que el APK nuevo esté firmado con la misma clave que el instalado (ver `docs/RELEASES.md`).

## Tests

- `flutter test test/`: lógica pura, en la PC. No necesita la tablet. `test/data/dirty_save_test.dart` y
  `test/data/lazy_load_test.dart` son la red de seguridad del guardado: secuencias aleatorias de operaciones contra
  un modelo de referencia con todo cargado, comparando cada `.sheet` (el segundo mezcla además cargas y descargas de
  hojas); `test/screens/lazy_notebook_test.dart` abre un cuaderno de 30 hojas por la UI.
- `./run_tests.sh`: tests de integración en la tablet. Corren con el build debug
  (`com.apuntes.apuntes.test`, "OpenNote Test"), que es otra app con datos propios. Antes y después
  verifica que OpenNote y sus cuadernos sigan intactos.
- `BACKUP=1 ./run_tests.sh` además baja un backup a `~/apuntes_app_backup/`.
- `tool/screenshots.sh`: regenera las capturas del README (`docs/img/*.png`) en la tablet. Corre
  `integration_test/screenshots_test.dart` con el build debug (`com.apuntes.apuntes.test`) y datos de ejemplo
  (`integration_test/screenshots_data.dart`) en una carpeta temporal, con las mismas verificaciones que
  `run_tests.sh`. Como `flutter drive` no tiene `--no-uninstall`, compila antes y le pasa el APK con
  `--use-application-binary`.
