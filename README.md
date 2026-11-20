# OpenNote

App de apuntes a mano (S Pen) y con teclado. Flutter: Android (tablet) y Linux (PC).

- El lápiz dibuja (con presión), el dedo scrollea, el botón del S Pen borra.
- Cuadernos y páginas guardados localmente como JSON (`index.json` + `pages/<id>.json`),
  con el mismo formato que la versión web, para sincronizar más adelante.

## Compilar e instalar en la tablet

```
./build_install.sh
```

Requiere Flutter en `~/flutter`, Android SDK en `~/Android/Sdk` y JDK 21 en `~/Android/jdk21`.

## Código

Por capas (cada una usa solo las de arriba):

- `lib/domain/`    — datos puros: medidas de la hoja, trazos, páginas, cuadernos, herramientas (+ JSON)
- `lib/data/`      — archivos (`Storage`), exportar PDF/PNG, importar imágenes/audio/PDF
- `lib/rendering/` — dibujo de trazos, papel, hojas completas (miniaturas y PDF) y capas del editor
- `lib/editor/`    — editor de página: `page_editor.dart` coordina; entrada del lápiz (`ink`),
  selección, deshacer (`history`), textos, elementos, zoom (`viewport`, `touch_gestures`),
  tirar para agregar hoja, barra acoplable (`dock_layout`, `toolbar`) y menús
- `lib/screens/`   — biblioteca y cuaderno abierto (panel de páginas, búsqueda, estilo, menús)
- `lib/widgets/`, `lib/theme/` — diálogos compartidos y tema
- `lib/main.dart`, `lib/app.dart` — arranque

## Tests

- `flutter test test/` — lógica pura, en la PC (no necesita la tablet).
- `./run_tests.sh` — tests de integración en la tablet. Corren con el build debug (`com.apuntes.apuntes.test`, "OpenNote Test"), otra app con datos propios; antes y después verifica que OpenNote y sus cuadernos sigan intactos. `BACKUP=1 ./run_tests.sh` baja además un backup a `~/apuntes_app_backup/`.
