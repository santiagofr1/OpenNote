# Cómo contribuir a OpenNote

¡Gracias por meter mano! Cualquier aporte suma: código, issues, ideas, documentación, pruebas en otras tablets
o traducciones.

## Arrancar

```sh
git clone https://github.com/<tu-usuario>/OpenNote   # tu fork
cd OpenNote
flutter pub get            # instala dependencias
flutter run                # corre la app en una tablet o emulador conectado
flutter test               # tests de lógica pura, en la PC
```

Necesitás Flutter en canal *stable*. Para compilar para la tablet también hacen falta el Android SDK y
JDK 21 (con `JAVA_HOME` apuntando a él).

## Ramas

- **`main`**: lo que se publica. Cada push compila y saca una release (APK, `.deb` y `.exe`), así que solo recibe
  merges desde `dev`.
- **`dev`**: funciones ya probadas en la tablet. Cuando se juntan un par, `dev` se mergea a `main`.
- **Ramas de trabajo** (`feat/…`, `fix/…`): salen de `dev` y vuelven a `dev`. **Los PR van contra `dev`**, no contra
  `main`. Una vez mergeadas se borran.

## Antes de mandar un PR

- `flutter analyze` sin avisos nuevos. Si tu cambio agrega un aviso, arreglalo antes de pedir revisión.
- `flutter test` tiene que quedar en verde.
- **No corras `dart format`.** El repo se escribe a unas 120 columnas y no usa formatter: correrlo reformatea
  archivos enteros y ensucia el diff. Mantené el estilo del código que ya hay alrededor.
- Un PR por tema. Si es un cambio grande (una función nueva, algo que toque mucha arquitectura), conviene abrir un
  issue antes para charlarlo.
- Si tocás la interfaz o el lápiz, probalo en una tablet real y decilo en el PR. La plantilla de PR tiene un checklist
  para eso.

## Tests en la tablet

```sh
./run_tests.sh             # suite de integración en la tablet conectada por adb
BACKUP=1 ./run_tests.sh    # igual, pero además baja una copia de tus cuadernos reales
```

`./run_tests.sh` instala una app aparte, **"OpenNote Test"** (`com.apuntes.apuntes.test`), con sus propios datos.
Nunca toca la app real ni tus cuadernos: al final verifica que la app real y sus archivos sigan iguales.

Regla para las funciones nuevas: **cada función nueva suma un caso a `integration_test/app_test.dart`.** Si hace
falta, también agregá un test de lógica pura en `test/`.

## Sincronización con Google Drive

La sincronización usa un proyecto de Google Cloud del dueño del repositorio. Sus IDs de cliente **no están en el repo**:
los pasa el workflow de release desde secretos. Si hacés un fork y querés probar la sync (o publicar tu propia
versión), necesitás **tu propio proyecto de Google Cloud**: los pasos están en
[docs/SINCRONIZACION.md](docs/SINCRONIZACION.md), "Configurar Google Cloud". Copiá `google_config.example.json` a
`google_config.json` (está en el `.gitignore`) y corré con `--dart-define-from-file=google_config.json`. Sin esos
datos la app compila y anda igual, solo que "Conectar con Google" avisa que falta configurar. Los tests de la
sincronización (`test/sync/`) usan un remoto falso en memoria y no necesitan nada de Google.

## Rendimiento

Si tu cambio puede afectar la velocidad o la memoria (dibujo, carga, guardado, scroll), medilo:

- `tool/perf.sh`: mide cuadernos de 50, 100, 200 y 400 hojas en la tablet (tarda unos 15-25 minutos).
  `SIZES=100,200 tool/perf.sh` corre solo esos tamaños.
- `tool/comparar.sh`: compara la app con Samsung Notes en la tablet, con un cuaderno de 34 hojas.

Pegá los números antes y después en el PR.

## Dónde está cada cosa

```
lib/domain/      datos puros sin Flutter: hojas, trazos, cuadernos, carpetas, herramientas (con tests)
lib/sync/        sincronización con Google Drive: motor, remoto falso, Drive, login
lib/data/        almacenamiento (Storage), formato binario, migración, exportar PDF/PNG, importar
lib/rendering/   dibujo de trazos (mallas), papel, hojas completas, capas del editor
lib/editor/      editor de la tira de hojas, entrada del lápiz, selección, deshacer, zoom, barra
lib/screens/     biblioteca y cuaderno abierto
lib/widgets/     diálogos compartidos
lib/theme/       tema y colores
```

Cada capa usa solo las de arriba. Si una lógica puede ir en `lib/domain/` sin depender de Flutter, ponela ahí y
cubrila con tests.

## Estilo

- Los comentarios y los textos de la interfaz van en **español**.
- Seguí las reglas de `analysis_options.yaml`.
- Cambios chicos y enfocados: un PR, un tema.

## Reportar un bug

Usá la [plantilla de reporte de error](https://github.com/santiagofr1/OpenNote/issues/new/choose). Contá:

- **Modelo de tablet** (por ejemplo, Galaxy Tab S6 Lite SM-P620) y **lápiz** (S Pen, USI u otro).
- **Versión de Android**.
- **Versión de OpenNote**: el tag de la release (por ejemplo, `v1.0.42`) o el commit si lo compilaste vos.
- Qué hiciste, qué esperabas y qué pasó. Si se cayó, decinos si fue al abrir un cuaderno o al escribir.

## Licencia

Al contribuir aceptás que tu aporte se publique bajo la licencia [MIT](LICENSE) del proyecto.
