# Cómo contribuir a OpenNote

¡Gracias por tu interés en OpenNote! Cualquier ayuda es bienvenida: reportar errores,
proponer ideas, mejorar la documentación o mandar código.

## Antes de empezar

- **Cambios grandes** (una función nueva, un cambio de arquitectura, algo que toque
  mucho código): abrí primero un *issue* con la idea para charlarla. Así no perdés
  tiempo en algo que quizás no encaja con el proyecto.
- **Cambios chicos** (un arreglo, un texto, una mejora puntual): podés ir directo a un PR.
- Si no sabés por dónde empezar, mirá `PENDIENTES.md`: tiene la lista de lo que viene.

## Flujo de trabajo

1. Hacé un *fork* del repositorio.
2. Creá una rama para tu cambio, con nombre descriptivo (por ejemplo `fix/borrador-trazos`
   o `feat/regla-cuadriculada`). No trabajes directo en `main`.
3. Hacé tus cambios en commits chicos, cada uno con un propósito claro.
4. Abrí un *Pull Request* contra `main` y completá la plantilla que aparece.

## Compilar y probar

Necesitás:

- **Flutter** en canal *stable*.
- **JDK 21**, apuntado con la variable `JAVA_HOME`.
- Android SDK, si vas a compilar para la tablet.

Comandos:

```
flutter pub get        # instala dependencias
flutter analyze        # análisis estático: tiene que salir sin errores
flutter test           # tests de lógica pura, en la PC (no necesita tablet)
./run_tests.sh         # tests de integración en un dispositivo Android
```

`./run_tests.sh` instala una app aparte llamada **"OpenNote Test"** (debug), así que
nunca toca tus cuadernos reales: el script verifica al final que la app real siga igual.
Con `BACKUP=1 ./run_tests.sh` además guarda una copia de tus cuadernos antes de correr.

Para compilar el APK e instalarlo en la tablet con `./build_install.sh` hacen falta Flutter, el Android
SDK y JDK 21 en las rutas que indica la documentación técnica. Los detalles de cada test y del
formato de archivos están en [docs/TECNICO.md](docs/TECNICO.md).

## Estilo de código

El código está separado en capas (la descripción completa está en
[docs/TECNICO.md](docs/TECNICO.md)). Cada capa usa solo las de arriba:

- `lib/domain/`    — datos puros y lógica sin Flutter (medidas, trazos, páginas, cuadernos, herramientas, JSON).
- `lib/data/`      — almacenamiento (`Storage`), exportar PDF/PNG, importar imágenes/audio/PDF.
- `lib/rendering/` — dibujo de trazos, papel, hojas y capas del editor.
- `lib/editor/`    — editor de página, entrada del lápiz, selección, deshacer, zoom, barra.
- `lib/screens/`   — biblioteca y cuaderno abierto.
- `lib/widgets/`, `lib/theme/` — diálogos compartidos y tema.

Otras reglas:

- Si una lógica puede ir en `lib/domain/` sin depender de Flutter, ponela ahí y cubrila con tests.
- Los comentarios y los textos de la interfaz van en **español**.
- Mantené los cambios chicos y enfocados: un PR, un tema.
- Seguí el estilo que ya hay en el código y las reglas de `analysis_options.yaml`.

## Antes de mandar el PR

- `flutter analyze` sin errores.
- `flutter test` en verde.
- Si tocás la interfaz o el lápiz, probalo en un dispositivo real y decilo en el PR.

Los PR solo se aceptan si **`flutter analyze` y los tests quedan en verde**.

## Licencia

Al contribuir aceptás que tu código se publique bajo la [licencia MIT](LICENSE) del proyecto.
