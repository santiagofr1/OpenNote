# Pendientes

15. **LaTeX**: lo hace el usuario; no tocar.

## Hecho

- **Issue #4, tamaño del texto** (rama `feat/tamano-texto`, 2026-11-21): el texto escrito con teclado se puede cambiar de tamaño en puntos como Word / Docs: `RunStyle.size` (null = automático, el del rayado), control A− / chip / A+ en la barra de formato con lista (Automático, 8 a 48) y atajos Ctrl+] / Ctrl+[. El render usa pt reales (12 pt = 4,23 mm al imprimir) y el párrafo crece en renglones enteros para seguir sobre las líneas; editor, miniaturas, PNG y PDF comparten `paraLayout`. Ver docs/TECNICO.md. Falta probarlo en la tablet (caso de integración nuevo).
- **17. App de PC + sincronización por Google Drive** (2026-11-21): terminado. Drive con `drive.file` (carpeta `OpenNote`; los builds debug usan `OpenNote Test`), tablet y Linux (`.deb` en el repo apt), segundo plano en Android y cifrado opcional. Secreto `GOOGLE_WEB_CLIENT_SECRET` cargado en GitHub; segundo plano probado en la tablet (la tarea de WorkManager corre sola cada 15 min, retoma la sesión con el refresh token y sincroniza; deja el resultado en el log como "OpenNote sync de fondo: ..."). Diseño e investigación en docs/SINCRONIZACION.md.
- **Issue #9, borrar no llegaba a la nube** (rama `fix/sync-borrar`, 2026-11-21): borrar un cuaderno y sincronizar daba para siempre "index.json: El archivo cambió en la nube mientras se subía". Causa: `crypto.wrap` baja `crypto.json` antes del primer `changes(token)`, eso carga el mapa de Drive (`_loaded`) y el store usaba el delta, así que lo cambiado antes de cargar el mapa nunca se informaba y `SyncState.remote['index.json']` quedaba con un md5 viejo. Arreglo: `DriveRemoteStore._listed` (el listado completo se decide por "ya se le entregó uno al motor", no por "mapa cargado") y el motor borra el token si un archivo da `RemoteConflictException`, para que la próxima pasada liste todo. Tests en `test/sync/` y caso de integración "borrar un cuaderno sincronizado lo borra de la nube".
- **Seleccionar solo el resaltador** (rama `fix/solo-resaltador`, 2026-11-21): los filtros de la barrita de selección ahora son botones con texto, "Solo resaltador" y "Sin resaltador", en una fila aparte; aparecen siempre que la selección tenga resaltador y algo más (tinta, textos, imágenes, notas), no solo trazos; "Sin resaltador" conserva textos y elementos. Mover / borrar una selección de solo resaltador no arrastra lo de abajo. Ver docs/TECNICO.md. Falta probarlo en la tablet.
- **Mover arrastrando en la biblioteca** (rama `feat/detalles`, 2026-11-21): `LongPressDraggable` con umbral: mantener apretado ~500 ms abre el menú YA, mientras sigue apretando (OverlayEntry anclado a la tarjeta, no ruta modal); si suelta sin mover queda abierto, y si mueve más de 10 px el menú se cierra y arrastra la tarjeta. Soltar sobre una carpeta (se resalta) o sobre las migas de pan, incluida "Inicio", mueve; no deja soltar una carpeta en sí misma ni en una descendiente; scroll automático cerca de los bordes; aviso "Movido a X" con "Deshacer". Ver docs/TECNICO.md.
- **Selección de texto entre párrafos** (rama `feat/detalles`, 2026-11-21): con mouse arrastrar de un párrafo a otro, con dedo / lápiz mantener apretado (~350 ms) y arrastrar; negrita, colores, listas, alineación, copiar, cortar y borrar valen sobre todo lo seleccionado (botones Copiar / Cortar / Borrar en la barra de formato). No cruza bloques distintos. Ver docs/TECNICO.md.
- **17. Sincronización en segundo plano** (2026-11-21, rama `feat/sync-fondo`): en Android una tarea de `workmanager` cada 15 min con red sincroniza con la app cerrada (`lib/sync/background_sync.dart`); candado `sync.lock` y marcas para no pisarse con la pasada de la app, la app relee el disco al volver, interruptor "Sincronizar en segundo plano" en la hoja de Sincronización. La tarea no usa `google_sign_in` (pide Activity): usa un refresh token propio canjeado del `serverAuthCode` con el cliente Web (`GOOGLE_WEB_CLIENT_SECRET`, opcional). Falta probarlo en la tablet.
- **17. Cifrado de extremo a extremo opcional para la sync con Drive** (2026-11-21, rama `feat/sync-cifrado`): frase del usuario → Argon2id (64 MiB, 3 pasadas) → XChaCha20-Poly1305 por archivo, `crypto.json` con sal y verificador, decorador `EncryptedRemoteStore` (el motor sigue comparando hashes del claro), activar/desactivar re-subiendo todo, clave en el almacenamiento seguro y sección "Cifrado" en la hoja de sincronización. Sin probar contra Drive real ni medir Argon2id en la tablet. Ver docs/SINCRONIZACION.md, "Cifrado".
- **22. Menú de la hoja con el dedo** (2026-11-21): no abría porque `_onStillPress` dependía de `isScrollingNotifier` (el scroll gana el gesto apenas toca) y quedaba un dedo "fantasma" tras abrir el menú; ahora mira si la hoja se movió de verdad y limpia el seguimiento de dedos al abrir el menú. Verificado con la suite en la tablet.
- **21. Bugs de la primera prueba real de sync** (2026-11-21): borrados que no llegaban si el otro dispositivo reiniciaba la app (primer `changes()` de cada proceso ahora es listado completo), "Mi cuaderno" de ejemplo duplicado (se descarta si está intacto y la nube ya tiene cuadernos) y sync lenta (sube ~5 s después de guardar, consulta cada 45 s, al volver a primer plano, indicador en la barra, aviso "Actualizar" con el cuaderno abierto). Probado entre tablet y Linux.
- **1. Hojas, detalles** (rama `feat/hojas-3`): "Seleccionar todo" toma la hoja visible y "Seleccionar todo el cuaderno" carga las que faltan (progreso, cancelable, aviso con más de 60 hojas); el historial se poda por el fondo si fija más de 12 hojas lejanas. Ver docs/TECNICO.md.
- **19. Selección: resaltador y tocar afuera** (rama `feat/seleccion-2`): un toque elige un solo elemento (el de más arriba que se ve), tocar de nuevo en el mismo lugar alterna al de abajo (tinta, resaltador), tocar afuera deselecciona, y con tinta y resaltador mezclados la barrita ofrece "Solo resaltador" / "Solo tinta".
- **1. Hojas: arrastrar, deshacer y `.opennote`** (rama `feat/hojas-2`): mover hojas arrastrando el asa de la miniatura
  en el panel (dedo o lápiz; el menú "Mover antes / después" sigue); agregar, duplicar, mover y borrar hojas se deshacen
  y rehacen en el mismo historial (la hoja borrada vuelve con contenido, estilo, título y marcador); exportar el cuaderno
  entero como `.opennote` (ZIP con manifest) desde su menú e importarlo desde el "+" de la biblioteca. Detalle en docs/TECNICO.md.
- **20. Borrar releases viejos** (rama `feat/releases-viejos`): el workflow deja solo los últimos 2 `v1.0.<n>` (antes 5) (`tool/podar_releases.sh`, nunca borra el Latest ni el nuevo, tolera fallos). Ver docs/RELEASES.md.

- **1. Carga perezosa de hojas** (rama `feat/rendimiento-3`, 2026-11-20): el cuaderno se abre leyendo solo las hojas
  cercanas a la última vista (±2); `NotebookDoc` distingue hojas cargadas y no cargadas, el editor carga las del rango
  visible más un margen y suelta las lejanas (si no están sucias, ni seleccionadas, ni con foco, ni en el historial de
  deshacer) y el guardado nunca escribe una hoja sin cargar. Panel de hojas (miniaturas de disco), búsqueda, PDF y duplicar
  cuaderno funcionan sin cargar todo. Red de seguridad: `test/data/lazy_load_test.dart` (secuencias aleatorias contra
  un modelo de referencia) y `test/screens/lazy_notebook_test.dart` (30 hojas por la UI). Detalle en docs/TECNICO.md.

- **9. Capturas en el README** (rama `feat/capturas`): 3 capturas (cuaderno, panel de hojas, biblioteca) que se generan solas en la tablet con `tool/screenshots.sh`, desde "OpenNote Test" con datos de ejemplo (letra con la fuente Hershey Script). La compatibilidad con otras tablets quedó en docs/TECNICO.md ("Tablets y lápices"); falta probarla en otros equipos.

- **18. Aviso de actualización más amable** (rama `feat/aviso-actualizacion`): "Hay una versión nueva de OpenNote", "Tenés la X → nueva Y", novedades en viñetas sacadas de los merges a main (sin merges internos, tests ni metadatos), aclaración de que viene de GitHub y no toca los cuadernos, botones "Ahora no" / "Omitir esta versión" / "Actualizar" y el permiso de instalar explicado antes de ir a ajustes.

- **2. Capas (rama feat/seleccion)**: un solo orden de dibujo para trazos, textos, imágenes, notas y audios (campo `z` por elemento, guardado en cada hoja; archivos viejos cargan como se veían). Menú "Orden" en la barrita de selección: Traer al frente, Subir uno, Bajar uno, Enviar al fondo; subir/bajar salta al próximo elemento que se superpone con la selección; se puede deshacer. El resaltador se dibuja debajo de la tinta de la misma tanda de trazos. Lo nuevo y lo duplicado queda arriba.

- **16. Selección tipo AutoCAD (rama feat/seleccion)**: de izquierda a derecha, "ventana" (línea continua azul): solo lo que queda adentro; de derecha a izquierda, "captura" (punteada verde): todo lo que el recuadro toca, con intersección real con el recorrido del trazo.

- **10. Releases automáticas**: workflow de GitHub Actions en cada push a main (analyze, tests, APK firmado, GitHub Release `v1.0.<n>`). Los cambios solo de docs no disparan release. Ver docs/RELEASES.md.

- **8. Ícono nuevo**: opción A (hoja con esquina doblada y trazo de tinta), adaptativo con versión monocromática; fuentes en `docs/icon/`, se regenera con `tool/apply_icon.sh`.

- **11. La app busca actualizaciones sola** (rama `feat/updater`): al abrir (Android release, cada 24 h) consulta el último
  Release; si hay versión nueva avisa con las notas ("Más tarde" / "Omitir esta versión" / "Actualizar"), descarga el APK
  y abre el instalador. Menú ⋮ de la biblioteca: "Buscar actualizaciones" y interruptor automático. Ver docs/TECNICO.md.
- **3. El tecladito abre el teclado al tocarlo** y **5. Formato tipo Word** (rama `feat/texto`): el tecladito crea un renglón
  nuevo debajo de lo último visible (o arriba si está vacío) y abre el teclado; en modo texto lo reabre en el último bloque;
  los bloques vacíos se borran. Barra de formato (negrita, cursiva, subrayado, tachado, colores, título/subtítulo, listas,
  sangría, alineación), Ctrl+B/I/U y Tab / Shift+Tab. Sin flutter_quill: modelo propio (`rich_text.dart`) que dibujan igual
  editor, miniaturas, PNG y PDF. Los textos viejos se convierten solos.
- **13. Carpetas en la biblioteca** (rama `feat/carpetas`): carpetas anidadas (`Folder` en `NotesIndex.folders`, `Notebook.folder`),
  tarjetas de carpeta con cuántos cuadernos tienen, migas de pan y flecha para subir, atrás del sistema sube de a un nivel.
  "+" ofrece Cuaderno nuevo (en la carpeta actual) y Carpeta nueva. Mantener apretado: cuaderno o carpeta → "Mover a…"
  (árbol con "Inicio"); carpeta → Renombrar / Borrar (sacar los cuadernos a la carpeta de arriba, o borrar todo con
  segunda confirmación). Además se puede mover arrastrando (ver el punto de abajo); "Mover a…" sigue.
- **14. Búsqueda en la biblioteca**: campo arriba; busca por nombre de cuaderno y de carpeta en todas las carpetas, sin
  mayúsculas ni tildes, con la ruta como subtítulo. Al borrar el texto vuelve a la carpeta actual.
- **7. App renombrada a OpenNote** (nombre en la tablet y título; el id `com.apuntes.apuntes` no cambió).
- **12. Tests sin tocar la app real**: el build debug se instala como `com.apuntes.apuntes.test` ("OpenNote Test"); `run_tests.sh` verifica que la app real y sus datos sigan intactos (`BACKUP=1` además hace backup).
- **4. Fondo en milímetros reales de A4** (rama `feat/estilo-hoja`): 1 mm = 1000/210 unidades. Rayado 7 / 8 / 10 mm
  (por defecto 8) con margen rojo a 25 mm y primer renglón cerca de 25 mm; cuadriculado y puntos 5 / 7 mm
  (por defecto 5), centrados en la hoja. El espaciado se guarda por hoja (`spacing`, en mm; los archivos viejos
  cargan con el por defecto). Miniaturas, PNG y PDF usan el mismo dibujo; el PDF es A4 con la imagen llenando la
  página, así que al imprimir al 100 % salen milímetros reales. El texto con teclado se acomoda al renglón de SU hoja
  y la letra escala con el interlineado (8 mm ≈ como antes); los textos existentes no se mueven hasta que se editan.
- **6. Estilo de hoja**: el menú ⋮ tiene "Estilo de hoja" con fondo, color de papel, interlineado / cuadrícula,
  vista previa y "Aplicar a: Esta hoja / Todo el cuaderno" (por defecto todo; "todo" también cambia el estilo de las
  hojas nuevas). "Esta hoja" es la que se ve. Se sacaron de ahí "Agregar / Quitar la última hoja" (lo cubren el panel y
  el pull-to-add). El selector de fondo de la barra sigue cambiando solo la hoja visible.
- **Todo hojas, como Samsung Notes** (rama `feat/hojas`): el cuaderno es una tira continua de hojas.
  Contador "2 / 5" en el título, panel con una miniatura por hoja (agregar / duplicar / mover / borrar / marcar /
  renombrar), título y marcador por hoja en el panel y la búsqueda, PDF con una A4 por hoja con su fondo y papel,
  migración automática de las páginas viejas (con backup en `legacy_pages_backup/`).
  Almacenamiento: carpeta por cuaderno, archivo binario por hoja (~2 bytes/punto, zlib), guardado en segundo
  plano que escribe solo lo cambiado, escritura atómica. Detalle en el README.
