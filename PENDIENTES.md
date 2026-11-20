# Pendientes

Para hacer después de pasar la reorganización del código (rama `refactor/arquitectura`).

1. **Carga perezosa de hojas lejanas** (resto de "todo hojas", ver Hecho). Hoy se leen y se decodifican todas las
   hojas al abrir el cuaderno (en un isolate, sin trabar la pantalla) y el cuaderno vive entero en memoria.
   Por qué no se hizo: el editor, la selección, la tinta y el deshacer trabajan sobre un solo documento con
   coordenadas globales; cargar solo las hojas cercanas exige que el documento admita "hojas sin cargar"
   (marcador de posición, guardar sin pisarlas, buscar y exportar leyéndolas del disco).
   Medir primero con un cuaderno de 100+ hojas antes de complicarlo.
   - Guardar parte y codifica todo el documento aunque solo una hoja haya cambiado (solo se *escribe* lo cambiado):
     si pesa, llevar la cuenta de hojas tocadas y codificar solo esas.
   - Exportar/backup del cuaderno entero como un archivo `.opennote` (ZIP).
   - Mover hojas arrastrando en el panel (hoy: menú "Mover antes / después").
   - Las operaciones de hojas (agregar, duplicar, mover, borrar) no se pueden deshacer: vacían el historial.
2. **Capas al seleccionar**: menú "Orden" con Traer al frente, Subir uno, Bajar uno, Enviar al fondo.
   - Un solo orden para trazos, imágenes, notas y textos (hoy las imágenes quedan siempre debajo de la tinta).
   - "Subir/bajar uno" salta al siguiente elemento que se superpone con la selección.
   - El resaltador sigue por debajo de la tinta del mismo nivel.
3. **El tecladito abre el teclado al tocarlo**: crea un renglón nuevo debajo de lo último escrito en la parte visible; si ya estás en modo texto, vuelve a abrirlo.
5. **Barra de formato tipo Word** al escribir con teclado (con flutter_quill):
   negrita, cursiva, subrayado, tachado, color de texto, resaltado, tamaños (normal / título / subtítulo),
   listas con viñetas, numeradas y de tareas, sangría con Tab / Shift+Tab, alineación.
   Los textos existentes se convierten solos; búsqueda, PDF y miniaturas respetan el formato.
8. **Ícono nuevo** (hoy es el de Flutter por defecto): adaptativo de Android (fondo + figura, con versión
   monocromática para los íconos temáticos de Android 13+). Idea: una hoja con una esquina doblada y un trazo
   de tinta que la cruza, en los colores del tema. Mostrar 2–3 opciones antes de elegir.
9. **README del proyecto** piola: qué es, capturas/GIF, funciones, cómo instalar (APK de Releases),
   cómo compilar, arquitectura (capas), cómo contribuir, plantillas de issues (bug / idea), licencia.
   Decidido: licencia **MIT** (agregar LICENSE); el usuario hace público el repo. Play Store queda para más adelante.
   Sección **Compatibilidad** en el README: investigar si anda igual en toda la gama Galaxy Tab S (S6 Lite, S7–S11, FE,
   Ultra) o hay que cambiar código. A revisar: cómo reporta cada modelo el botón del S Pen, pantallas/resoluciones
   (Ultra 14,6"), 60 vs 120 Hz, versiones de Android (minSdk), escritura a mano en campos de texto de Android 14+,
   y otras tablets con lápiz USI (Lenovo, etc.). Hasta ahora solo probado en Tab S6 Lite (SM-P620, Android 16).
10. **Compilación automática en cada commit a main** (GitHub Actions): `flutter analyze` + tests de PC,
    build del APK firmado y publicación como GitHub Release (`v1.0.<n>`, versionCode = número de build).
    Clave de firma propia guardada como secreto del repo (+ copia del usuario). El cambio de firma exige
    desinstalar una vez: hacerlo con backup y restauración.
11. **La app busca actualizaciones sola**: al abrir y cada 24 h consulta el último Release; si hay versión nueva
    muestra un aviso con los cambios, descarga el APK y abre el instalador (un toque).
    Permiso REQUEST_INSTALL_PACKAGES; opción en ajustes para desactivarlo. Android no permite instalación
    100 % silenciosa fuera de Play Store.

## Hecho

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
