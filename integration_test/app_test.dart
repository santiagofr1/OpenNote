// Tests de la app corriendo en la tablet.
// Cada test usa una carpeta temporal propia: NO toca los cuadernos reales.
//
//   flutter test integration_test -d <id de la tablet>

import 'dart:io';
import 'dart:ui' as ui;

import 'package:apuntes/app.dart';
import 'package:apuntes/data/export.dart';
import 'package:apuntes/data/media_import.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:printing/printing.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUp(() async => root = await Directory.systemTemp.createTemp('apuntes_test'));
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  // ---------------- ayudas ----------------
  Future<void> settle(WidgetTester t, [int ms = 400]) async {
    for (var i = 0; i < ms ~/ 50; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> start(WidgetTester t) async {
    await t.pumpWidget(ApuntesApp(root: root));
    await settle(t, 1500);
  }

  Future<void> createNotebook(WidgetTester t, String name) async {
    await t.tap(find.text('Nuevo cuaderno'));
    await settle(t);
    await t.enterText(find.byKey(const Key('askText')), name);
    await t.tap(find.byKey(const Key('askOk')));
    await settle(t, 1500);
  }

  PageEditorState editor(WidgetTester t) => t.state<PageEditorState>(find.byType(PageEditor));

  /// centro de la hoja visible, en coordenadas de pantalla
  Offset sheetCenter(WidgetTester t) => t.getCenter(find.byType(PageEditor));

  Future<void> stylusLine(WidgetTester t, Offset a, Offset b) async {
    final g = await t.createGesture(kind: PointerDeviceKind.stylus);
    await g.down(a);
    for (var i = 1; i <= 12; i++) {
      await g.moveTo(Offset.lerp(a, b, i / 12)!);
      await t.pump(const Duration(milliseconds: 8));
    }
    await g.up();
    await settle(t, 200);
  }

  Future<void> openMore(WidgetTester t, String label) async {
    await t.tap(find.byKey(const Key('more')));
    await settle(t);
    await t.tap(find.text(label));
    await settle(t, 600);
  }

  Future<void> tapMoreIcon(WidgetTester t, String value) async {
    await t.tap(find.byKey(const Key('more')));
    await settle(t);
    await t.tap(find.byKey(Key('more-$value')));
    await settle(t, 600);
  }

  Future<Notebook> savedNotebook(String name) async {
    final s = Storage(root: root);
    await s.init();
    return (await s.loadIndex()).notebooks.firstWhere((n) => n.name == name);
  }

  Future<File> fakeImage(int w, int h) async {
    final rec = ui.PictureRecorder();
    ui.Canvas(rec).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = const Color(0xFF3B82F6));
    final img = await rec.endRecording().toImage(w, h);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('${root.path}/foto.png');
    await f.writeAsBytes(png!.buffer.asUint8List());
    return f;
  }

  // ---------------- tests ----------------
  testWidgets('biblioteca: crear cuaderno, nombre arriba, volver guarda lo escrito', (t) async {
    await start(t);
    expect(find.text('Cuadernos'), findsOneWidget);
    await createNotebook(t, 'Física');

    // adentro: el nombre siempre arriba a la izquierda
    expect(find.byKey(const Key('nbTitle')), findsOneWidget);
    expect((t.widget(find.byKey(const Key('nbTitle'))) as Text).data, 'Física');

    final c = sheetCenter(t);
    await stylusLine(t, c, c + const Offset(200, 40));
    expect(editor(t).page.strokes.length, 1);

    // volver: guarda y muestra la biblioteca
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
    expect(find.byKey(const Key('nb-Física')), findsOneWidget);
    final nb = await savedNotebook('Física');
    final s = Storage(root: root);
    await s.init();
    expect((await s.loadPage(nb.pages.first.id)).strokes.length, 1, reason: 'el trazo quedó guardado en disco');
  });

  testWidgets('modo lectura: el lápiz no dibuja', (t) async {
    await start(t);
    await createNotebook(t, 'Lectura');
    await t.tap(find.byKey(const Key('reading')));
    await settle(t);
    final c = sheetCenter(t);
    await stylusLine(t, c, c + const Offset(150, 0));
    expect(editor(t).page.strokes, isEmpty);
    await t.tap(find.byKey(const Key('reading')));
    await settle(t);
    await stylusLine(t, c, c + const Offset(150, 0));
    expect(editor(t).page.strokes.length, 1);
    // salir: que el guardado termine antes de que el test borre su carpeta
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
  });

  testWidgets('panel de páginas: contador, agregar página y marcador', (t) async {
    await start(t);
    await createNotebook(t, 'Panel');
    await t.tap(find.byKey(const Key('pagesBtn')));
    await settle(t, 600);
    expect(find.byKey(const Key('pagesPanel')), findsOneWidget);
    expect(find.byKey(const Key('thumb-1')), findsOneWidget);

    await t.tap(find.byKey(const Key('addPage')));
    await settle(t, 800);
    expect(find.byKey(const Key('thumb-2')), findsOneWidget);
    final counter = t.widget<Text>(find.byKey(const Key('pageCounter')));
    expect(counter.textSpan!.toPlainText(), '2 / 2');

    // volver a la primera tocando su miniatura
    await t.tap(find.byKey(const Key('thumb-1')));
    await settle(t, 600);
    expect(t.widget<Text>(find.byKey(const Key('pageCounter'))).textSpan!.toPlainText(), '1 / 2');

    // marcador
    await t.tap(find.descendant(of: find.byKey(const Key('thumb-2')), matching: find.byType(IconButton)));
    await settle(t, 600);
    expect((await savedNotebook('Panel')).pages[1].bookmark, isTrue);
  });

  testWidgets('nota adhesiva y búsqueda', (t) async {
    await start(t);
    await createNotebook(t, 'Notas');
    await t.tap(find.byKey(const Key('insert')));
    await settle(t);
    await t.tap(find.text('Nota adhesiva'));
    await settle(t, 600);
    final items = editor(t).page.items.values;
    expect(items.length, 1);
    expect(items.first.type, 'sticky');

    // escribir en la nota (modo texto)
    await t.tap(find.byTooltip('Texto con teclado'));
    await settle(t);
    final field = find.descendant(of: find.byKey(ValueKey('sticky-${items.first.id}')), matching: find.byType(TextField));
    await t.enterText(field, 'Ley de Ohm: V = I·R');
    await settle(t, 600);
    expect(items.first.text, 'Ley de Ohm: V = I·R');

    // buscar
    await openMore(t, 'Buscar');
    await t.enterText(find.byKey(const Key('searchField')), 'ohm');
    await settle(t, 1000);
    expect(find.byKey(Key('hit-${items.first.id}')), findsOneWidget);
    await t.tap(find.byKey(Key('hit-${items.first.id}')));
    await settle(t, 800);
    expect(editor(t).selI, contains(items.first.id), reason: 'al tocar el resultado queda seleccionado');
  });

  testWidgets('insertar imagen (selector simulado) mantiene la proporción', (t) async {
    final img = await fakeImage(400, 300);
    Pickers.image = (_) async => img;
    await start(t);
    await createNotebook(t, 'Imágenes');
    await t.tap(find.byKey(const Key('insert')));
    await settle(t);
    await t.tap(find.text('Imagen'));
    await settle(t, 1200);
    final it = editor(t).page.items.values.single;
    expect(it.type, 'image');
    expect(it.h / it.w, closeTo(.75, .01));
    expect(await File('${root.path}/media/${it.file}').exists(), isTrue, reason: 'la imagen se copió a la carpeta del cuaderno');
  });

  testWidgets('estilo del cuaderno: fondo y papel en todas las páginas', (t) async {
    await start(t);
    await createNotebook(t, 'Estilo');
    await t.tap(find.byKey(const Key('pagesBtn')));
    await settle(t, 600);
    await t.tap(find.byKey(const Key('addPage')));
    await settle(t, 800);

    await openMore(t, 'Estilo del cuaderno');
    await t.tap(find.text('Cuadriculado'));
    await t.tap(find.byTooltip('Crema'));
    await settle(t);
    await t.tap(find.byKey(const Key('styleOk')));
    await settle(t, 1200);

    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
    final nb = await savedNotebook('Estilo');
    final s = Storage(root: root);
    await s.init();
    for (final ref in nb.pages) {
      final p = await s.loadPage(ref.id);
      expect(p.bg, 'grid');
      expect(p.paper, '#fbf3e0');
    }
  });

  testWidgets('favorito y bloqueo con PIN', (t) async {
    await start(t);
    await createNotebook(t, 'Secreto');
    await tapMoreIcon(t, 'fav');
    await tapMoreIcon(t, 'lock');
    await t.enterText(find.byKey(const Key('pinField')), '1234');
    await t.tap(find.byKey(const Key('pinOk')));
    await settle(t, 600);
    await t.enterText(find.byKey(const Key('pinField')), '1234');
    await t.tap(find.byKey(const Key('pinOk')));
    await settle(t, 600);

    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
    final nb = await savedNotebook('Secreto');
    expect(nb.favorite, isTrue);
    expect(nb.pin, hashPin('1234'));
    expect(find.byKey(Key('fav-${nb.id}')), findsOneWidget);

    // PIN incorrecto: no entra
    await t.tap(find.byKey(const Key('nb-Secreto')));
    await settle(t);
    await t.enterText(find.byKey(const Key('pinField')), '0000');
    await t.tap(find.byKey(const Key('pinOk')));
    await settle(t, 800);
    expect(find.byKey(const Key('nbTitle')), findsNothing);

    // PIN correcto: entra
    await t.tap(find.byKey(const Key('nb-Secreto')));
    await settle(t);
    await t.enterText(find.byKey(const Key('pinField')), '1234');
    await t.tap(find.byKey(const Key('pinOk')));
    await settle(t, 1200);
    expect(find.byKey(const Key('nbTitle')), findsOneWidget);
  });

  testWidgets('borrar el cuaderno desde ⋮ vuelve a la biblioteca', (t) async {
    await start(t);
    await createNotebook(t, 'Descartable');
    await tapMoreIcon(t, 'delete');
    await t.tap(find.byKey(const Key('confirmDelete')));
    await settle(t, 1200);
    expect(find.text('Cuadernos'), findsOneWidget);
    expect(find.byKey(const Key('nb-Descartable')), findsNothing);
  });

  testWidgets('zoom con dos dedos y candado', (t) async {
    await start(t);
    await createNotebook(t, 'Zoom');
    final ed = editor(t);
    ed.widget.tools.zoom = 1;
    ed.widget.tools.zoomLocked = false;
    final c = sheetCenter(t);

    Future<void> pinch(double from, double to) async {
      final a = await t.createGesture(kind: PointerDeviceKind.touch);
      final b = await t.createGesture(kind: PointerDeviceKind.touch);
      await a.down(c - Offset(from, 0));
      await t.pump(const Duration(milliseconds: 30));
      await b.down(c + Offset(from, 0));
      for (var i = 1; i <= 10; i++) {
        final d = from + (to - from) * i / 10;
        await a.moveTo(c - Offset(d, 0));
        await b.moveTo(c + Offset(d, 0));
        await t.pump(const Duration(milliseconds: 16));
      }
      await a.up();
      await b.up();
      await settle(t, 300);
    }

    await pinch(100, 200);
    expect(ed.widget.tools.zoom, closeTo(2, .15), reason: 'separar los dedos agranda');

    // candado: pellizcar ya no cambia el zoom
    await t.tap(find.byTooltip('Fijar el zoom'));
    await settle(t);
    final fixed = ed.widget.tools.zoom;
    await pinch(200, 100);
    expect(ed.widget.tools.zoom, fixed);
    expect(find.byKey(const Key('nbTitle')), findsOneWidget, reason: 'mantener dos dedos no abre el menú de pegar');
    expect(find.text('Pegar acá'), findsNothing);
  });

  testWidgets('PDF: una hoja A4 por cada hoja de cada página', (t) async {
    final s = Storage(root: root);
    await s.init();
    final p1 = PageData(newId('p'), h: heightFor(2)); // 2 hojas
    final p2 = PageData(newId('p')); // 1 hoja
    p1.texts['t1'] = TextBlock('t1', 90, 44, 800, 'Hola PDF');
    await s.savePage(p1);
    await s.savePage(p2);
    final nb = Notebook(newId('n'), 'PDF', [PageRef(p1.id, 'a'), PageRef(p2.id, 'b')]);
    final bytes = await buildNotebookPdf(s, nb);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    final pages = await Printing.raster(bytes, dpi: 20).toList();
    expect(pages.length, 3);
    expect(pages.first.width / pages.first.height, closeTo(210 / 297, .02), reason: 'tamaño A4');
  });
}
