# Pendientes

17. **App de PC + sincronización** (rama `feat/drive-sync`). **DECIDIDO (2026-11-21): sincronización por Google Drive**
    (permiso `drive.file`, carpeta `OpenNote`; tablet y Linux se conectan una vez con Google). Diseño en
    docs/SINCRONIZACION.md, "Decisión: Google Drive". **Avance:** motor testeable sin Google (`lib/sync/`, remoto
    falso, tests en `test/sync/`), remoto de Drive (`googleapis` v3), login (Android `google_sign_in`, Linux
    `googleapis_auth` con PKCE), pantalla en el menú ⋮ de la biblioteca, workflow de release con los IDs desde secretos.
    **Hecho también:** proyecto de Google Cloud `opennote-515407` (en producción, permiso no sensible), clientes OAuth y secretos cargados; probado de verdad entre la tablet y Linux (subir, bajar, borrar). **Falta:** cliente Android de la app real (necesita el SHA-1 del keystore de release), segundo plano, cifrado de extremo a extremo. **Hecho:** app de Linux empaquetada como `.deb` (`tool/build_deb.sh`, job `linux` del release, repo apt `santiagofr1/apt`); falta probar la instalación en una máquina limpia y agregar `santiagofr1/OpenNote` a `apps.txt` del repo apt. Lo que sigue es la investigación original:
    - PC: Flutter desktop compila el mismo código para Linux, Windows y macOS. Investigar qué cambia: entrada
      (mouse/teclado y tabletas Wacom en PC), atajos de teclado, rutas de datos, empaquetado (AppImage/Flatpak/.deb,
      instalador .msi/MSIX en Windows).
    - Sincronizar en la LAN sin que otros en la misma red vean nada: emparejar una sola vez escaneando un QR
      (como KDE Connect / Syncthing). Cada dispositivo tiene su propia clave; el QR lleva la huella de la clave del otro,
      y después todo va por TLS mutuo con certificados fijados. Un dispositivo no emparejado no puede ni conectarse.
      No hace falta Google Authenticator ni cuentas. Descubrimiento con mDNS. Revocar dispositivos desde ajustes.
    - Fuera de casa: opción por nube (Google Drive / WebDAV / Syncthing) con cifrado de extremo a extremo (la nube
      solo ve archivos cifrados).
    - Conflictos: el formato por hojas (una hoja = un archivo con rev/updated) ya ayuda; definir qué pasa si se
      edita la misma hoja en los dos lados (guardar las dos versiones, o fusionar trazos por id).
    Entregable: un documento comparando opciones (seguridad, comodidad, esfuerzo) y una recomendación.
    Investigación hecha: docs/SINCRONIZACION.md (rama `docs/sincronizacion`).
    **Idea que le interesa al usuario (2026-11-20): Google Drive como en Colab.** Conectar con Google una vez,
    la app crea una carpeta `OpenNote` en "Mi unidad" (permiso drive.file: solo ve lo que crea ella) y sube ahí
    solo las hojas que cambiaron (ya hay seguimiento de hojas sucias); la otra punta baja lo cambiado con la API de
    cambios de Drive. Conflicto en la misma hoja: guardar las dos versiones. La app de PC habla directo con Drive
    (en Linux no hay cliente oficial). Hace falta un proyecto de Google Cloud para el login; confirmar si drive.file
    exige verificación de Google. Orden: 1) Drive en la tablet, 2) app Linux, 3) en segundo plano, 4) cifrado opcional.
15. **LaTeX**: lo hace el usuario; no tocar.

## Hecho

- **21. Bugs de la primera prueba real de sync** (2026-11-21): borrados que no llegaban si el otro dispositivo reiniciaba la app (primer `changes()` de cada proceso ahora es listado completo), "Mi cuaderno" de ejemplo duplicado (se descarta si está intacto y la nube ya tiene cuadernos) y sync lenta (sube ~5 s después de guardar, consulta cada 45 s, al volver a primer plano, indicador en la barra, aviso "Actualizar" con el cuaderno abierto). Probado entre tablet y Linux.
- **1. Hojas, detalles** (rama `feat/hojas-3`): "Seleccionar todo" toma la hoja visible y "Seleccionar todo el cuaderno" carga las que faltan (progreso, cancelable, aviso con más de 60 hojas); el historial se poda por el fondo si fija más de 12 hojas lejanas. Ver docs/TECNICO.md.
- **19. Selección: resaltador y tocar afuera** (rama `feat/seleccion-2`): un toque elige un solo elemento (el de más arriba que se ve), tocar de nuevo en el mismo lugar alterna al de abajo (tinta, resaltador), tocar afuera deselecciona, y con tinta y resaltador mezclados la barrita ofrece "Solo resaltador" / "Solo tinta".
- **1. Hojas: arrastrar, deshacer y `.opennote`** (rama `feat/hojas-2`): mover hojas arrastrando el asa de la miniatura
  en el panel (dedo o lápiz; el menú "Mover antes / después" sigue); agregar, duplicar, mover y borrar hojas se deshacen
  y rehacen en el mismo historial (la hoja borrada vuelve con contenido, estilo, título y marcador); exportar el cuaderno
  entero como `.opennote` (ZIP con manifest) desde su menú e importarlo desde el "+" de la biblioteca. Detalle en docs/TECNICO.md.
- **20. Borrar releases viejos** (rama `feat/releases-viejos`): el workflow deja solo los últimos 5 `v1.0.<n>` (`tool/podar_releases.sh`, nunca borra el Latest ni el nuevo, tolera fallos). Ver docs/RELEASES.md.

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
  editor, miniaturas, PNG y PDF. Los textos viejos se convierten solos. Falta: selección que cruce párrafos con el dedo.
- **13. Carpetas en la biblioteca** (rama `feat/carpetas`): carpetas anidadas (`Folder` en `NotesIndex.folders`, `Notebook.folder`),
  tarjetas de carpeta con cuántos cuadernos tienen, migas de pan y flecha para subir, atrás del sistema sube de a un nivel.
  "+" ofrece Cuaderno nuevo (en la carpeta actual) y Carpeta nueva. Mantener apretado: cuaderno o carpeta → "Mover a…"
  (árbol con "Inicio"); carpeta → Renombrar / Borrar (sacar los cuadernos a la carpeta de arriba, o borrar todo con
  segunda confirmación). Mover arrastrando NO se hizo: choca con el long-press del menú y con el scroll; queda "Mover a…".
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
