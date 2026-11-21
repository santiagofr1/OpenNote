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
import 'package:apuntes/editor/selection_menu.dart';
import 'package:apuntes/rendering/sheet_image_cache.dart';
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
  /// Mantener apretado de verdad: en la tablet `t.longPress` no espera tiempo real
  /// y a veces suelta antes de los 500 ms del long-press.
  Future<void> holdOn(WidgetTester t, Finder f) async {
    final g = await t.startGesture(t.getCenter(f));
    final end = DateTime.now().add(const Duration(milliseconds: 750));
    while (DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await t.pump();
    }
    await g.up();
    await t.pump();
  }

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
    await t.tap(find.byKey(const Key('new')));
    await settle(t);
    await t.tap(find.byKey(const Key('newNotebook')));
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

  /// Documento -> pantalla: el Listener de las capas mide exactamente la hoja (ancho kW * escala) y se
  /// pregunta al render, así que cuenta escala y scroll (anda igual en la tablet vertical u horizontal).
  Offset Function(Offset) docToScreen(WidgetTester t) {
    final ed = editor(t);
    final layers = find
        .descendant(of: find.byType(PageEditor), matching: find.byType(Listener))
        .evaluate()
        .map((e) => e.renderObject as RenderBox)
        .firstWhere((b) => b.hasSize && (b.size.width - kW * ed.scale).abs() < .5);
    return (Offset p) => layers.localToGlobal(p * ed.scale);
  }

  /// Arrastre de lápiz; [during] se evalúa con el lápiz todavía apoyado.
  Future<void> stylusDrag(WidgetTester t, Offset a, Offset b, {void Function()? during}) async {
    final g = await t.startGesture(a, kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(a, b, i / 10)!);
      await t.pump(const Duration(milliseconds: 16));
    }
    during?.call();
    await g.up();
    await settle(t, 300);
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
    expect(editor(t).doc.strokes.length, 1);

    // volver: guarda y muestra la biblioteca
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
    expect(find.byKey(const Key('nb-Física')), findsOneWidget);
    final nb = await savedNotebook('Física');
    final s = Storage(root: root);
    await s.init();
    expect((await s.loadNotebook(nb)).strokes.length, 1, reason: 'el trazo quedó guardado en disco');
  });

  testWidgets('modo lectura: el lápiz no dibuja', (t) async {
    await start(t);
    await createNotebook(t, 'Lectura');
    await t.tap(find.byKey(const Key('reading')));
    await settle(t);
    final c = sheetCenter(t);
    await stylusLine(t, c, c + const Offset(150, 0));
    expect(editor(t).doc.strokes, isEmpty);
    await t.tap(find.byKey(const Key('reading')));
    await settle(t);
    await stylusLine(t, c, c + const Offset(150, 0));
    expect(editor(t).doc.strokes.length, 1);
    // salir: que el guardado termine antes de que el test borre su carpeta
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
  });

  testWidgets('panel de páginas: contador, agregar hoja y marcador', (t) async {
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
    expect(t.widget<Text>(find.byKey(const Key('sheetCounter'))).data, '1 / 2', reason: 'contador del título');

    // marcador
    await t.tap(find.descendant(of: find.byKey(const Key('thumb-2')), matching: find.byType(IconButton)));
    await settle(t, 600);
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
    expect((await savedNotebook('Panel')).sheets[1].bookmark, isTrue);
  });

  testWidgets('el contador del título sigue al scroll', (t) async {
    await start(t);
    await createNotebook(t, 'Scroll');
    // tres hojas más: se agregan desde el panel (cada una después de la actual)
    await t.tap(find.byKey(const Key('pagesBtn')));
    await settle(t, 600);
    for (var i = 0; i < 3; i++) {
      await t.tap(find.byKey(const Key('addPage')));
      await settle(t, 900);
    }
    expect(editor(t).doc.sheetCount, 4);
    await t.tap(find.byKey(const Key('thumb-1')));
    await settle(t, 800);
    expect(t.widget<Text>(find.byKey(const Key('sheetCounter'))).data, '1 / 4');
    // scrollear con el dedo hasta la hoja 3
    final ed = editor(t);
    ed.scroll.jumpTo(2 * kSheetStep * ed.scale);
    await settle(t, 600);
    expect(t.widget<Text>(find.byKey(const Key('sheetCounter'))).data, '3 / 4');
    expect(t.widget<Text>(find.byKey(const Key('pageCounter'))).textSpan!.toPlainText(), '3 / 4');
  });

  testWidgets('agregar, mover y borrar hojas desde el panel', (t) async {
    await start(t);
    await createNotebook(t, 'Hojas');
    // un trazo en la hoja 1 para reconocerla después
    final c = sheetCenter(t);
    await stylusLine(t, c, c + const Offset(200, 0));
    final strokeId = editor(t).doc.strokes.keys.single;

    await t.tap(find.byKey(const Key('pagesBtn')));
    await settle(t, 600);
    await t.tap(find.byKey(const Key('addPage')));
    await settle(t, 900);
    await t.tap(find.byKey(const Key('addPage')));
    await settle(t, 900);
    expect(editor(t).doc.sheetCount, 3);
    expect(find.byKey(const Key('thumb-3')), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const Key('pageCounter'))).textSpan!.toPlainText(), '3 / 3');

    // mover la hoja 1 (con el trazo) después de la 2: el trazo baja una hoja
    Future<void> longPressThumb(int n, String item) async {
      await holdOn(t, find.byKey(Key('thumb-$n')));
      await settle(t, 500);
      await t.tap(find.text(item));
      await settle(t, 900);
    }

    await longPressThumb(1, 'Mover después');
    expect(editor(t).doc.strokes[strokeId]!.bounds.top, greaterThan(kSheetStep), reason: 'el trazo viajó con su hoja');
    expect(editor(t).doc.sheetOfY(editor(t).doc.strokes[strokeId]!.bounds.top), 1);

    // borrar la hoja 2 (la del trazo): pide confirmación y se va con su contenido
    await longPressThumb(2, 'Borrar');
    await t.tap(find.byKey(const Key('confirmDelete')));
    await settle(t, 900);
    expect(editor(t).doc.sheetCount, 2);
    expect(editor(t).doc.strokes, isEmpty);
    expect(find.byKey(const Key('thumb-3')), findsNothing);

    // borrar también la última de las dos; con una sola hoja el menú ya no ofrece "Borrar"
    await longPressThumb(2, 'Borrar');
    await t.tap(find.byKey(const Key('confirmDelete')));
    await settle(t, 900);
    await holdOn(t, find.byKey(const Key('thumb-1')));
    await settle(t, 500);
    expect(find.text('Borrar'), findsNothing, reason: 'con una sola hoja no hay "Borrar"');
    await t.tapAt(const Offset(5, 5)); // cierra el menú
    await settle(t, 400);
    expect(editor(t).doc.sheetCount, 1);

    // todo quedó guardado: una hoja en notebook.json y un solo .sheet
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
    final nb = await savedNotebook('Hojas');
    expect(nb.sheets.length, 1);
    final sheets = Directory('${root.path}/notebooks/${nb.id}/sheets').listSync().where((e) => e.path.endsWith('.sheet'));
    expect(sheets.length, 1);
  });

  testWidgets('nota adhesiva y búsqueda', (t) async {
    await start(t);
    await createNotebook(t, 'Notas');
    await t.tap(find.byKey(const Key('insert')));
    await settle(t);
    await t.tap(find.text('Nota adhesiva'));
    await settle(t, 600);
    final items = editor(t).doc.items.values;
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

  testWidgets('texto: el teclado abre al tocar la herramienta y la barra de formato aplica negrita', (t) async {
    await start(t);
    await createNotebook(t, 'Texto');
    await t.tap(find.byTooltip('Texto con teclado'));
    await settle(t, 600);
    final ed = editor(t);
    expect(ed.doc.texts.length, 1, reason: 'el tecladito crea el renglón solo');
    final b = ed.doc.texts.values.single;
    expect(ed.texts.editor(b.id)!.hasFocus, isTrue, reason: 'y lo enfoca: se abre el teclado');
    expect(find.byKey(const Key('fmt-bold')), findsOneWidget);

    final field = find.byKey(Key('para-${b.id}-0'));
    await t.enterText(field, 'hola mundo');
    await settle(t, 300);
    ed.texts.editor(b.id)!.fields[0].ctl.selection = const TextSelection(baseOffset: 1, extentOffset: 5);
    await t.pump();
    await t.tap(find.byKey(const Key('fmt-bold')));
    await settle(t, 300);
    expect(b.body.paras[0].runs.first.style.bold, isTrue);
    expect(b.body.paras[0].runs.first.text, 'hola');

    // volver y entrar: el formato quedó guardado
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1500);
    final nb = await savedNotebook('Texto');
    final s = Storage(root: root);
    await s.init();
    final saved = (await s.loadNotebook(nb)).texts.values.single;
    expect(saved.text, 'hola mundo');
    expect(saved.body.paras[0].runs.first.style.bold, isTrue);
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
    final it = editor(t).doc.items.values.single;
    expect(it.type, 'image');
    expect(it.h / it.w, closeTo(.75, .01));
    expect(await File('${root.path}/media/${it.file}').exists(), isTrue, reason: 'la imagen se copió a la carpeta del cuaderno');
  });

  testWidgets('estilo de hoja: esta hoja y todo el cuaderno', (t) async {
    await start(t);
    await createNotebook(t, 'Estilo');
    await t.tap(find.byKey(const Key('pagesBtn')));
    await settle(t, 600);
    await t.tap(find.byKey(const Key('addPage')));
    await settle(t, 800);

    // solo la hoja que se ve (la 2, que acaba de agregarse)
    await openMore(t, 'Estilo de hoja');
    await t.tap(find.byKey(const Key('applySheet')));
    await t.tap(find.text('Cuadriculado'));
    await settle(t, 300);
    await t.tap(find.byKey(const Key('spacing-7')));
    await t.tap(find.byTooltip('Crema'));
    await settle(t);
    await t.tap(find.byKey(const Key('styleOk')));
    await settle(t, 1200);

    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
    var nb = await savedNotebook('Estilo');
    expect([nb.sheets[0].bg, nb.sheets[0].spacing], ['lined', 8.0], reason: 'la otra hoja no cambia');
    expect([nb.sheets[1].bg, nb.sheets[1].paper, nb.sheets[1].spacing], ['grid', '#fbf3e0', 7.0]);
    expect([nb.bg, nb.spacing], ['lined', 8.0], reason: 'las hojas nuevas siguen igual');

    // todo el cuaderno (es lo que viene marcado), y también las hojas nuevas
    await t.tap(find.byKey(const Key('nb-Estilo')));
    await settle(t, 1200);
    await openMore(t, 'Estilo de hoja');
    await t.tap(find.byKey(const Key('applyAll')));
    await t.tap(find.text('Rayado'));
    await settle(t, 300);
    await t.tap(find.byKey(const Key('spacing-10')));
    await t.tap(find.byTooltip('Celeste'));
    await settle(t);
    await t.tap(find.byKey(const Key('styleOk')));
    await settle(t, 1200);

    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
    nb = await savedNotebook('Estilo');
    expect(nb.sheets.length, 2);
    expect([nb.bg, nb.paper, nb.spacing], ['lined', '#eaf3fb', 10.0], reason: 'también el estilo de las hojas nuevas');
    for (final sheet in nb.sheets) {
      expect([sheet.bg, sheet.paper, sheet.spacing], ['lined', '#eaf3fb', 10.0]);
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

  testWidgets('PDF: una hoja A4 por cada hoja del cuaderno, cada una con su papel', (t) async {
    final s = Storage(root: root);
    await s.init();
    final nb = Notebook.create('PDF');
    nb.sheets.addAll([nb.newSheet(), nb.newSheet()..bg = 'grid']); // 3 hojas
    final doc = NotebookDoc(nb);
    doc.texts['t1'] = TextBlock('t1', 90, 44, 800, 'Hola PDF');
    final bytes = await buildNotebookPdf(s, doc);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    final pages = await Printing.raster(bytes, dpi: 20).toList();
    expect(pages.length, 3);
    expect(pages.first.width / pages.first.height, closeTo(210 / 297, .02), reason: 'tamaño A4');
  });

  Future<void> createFolder(WidgetTester t, String name) async {
    await t.tap(find.byKey(const Key('new')));
    await settle(t);
    await t.tap(find.byKey(const Key('newFolder')));
    await settle(t);
    await t.enterText(find.byKey(const Key('askText')), name);
    await t.tap(find.byKey(const Key('askOk')));
    await settle(t, 800);
  }

  testWidgets('carpetas: crear, meter un cuaderno, renombrar y sacar', (t) async {
    await start(t);
    await createNotebook(t, 'Suelto'); // se abre solo: volver a la biblioteca
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
    await createFolder(t, 'Facultad');
    expect(find.byKey(const Key('folder-Facultad')), findsOneWidget);

    // meter el cuaderno
    await holdOn(t, find.byKey(const Key('nb-Suelto')));
    await settle(t);
    await t.tap(find.byKey(const Key('moveTo')));
    await settle(t);
    await t.tap(find.byKey(const Key('moveTarget-Facultad')));
    await settle(t, 800);
    expect(find.byKey(const Key('nb-Suelto')), findsNothing);
    await t.tap(find.byKey(const Key('folder-Facultad')));
    await settle(t, 800);
    expect(find.byKey(const Key('nb-Suelto')), findsOneWidget);

    // volver y renombrar la carpeta
    await t.tap(find.byKey(const Key('up')));
    await settle(t, 800);
    await holdOn(t, find.byKey(const Key('folder-Facultad')));
    await settle(t);
    await t.tap(find.text('Renombrar'));
    await settle(t);
    await t.enterText(find.byKey(const Key('askText')), 'Uni');
    await t.tap(find.byKey(const Key('askOk')));
    await settle(t, 800);
    expect(find.byKey(const Key('folder-Uni')), findsOneWidget);

    // borrarla sacando los cuadernos
    await holdOn(t, find.byKey(const Key('folder-Uni')));
    await settle(t);
    await t.tap(find.text('Borrar'));
    await settle(t);
    await t.tap(find.byKey(const Key('folderKeep')));
    await settle(t, 800);
    expect(find.byKey(const Key('folder-Uni')), findsNothing);
    expect(find.byKey(const Key('nb-Suelto')), findsOneWidget);
  });

  testWidgets('buscar en el inicio', (t) async {
    await start(t);
    await createFolder(t, 'Análisis');
    await t.tap(find.byKey(const Key('folder-Análisis')));
    await settle(t, 800);
    await createNotebook(t, 'Álgebra lineal');
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
    await t.tap(find.byKey(const Key('up')));
    await settle(t, 800);
    expect(find.byKey(const Key('nb-Álgebra lineal')), findsNothing);

    await t.enterText(find.byKey(const Key('librarySearch')), 'ALGEBRA');
    await settle(t, 600);
    expect(find.byKey(const Key('nb-Álgebra lineal')), findsOneWidget);
    expect(find.text('Inicio / Análisis'), findsOneWidget);
    await t.enterText(find.byKey(const Key('librarySearch')), 'analisis');
    await settle(t, 600);
    expect(find.byKey(const Key('folder-Análisis')), findsOneWidget);

    await t.tap(find.byKey(const Key('librarySearchClear')));
    await settle(t, 600);
    expect(find.byKey(const Key('nb-Álgebra lineal')), findsNothing);
    expect(find.byKey(const Key('folder-Análisis')), findsOneWidget);
  });

  testWidgets('ajustes: buscar actualizaciones a mano y el interruptor automático', (t) async {
    await start(t);
    await t.tap(find.byKey(const Key('libraryMenu')));
    await settle(t, 600);
    expect(find.byKey(const Key('checkUpdates')), findsOneWidget);
    expect(t.widget<SwitchListTile>(find.byKey(const Key('autoUpdates'))).value, isTrue);
    await t.tap(find.byKey(const Key('autoUpdates')));
    await settle(t, 400);
    expect(t.widget<SwitchListTile>(find.byKey(const Key('autoUpdates'))).value, isFalse);
  });

  testWidgets('seleccionar: hacia la derecha toma lo de adentro, hacia la izquierda todo lo que toca', (t) async {
    await start(t);
    await createNotebook(t, 'Selección');
    final p = docToScreen(t);
    // zona del recuadro (coordenadas del documento): A queda entero adentro, B cruza con casi todo afuera, C lejos
    const zone = Rect.fromLTRB(100, 100, 400, 300);
    await stylusLine(t, p(const Offset(150, 150)), p(const Offset(350, 250)));
    await stylusLine(t, p(const Offset(300, 200)), p(const Offset(900, 200)));
    await stylusLine(t, p(const Offset(600, 340)), p(const Offset(900, 340)));
    final ed = editor(t);
    expect(ed.doc.strokes.length, 3);
    final strokes = ed.doc.strokes.values.toList();
    final a = strokes.firstWhere((s) => zone.contains(s.bounds.center) && s.bounds.width < 300).id;
    final b = strokes.firstWhere((s) => s.bounds.width > 400 && s.bounds.center.dy < 300).id;
    final c = strokes.firstWhere((s) => s.bounds.center.dy > 300).id;

    await t.tap(find.byTooltip('Seleccionar'));
    await settle(t);

    // izquierda -> derecha: ventana
    var duringCapture = true, duringBand = false;
    await stylusDrag(t, p(zone.topLeft), p(zone.bottomRight), during: () {
      duringCapture = ed.sel.capture;
      duringBand = ed.sel.band != null;
    });
    expect(duringBand, isTrue);
    expect(duringCapture, isFalse);
    expect(ed.sel.strokes, {a});
    expect(find.byType(SelectionMenu), findsOneWidget);

    // deseleccionar con la X de la barrita
    await t.tap(find.byTooltip('Deseleccionar'));
    await settle(t);
    expect(ed.sel.strokes, isEmpty);
    expect(find.byType(SelectionMenu), findsNothing);

    // derecha -> izquierda: captura
    duringCapture = false;
    await stylusDrag(t, p(zone.bottomRight), p(zone.topLeft), during: () => duringCapture = ed.sel.capture);
    expect(duringCapture, isTrue);
    expect(ed.sel.strokes, {a, b});
    expect(ed.sel.strokes, isNot(contains(c)));
    expect(find.byType(SelectionMenu), findsOneWidget);
  });

  testWidgets('selección: menú Orden lleva al frente y al fondo', (t) async {
    await start(t);
    await createNotebook(t, 'Orden');
    final p = docToScreen(t);
    // dos trazos que se cruzan: el horizontal se dibuja primero (abajo), el vertical después (arriba)
    await stylusLine(t, p(const Offset(200, 200)), p(const Offset(600, 200)));
    await stylusLine(t, p(const Offset(400, 100)), p(const Offset(400, 320)));
    final ed = editor(t);
    final low = ed.doc.strokes.values.firstWhere((s) => s.bounds.width > 300).id;
    expect(ed.doc.drawOrder().first.id, low);

    await t.tap(find.byTooltip('Seleccionar'));
    await settle(t);
    // ventana que encierra solo el horizontal
    await stylusDrag(t, p(const Offset(150, 170)), p(const Offset(650, 230)));
    expect(ed.sel.strokes, {low});
    expect(find.byType(SelectionMenu), findsOneWidget);

    await t.tap(find.byKey(const Key('selOrder')));
    await settle(t);
    await t.tap(find.text('Traer al frente'));
    await settle(t);
    expect(ed.doc.drawOrder().last.id, low);

    await t.tap(find.byKey(const Key('selOrder')));
    await settle(t);
    await t.tap(find.text('Enviar al fondo'));
    await settle(t);
    expect(ed.doc.drawOrder().first.id, low);

    // deshacer: vuelve al orden anterior (al frente)
    await t.tap(find.byTooltip('Deshacer'));
    await settle(t);
    expect(ed.doc.drawOrder().last.id, low);
  });

  testWidgets('scroll rápido de punta a punta: sin errores; quieto usa imágenes; un trazo nuevo se ve y se guarda', (t) async {
    // cuaderno de 6 hojas con bastante tinta por hoja (más de 1500 puntos: vale una imagen)
    final s = Storage(root: root);
    await s.init();
    final nb = Notebook.create('Veloz');
    for (var i = 0; i < 5; i++) {
      nb.sheets.add(nb.newSheet());
    }
    final doc = NotebookDoc(nb);
    for (var k = 0; k < nb.sheets.length; k++) {
      for (var j = 0; j < 40; j++) {
        final y = k * kSheetStep + 80 + j * 32.0;
        doc.strokes['s$k-$j'] = Stroke('s$k-$j', 'pen', '#000000', 3, [
          for (var i = 0; i < 50; i++) ...[100 + i * 16.0, y + (i.isEven ? 0 : 6), .6]
        ]);
      }
    }
    final total = doc.strokes.length;
    await s.saveIndex(NotesIndex(last: nb.id, notebooks: [nb]));
    await s.saveNotebook(doc);

    await start(t);
    await t.tap(find.byKey(const Key('nb-Veloz')));
    await settle(t, 1500);
    final ed = editor(t);
    expect(ed.doc.sheetCount, 6);

    // de punta a punta con el dedo, rápido: hacia el final y de vuelta
    final max = ed.scroll.position.maxScrollExtent;
    for (var i = 0; i < 25 && ed.scroll.offset < max - 50; i++) {
      await t.fling(find.byType(PageEditor), const Offset(0, -600), 6000);
      await settle(t, 250);
    }
    expect(ed.scroll.offset, greaterThan(max * .8), reason: 'llegó (casi) al final');
    for (var i = 0; i < 25 && ed.scroll.offset > 50; i++) {
      await t.fling(find.byType(PageEditor), const Offset(0, 600), 6000);
      await settle(t, 250);
    }
    expect(t.takeException(), isNull);

    // quieto: la hoja que se ve termina dibujándose con imagen (se espera de verdad: el rasterizado es asíncrono)
    String visibleId() => ed.doc.sheets[ed.visibleSheet].id;
    for (var i = 0; i < 60 && !ed.sheetUsesImage(visibleId()); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(ed.sheetUsesImage(visibleId()), isTrue, reason: 'quieta, la hoja visible usa imagen');
    expect(t.takeException(), isNull);

    // quieto: en <= 1,5 s TODAS las hojas visibles quedan con modo image (todas sus franjas listas, sin vectorial)
    bool visiblesListas() {
      for (var k = 0; k < ed.doc.sheetCount; k++) {
        if (!ed.imageCache.visibleSheets.contains(ed.doc.sheets[k].id)) continue;
        for (final e in ed.imageCache.entriesOf(ed.doc.sheets[k].id)) {
          if (e.cacheable && e.mode != InkPaintMode.image) return false;
        }
      }
      return true;
    }

    final t0 = DateTime.now();
    while (!visiblesListas() && DateTime.now().difference(t0) < const Duration(milliseconds: 1500)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await t.pump(const Duration(milliseconds: 30));
    }
    expect(visiblesListas(), isTrue, reason: 'quieto, en 1,5 s las hojas visibles quedan con todas las franjas (modo image)');

    // escribir un trazo en una hoja después del scroll: se ve (vectorial al instante) y se guarda
    ed.scrollToSheet(2, animate: false);
    await settle(t, 800);
    final id = ed.doc.sheets[2].id;
    final ver = ed.inkVersionOf(id).value;
    final p = docToScreen(t);
    await stylusLine(t, p(Offset(300, 2 * kSheetStep + 250)), p(Offset(700, 2 * kSheetStep + 250)));
    expect(ed.doc.strokes.length, total + 1);
    expect(ed.inkVersionOf(id).value, greaterThan(ver), reason: 'la hoja se repintó con el trazo nuevo');
    expect(ed.sheetUsesImage(id), isFalse, reason: 'recién escrito: vectorial, no una imagen vieja sin el trazo');
    for (var i = 0; i < 60 && !ed.sheetUsesImage(id); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(ed.sheetUsesImage(id), isTrue, reason: 'al quedar quieta se regenera con el trazo');

    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1500);
    final saved = await savedNotebook('Veloz');
    final s2 = Storage(root: root);
    await s2.init();
    expect((await s2.loadNotebook(saved)).strokes.length, total + 1, reason: 'el trazo nuevo quedó en disco');
  });
}
