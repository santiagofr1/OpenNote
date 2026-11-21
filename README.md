# OpenNote

**Tomá apuntes a mano en tu tablet, libre y sin ataduras.**

[![Release](https://img.shields.io/github/v/release/santiagofr1/OpenNote?color=brightgreen)](https://github.com/santiagofr1/OpenNote/releases/latest)
[![Workflow de release](https://github.com/santiagofr1/OpenNote/actions/workflows/release.yml/badge.svg)](https://github.com/santiagofr1/OpenNote/actions/workflows/release.yml)
[![Licencia: MIT](https://img.shields.io/badge/licencia-MIT-blue.svg)](LICENSE)
[![PRs bienvenidos](https://img.shields.io/badge/PRs-bienvenidos-brightgreen.svg)](CONTRIBUTING.md)
[![Plataforma: Android](https://img.shields.io/badge/plataforma-Android-3DDC84.svg?logo=android&logoColor=white)](https://github.com/santiagofr1/OpenNote/releases/latest)
[![Hecho con Flutter](https://img.shields.io/badge/hecho%20con-Flutter-02569B.svg?logo=flutter&logoColor=white)](https://flutter.dev)

OpenNote es una app de apuntes a mano con S Pen (y también con teclado) para tablets Android. Nació como
alternativa a Samsung Notes, que solo funciona en Samsung y no te deja usar tus apuntes en otro lado.
Es gratis, es de código abierto, funciona sin conexión y tus apuntes son tuyos: se guardan en tu tablet,
sin cuentas ni servidores.

## Qué tiene

- **Escritura con presión**: el trazo engrosa o se afina según cuánto apretás el lápiz.
- **Puntas y colores**: bolígrafo, pluma, lápiz, fibra y caligrafía, más resaltador, con paleta propia y grosores a elección.
- **Borrador en el botón**: apretá el botón del S Pen para borrar. Hay tres tamaños de goma.
- **Texto con formato**: tocá el tecladito y se abre un renglón nuevo con negrita, cursiva, subrayado, colores,
  títulos, listas, sangría y alineación.
- **Selección tipo AutoCAD**: arrastrando hacia la derecha tomás lo que queda adentro del recuadro; hacia la
  izquierda, todo lo que el recuadro toca. Después podés mover, copiar, duplicar o eliminar.
- **Orden de capas**: traer al frente, subir, bajar o enviar al fondo lo seleccionado. Se puede deshacer.
- **Imágenes, notas adhesivas y audios**: insertalos dentro de la hoja, junto con la tinta.
- **Cuadernos como tira de hojas**: deslizás de una hoja a otra y el título muestra cuál estás viendo (por
  ejemplo, "2 / 5"). Agregá, duplicá, movés, borrás, marcá o renombrá hojas desde el panel de miniaturas.
- **Fondos en medidas reales de A4**: rayado de 7, 8 o 10 mm, cuadriculado o puntos. Si imprimís al 100 %, sale a
  tamaño real.
- **Estilo por hoja o por cuaderno**: elegí el fondo, el color de papel y el interlineado.
- **Biblioteca ordenada**: carpetas anidadas, favoritos, búsqueda por nombre sin importar mayúsculas ni tildes,
  y cuadernos protegidos con PIN.
- **Modo lectura**: para leer sin tocar nada por error.
- **Exportar e importar**: exportá cuadernos a PDF o PNG, e importá PDF, imágenes y audios.
- **Aspecto Material You**: sigue el tema de tu tablet.
- **Rápida con cuadernos grandes**: ver [Rendimiento](#rendimiento-medido).

## Capturas

<table>
  <tr>
    <td align="center"><img src="docs/img/01_cuaderno.png" width="260" alt="Un cuaderno de Física con escritura a mano, un diagrama de una lente, resaltador y una nota adhesiva"><br><sub><b>Cuaderno</b>: escritura a mano con presión, texto con teclado, resaltador y notas.</sub></td>
    <td align="center"><img src="docs/img/02_panel_hojas.png" width="260" alt="El panel de hojas con las miniaturas de cada hoja del cuaderno"><br><sub><b>Panel de hojas</b>: miniaturas para saltar, mover o marcar cada hoja.</sub></td>
    <td align="center"><img src="docs/img/03_biblioteca.png" width="260" alt="La biblioteca con carpetas y cuadernos"><br><sub><b>Biblioteca</b>: carpetas, favoritos y miniaturas de tus cuadernos.</sub></td>
  </tr>
</table>

## Instalación

### Desde el APK (lo más fácil)

1. Bajá el archivo `.apk` de la [última release](https://github.com/santiagofr1/OpenNote/releases/latest).
2. Abrilo desde tu tablet. Si Android lo pide, habilitá **"Instalar apps desconocidas"** para el navegador o el
   gestor de archivos que uses.
3. Seguí los pasos del instalador.

La app se actualiza sola: al abrirla busca una versión nueva en GitHub, te muestra las novedades y te pregunta si
querés instalarla. Nunca toca tus cuadernos.

> Si ya instalaste una versión compilada por vos (firmada con la clave de debug), la primera release firmada con la
> clave oficial no se puede instalar encima. Hacé un backup de tus cuadernos, desinstalá OpenNote una vez e instalá
> el APK. Después, las actualizaciones son normales. Detalles en [docs/RELEASES.md](docs/RELEASES.md).

### Desde el código

Necesitás [Flutter](https://flutter.dev) en canal *stable*:

```sh
git clone https://github.com/santiagofr1/OpenNote
cd OpenNote
flutter pub get
flutter run                # en una tablet o emulador conectado
flutter build apk          # genera el APK en build/app/outputs/flutter-apk/
```

Para compilar para la tablet hacen falta también el Android SDK y JDK 21. Los pasos completos están en
[CONTRIBUTING.md](CONTRIBUTING.md).

## Uso

- **Escribir**: usá el S Pen para escribir. Con el dedo te desplazás por la hoja, y pellizcás para hacer zoom.
  Podés bloquear el zoom si te molesta.
- **Borrar**: apretá el botón del S Pen mientras pasás la punta por la tinta.
- **Texto**: tocá el tecladito de la barra para abrir un renglón nuevo y escribir con teclado.
- **Hojas**: deslizá entre hojas. Al final de la página, tirá hacia arriba y mantené hasta que se llene el círculo
  para agregar una hoja nueva. El panel de hojas te muestra todas en miniatura.
- **Cuadernos**: desde la biblioteca, el "+" crea un cuaderno nuevo (en la carpeta en la que estás) o una carpeta.
  Mantené apretado un cuaderno o una carpeta para elegir "Mover a…".

## Compatibilidad

OpenNote fue probado en una **Samsung Galaxy Tab S6 Lite (SM-P620) con Android 16** y el S Pen.

Debería funcionar en otras tablets Android con lápiz activo, como la gama Galaxy Tab S o tablets con lápiz USI,
pero todavía no las probamos. Si tenés una y la probás, contanos en un issue: sirve mucho saber qué anda y qué no.

## Rendimiento medido

Medimos OpenNote contra Samsung Notes en la misma Galaxy Tab S6 Lite, con una nota de 34 hojas abierta:

| Métrica | OpenNote | Samsung Notes |
|---|---|---|
| RAM con la nota abierta | **234 MB** | 673 MB |
| Tamaño en disco | **3,8 MB** | 24 MB |
| Frames lentos al desplazar | 1,1 % | **0,4 %** |
| Frame más lento del 1 % peor (p99) | **8 ms** | 19 ms |
| Abrir un cuaderno de 400 hojas | ~0,4 s | — |
| Guardar tras un trazo | ~0,1 s | — |

Son mediciones propias, hechas con `tool/perf.sh` y `tool/comparar.sh`. Podés correrlas en tu tablet para comprobarlas.

## Cómo está armado

```
lib/
├── domain/      # datos puros, sin Flutter: hojas, trazos, z-order, mallas, cuadernos, carpetas, herramientas
├── data/        # almacenamiento por hoja (binario + zlib), guardado en segundo plano, carga perezosa, export
├── rendering/   # dibujo de trazos como mallas, papel, imágenes de hojas por franjas
├── editor/      # editor, herramientas, selección, historial, texto, zoom, barra
├── screens/     # biblioteca, cuaderno abierto, panel de hojas, búsqueda y menús
├── widgets/     # diálogos y piezas compartidas
└── theme/       # tema y colores
integration_test/  # suite completa en tablet (app_test.dart) y medición de rendimiento (perf_test.dart)
tool/              # scripts: perf, comparación con Samsung Notes, capturas, ícono, trazas
docs/              # documentación técnica (TECNICO.md), releases, capturas e ícono
```

Cada capa usa solo las de arriba: `domain` no sabe nada de Flutter, y el resto se apoya en él. El detalle del
formato de archivos, la carga perezosa y el guardado está en [docs/TECNICO.md](docs/TECNICO.md).

## Es tuyo también: forkealo, rompelo, mejoralo

OpenNote es **software libre** bajo licencia MIT. Lo podés usar, copiar, modificar y redistribuir como quieras.

El software libre funciona porque la gente se anima a meter mano. No hace falta ser experto en Flutter ni pedir permiso:

- **Forkealo** y hacé tu propia versión: otra paleta, otras puntas, otro estilo de hoja. Si sale algo lindo, contalo.
- **Mandá un PR**, por chico que sea. Arreglar un texto, sumar un fondo o probar un test cuenta igual.
- **Abrí un issue** si algo no anda en tu tablet o con tu lápiz. Con tantos modelos y marcas distintas, tu reporte
  es lo que hace que funcione para todos.
- **Proponé ideas**: [Nuevo issue](https://github.com/santiagofr1/OpenNote/issues/new/choose) tiene plantillas para
  reportar un error y para proponer una mejora.

Algunas buenas primeras contribuciones:

- [ ] Probar OpenNote en otra tablet o con otro lápiz (USI, Galaxy Tab S más nueva) y reportar qué anda
      (ver "Tablets y lápices" en [docs/TECNICO.md](docs/TECNICO.md))
- [ ] Traducción al inglés de los textos de la interfaz (hoy está todo en español)
- [ ] Nuevos fondos o plantillas de hoja (`lib/domain/paper_layout.dart`, `lib/widgets/backgrounds.dart`)
- [ ] Nuevas puntas para el lápiz (`lib/domain/tools.dart`, dibujo en `lib/domain/stroke_mesh.dart`)
- [ ] Empaquetado para F-Droid
- [ ] App de PC: Flutter compila para Linux, Windows y macOS; falta resolver entrada con mouse y tableta, atajos y empaquetado (ver PENDIENTES.md)
- [ ] Más tests de lógica pura en `test/`

La guía para arrancar está en [CONTRIBUTING.md](CONTRIBUTING.md).

## Licencia

[MIT](LICENSE). Hacé lo que quieras con el código, solo mantené el aviso de copyright.
