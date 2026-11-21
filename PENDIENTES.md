# Pendientes

1. **Hojas, detalles** (rendimiento hecho y medido, ver Hecho y docs/TECNICO.md; falta medir en la tablet la RAM tras
   desplazar con el presupuesto nuevo del caché de imágenes, objetivo < ~400 MB):
   - "Seleccionar todo" solo toma lo de las hojas cargadas (decidido a propósito).
   - Si el historial de deshacer es largo, las hojas que toca no se sueltan (seguridad primero): se podría podar
     el historial por hojas lejanas si pesa en cuadernos enormes.
17. **App de PC + sincronización (A INVESTIGAR, no implementar todavía)**:
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
20. **Borrar releases viejos de GitHub** (pedido del usuario, 2026-11-20): cada push a main crea un Release `v1.0.<n>`
    con su APK y se acumulan. Que el workflow, después de publicar, borre los viejos y deje solo los últimos N
    (p. ej. 5) con `gh release delete --cleanup-tag`. La app busca solo el último, así que no rompe el aviso.
15. **LaTeX**: lo hace el usuario; no tocar.

## Hecho

- **19. Selección: resaltador y tocar afuera** (rama `feat/seleccion-2`): un toque elige un solo elemento (el de más arriba que se ve), tocar de nuevo en el mismo lugar alterna al de abajo (tinta, resaltador), tocar afuera deselecciona, y con tinta y resaltador mezclados la barrita ofrece "Solo resaltador" / "Solo tinta".
- **1. Hojas: arrastrar, deshacer y `.opennote`** (rama `feat/hojas-2`): mover hojas arrastrando el asa de la miniatura
  en el panel (dedo o lápiz; el menú "Mover antes / después" sigue); agregar, duplicar, mover y borrar hojas se deshacen
  y rehacen en el mismo historial (la hoja borrada vuelve con contenido, estilo, título y marcador); exportar el cuaderno
  entero como `.opennote` (ZIP con manifest) desde su menú e importarlo desde el "+" de la biblioteca. Detalle en docs/TECNICO.md.
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
