# Apuntes

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

- `lib/model.dart`   — trazos, textos, páginas, cuadernos (+ JSON)
- `lib/storage.dart` — lectura/escritura de archivos
- `lib/painters.dart` — dibujo de hoja, tinta y trazo en vivo
- `lib/editor.dart`  — editor de página y barra de herramientas
- `lib/main.dart`    — app, menú de cuadernos, guardado
