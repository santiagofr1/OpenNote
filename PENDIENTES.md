# Pendientes

Para hacer después de pasar la reorganización del código (rama `refactor/arquitectura`).

1. **Todo hojas, como Samsung Notes**: el cuaderno es una sola tira continua de hojas.
   - Contador "2 / 5" en el título que se actualiza al scrollear según la hoja visible.
   - Panel de páginas: una miniatura por hoja; agregar / duplicar / mover / borrar / marcar por hoja.
   - Nombre o marcador opcional por hoja (se ve en el panel y entra en la búsqueda).
   - Migración: las páginas viejas se aplanan en hojas seguidas, sin perder nada.
   - **Almacenamiento eficiente** (hacerlo junto con esto). Investigado:
     Samsung Notes (.sdocx) = ZIP con un `.page` binario por página + índice de orden + media/;
     Microsoft ISF (OneNote) = coordenadas enteras + delta de delta + compresión (1–2 bytes/punto);
     Xournal++ = un solo XML gzip que reescribe todo (lo que hay que evitar). Diseño:
     1. Cuaderno = carpeta: índice con orden de hojas + un archivo por hoja + media/; guardar solo la hoja tocada.
     2. Trazos en binario: x/y enteros (décimas), delta de delta zigzag-varint, presión 1 byte, zlib (dart:io).
        ~2 bytes/punto: hoja llena ~30–40 KB en vez de ~400 KB.
     3. Guardado en segundo plano (isolate), escritura atómica (tmp + rename).
     4. Carga perezosa: solo las hojas cerca de la vista.
     5. Exportar/backup del cuaderno entero como un archivo `.opennote` (ZIP).
     Conversión automática de lo existente.
2. **Capas al seleccionar**: menú "Orden" con Traer al frente, Subir uno, Bajar uno, Enviar al fondo.
   - Un solo orden para trazos, imágenes, notas y textos (hoy las imágenes quedan siempre debajo de la tinta).
   - "Subir/bajar uno" salta al siguiente elemento que se superpone con la selección.
   - El resaltador sigue por debajo de la tinta del mismo nivel.
3. **El tecladito abre el teclado al tocarlo**: crea un renglón nuevo debajo de lo último escrito en la parte visible; si ya estás en modo texto, vuelve a abrirlo.
4. **Fondo en milímetros reales de A4**: rayado 8 mm, cuadriculado 5 mm, puntos 5 mm, margen rojo 25 mm y margen superior.
   - En Configuración de página: interlineado 7 / 8 / 10 mm y cuadrícula 5 / 7 mm.
   - El texto con teclado se acomoda al renglón.
   - Al imprimir, elegir "tamaño real / 100 %".
5. **Barra de formato tipo Word** al escribir con teclado (con flutter_quill):
   negrita, cursiva, subrayado, tachado, color de texto, resaltado, tamaños (normal / título / subtítulo),
   listas con viñetas, numeradas y de tareas, sangría con Tab / Shift+Tab, alineación.
   Los textos existentes se convierten solos; búsqueda, PDF y miniaturas respetan el formato.
6. **Unificar "Estilo del cuaderno" y "Configuración de página"** en una sola opción del menú ⋮
   ("Estilo de hoja"): fondo, color de papel, interlineado / cuadrícula, con un selector
   "Aplicar a: esta hoja / todo el cuaderno" (por defecto, todo el cuaderno).
7. **Renombrar la app a OpenNote** (nombre en la tablet y título). El id del paquete no se toca para no perder datos.
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
12. **Tests sin tocar la app real**: `flutter test` desinstala la app al terminar (y Android borra sus datos).
    Usar un flavor `test` con otro applicationId (`com.apuntes.apuntes.test`) para que los tests se instalen
    como otra app; mientras tanto `run_tests.sh` hace backup y restaura (en una corrida el backup salió vacío:
    revisar y verificar la restauración al final del script).
