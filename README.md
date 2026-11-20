# Apuntes

App de apuntes a mano (S Pen) y con teclado. Flutter: Android (tablet) y Linux (PC).

- El lápiz dibuja (con presión), el dedo scrollea, el botón del S Pen borra.
- Cada cuaderno es una tira continua de hojas A4 (como Samsung Notes): se scrollea de una a otra,
  el título muestra "2 / 5" y el panel lateral tiene una miniatura por hoja.
- Todo se guarda local, una carpeta por cuaderno y un archivo por hoja (ver "Almacenamiento").

## Compilar e instalar en la tablet

```
./build_install.sh
```

Requiere Flutter en `~/flutter`, Android SDK en `~/Android/Sdk` y JDK 21 en `~/Android/jdk21`.

## Código

Por capas (cada una usa solo las de arriba):

- `lib/domain/`    — datos puros: medidas de la hoja, trazos, cuadernos (`Notebook`, `SheetMeta`), el cuaderno abierto
  en memoria (`NotebookDoc`, con las operaciones de hojas) y herramientas
- `lib/data/`      — archivos (`Storage`, códec binario `sheet_codec`, migración), exportar PDF/PNG, importar imágenes/audio/PDF
- `lib/rendering/` — dibujo de trazos, papel, hojas completas (miniaturas y PDF) y capas del editor
- `lib/editor/`    — editor del cuaderno (toda la tira): `page_editor.dart` coordina; entrada del lápiz (`ink`),
  selección, deshacer (`history`), textos, elementos, zoom (`viewport`, `touch_gestures`),
  tirar para agregar hoja, barra acoplable (`dock_layout`, `toolbar`) y menús
- `lib/screens/`   — biblioteca y cuaderno abierto (panel de hojas, búsqueda, estilo, menús)
- `lib/widgets/`, `lib/theme/` — diálogos compartidos y tema
- `lib/main.dart`, `lib/app.dart` — arranque

## Almacenamiento (formato 3)

```
apuntes/index.json                          cuadernos: id, nombre, favorito, PIN, fondo y papel por defecto, última hoja  ("format": 3)
apuntes/notebooks/<cuaderno>/notebook.json  orden de las hojas: id, título, marcador, fondo, papel, rev, updated
apuntes/notebooks/<cuaderno>/sheets/<hoja>.sheet   contenido de cada hoja (binario)
apuntes/media/                              imágenes y audios (compartidos por todos los cuadernos)
apuntes/prefs.json                          herramientas
```

- En memoria el cuaderno es un solo `NotebookDoc`: trazos, textos y elementos en coordenadas globales de la tira
  (la hoja `k` ocupa `y` de `k * kSheetStep` a `k * kSheetStep + kSheetH`). Cada elemento pertenece a la hoja
  que contiene su borde de arriba. Al guardar se parte por hoja (coordenadas locales) y al leer se rearma.
- `.sheet`: `"ONS"` + versión + zlib( JSON con textos, elementos y atributos de trazos + los puntos ).
  Puntos: x e y enteros en décimas, primero en zigzag-varint y después delta de delta, presión en 1 byte.
  Una hoja llena de letra ronda 2 bytes por punto (unas 10 veces menos que el JSON anterior).
- Guardar codifica las hojas en otro isolate y escribe solo las que cambiaron (compara un hash con el
  último guardado) más `notebook.json` si cambió algo de las hojas; las borradas se eliminan. Escritura atómica
  (temporal + rename), guardados de un mismo cuaderno de a uno y juntados.
- Migración automática al leer el índice viejo (`pages/<id>.json`): cada página se aplana en sus hojas
  (el título de la página pasa a la primera hoja, salvo "Primera página" / "Página N" / la fecha por defecto).
  `pages/` queda en `legacy_pages_backup/`. Si se corta, se rehace desde cero (el índice nuevo se escribe al final).

## Tests

- `flutter test test/` — lógica pura, en la PC (no necesita la tablet).
- `./run_tests.sh` — tests de integración en la tablet (hace backup de los cuadernos).
