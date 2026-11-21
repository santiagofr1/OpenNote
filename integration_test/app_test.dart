// Tests de la app corriendo en la tablet.
// Cada test usa una carpeta temporal propia: NO toca los cuadernos reales.
//
//   flutter test integration_test -d <id de la tablet>

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apuntes/app.dart';
import 'package:apuntes/data/export.dart';
import 'package:apuntes/data/media_import.dart';
import 'package:apuntes/data/sheet_codec.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:apuntes/editor/selection_menu.dart';
import 'package:apuntes/rendering/sheet_image_cache.dart';
import 'package:apuntes/sync/fake_backend.dart';
import 'package:apuntes/sync/fake_remote_store.dart';
import 'package:apuntes/sync/sync_engine.dart';
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

  testWidgets('hojas: borrar y deshacer, mover con el asa y deshacer, exportar e importar .opennote', (t) async {
    await start(t);
    await createNotebook(t, 'Tres');
    await t.tap(find.byKey(const Key('pagesBtn')));
    await settle(t, 600);
    await t.tap(find.byKey(const Key('addPage')));
    await settle(t, 900);
    await t.tap(find.byKey(const Key('addPage')));
    await settle(t, 900);
    expect(editor(t).doc.sheetCount, 3);
    await t.tap(find.byKey(const Key('pagesBtn'))); // cierra el panel
    await settle(t, 600);

    // un trazo por hoja: se reconocen por la hoja donde caen
    final ed = editor(t);
    for (var k = 0; k < 3; k++) {
      final st = Stroke('st$k', 'pen', '#22211e', 2.6, [100, k * kSheetStep + 200, .5, 500, k * kSheetStep + 200, .5]);
      ed.doc.strokes[st.id] = st;
      ed.doc.markDirtyElement(st);
    }
    // ignore: invalid_use_of_protected_member
    ed.setState(() {});
    await settle(t, 600);
    int sheetOf(String id) => editor(t).doc.sheetOfY(editor(t).doc.strokes[id]!.bounds.top);
    expect([sheetOf('st0'), sheetOf('st1'), sheetOf('st2')], [0, 1, 2]);

    // borrar la hoja 2 y deshacer: vuelve con su trazo
    await t.tap(find.byKey(const Key('pagesBtn')));
    await settle(t, 600);
    await holdOn(t, find.byKey(const Key('thumb-2')));
    await settle(t, 500);
    await t.tap(find.text('Borrar'));
    await settle(t, 500);
    await t.tap(find.byKey(const Key('confirmDelete')));
    await settle(t, 900);
    expect(editor(t).doc.sheetCount, 2);
    expect(editor(t).doc.strokes.containsKey('st1'), isFalse);
    await t.tap(find.byTooltip('Deshacer'));
    await settle(t, 900);
    expect(editor(t).doc.sheetCount, 3);
    expect(editor(t).doc.strokes.containsKey('st1'), isTrue, reason: 'volvió con su trazo');
    expect(sheetOf('st1'), 1);

    // mover la 3 antes de la 1 con el asa, y deshacer
    final from = t.getCenter(find.byKey(const Key('thumbHandle-3')));
    final to = t.getCenter(find.byKey(const Key('thumbDrop-1')));
    final g = await t.startGesture(from);
    await t.pump(const Duration(milliseconds: 50));
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 8)!);
      await t.pump(const Duration(milliseconds: 30));
    }
    await g.up();
    await settle(t, 900);
    expect(sheetOf('st2'), 0, reason: 'la hoja 3 quedó primera');
    await t.tap(find.byTooltip('Deshacer'));
    await settle(t, 900);
    expect(sheetOf('st2'), 2);
    expect(sheetOf('st0'), 0);

    // exportar .opennote (el diálogo del sistema se reemplaza) e importarlo
    await t.tap(find.byKey(const Key('pagesBtn')));
    await settle(t, 600);
    Uint8List? saved;
    final savedSave = saveOpennote, savedPick = Pickers.opennote;
    saveOpennote = (bytes, name) async {
      saved = bytes;
      return true;
    };
    addTearDown(() {
      saveOpennote = savedSave;
      Pickers.opennote = savedPick;
    });
    await openMore(t, 'Exportar cuaderno (.opennote)');
    expect(saved, isNotNull);
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
    Pickers.opennote = () async => saved;
    await t.tap(find.byKey(const Key('new')));
    await settle(t, 600);
    await t.tap(find.byKey(const Key('importNotebook')));
    await settle(t, 2000);
    final store = Storage(root: root);
    await store.init();
    final idx = await store.loadIndex();
    // al arrancar la app crea "Mi cuaderno": se comparan solo el original y el importado
    final names = idx.notebooks.map((n) => n.name).toList();
    final orig = idx.notebooks.firstWhere((n) => n.name == 'Tres');
    final imp = idx.notebooks.where((n) => n.name == 'Tres (importado)').toList();
    expect(imp.length, 1, reason: 'cuadernos: $names');
    expect(imp.single.id, isNot(orig.id));
    final impDoc = await store.loadNotebook(imp.single);
    expect(impDoc.sheetCount, 3, reason: 'el importado trae sus 3 hojas');
    expect(impDoc.strokes.length, 3, reason: 'y un trazo en cada una');
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

  testWidgets('selección: un toque elige la tinta, otro el resaltador (se mueve solo) y tocar afuera deselecciona', (t) async {
    await start(t);
    await createNotebook(t, 'Toque');
    final p = docToScreen(t);
    final ed = editor(t);
    // una "palabra" a lápiz y resaltada encima
    await stylusLine(t, p(const Offset(200, 200)), p(const Offset(400, 200)));
    await t.tap(find.byTooltip('Resaltador · tocá de nuevo para opciones'));
    await settle(t);
    await stylusLine(t, p(const Offset(200, 200)), p(const Offset(400, 200)));
    expect(ed.doc.strokes.length, 2);
    final hl = ed.doc.strokes.values.firstWhere((s) => s.k == 'hl');
    final ink = ed.doc.strokes.values.firstWhere((s) => s.k != 'hl');
    final hlBefore = hl.bounds, inkBefore = ink.bounds;

    await t.tap(find.byTooltip('Seleccionar'));
    await settle(t);

    Future<void> tapAt(Offset d) async {
      final g = await t.startGesture(p(d), kind: PointerDeviceKind.stylus);
      await g.up();
      await settle(t);
    }

    // el de más arriba que se ve es la tinta; tocar de nuevo en el mismo lugar alterna al resaltador
    await tapAt(const Offset(300, 200));
    expect(ed.sel.strokes, {ink.id});
    await tapAt(const Offset(300, 200));
    expect(ed.sel.strokes, {hl.id});

    // se mueve solo el resaltador
    await stylusDrag(t, p(const Offset(300, 200)), p(const Offset(300, 260)));
    expect(ed.doc.strokes[ink.id]!.bounds, inkBefore);
    expect(ed.doc.strokes[hl.id]!.bounds.top, greaterThan(hlBefore.top + 40));

    // tocar afuera: no queda nada seleccionado
    await tapAt(const Offset(500, 500));
    expect(ed.sel.isEmpty, isTrue);
    expect(find.byType(SelectionMenu), findsNothing);
  });

  testWidgets('scroll rápido de punta a punta: sin errores; quieto usa imágenes; un trazo nuevo se ve y se guarda', (t) async {
    // cuaderno de 6 hojas con bastante tinta por hoja (más de SheetImageCache.defaultMinPoints: vale una imagen)
    final perStroke = SheetImageCache.defaultMinPoints ~/ 40 + 20;
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
          for (var i = 0; i < perStroke; i++) ...[100 + i * 800 / perStroke, y + (i.isEven ? 0 : 6), .6]
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

  testWidgets('hojas con lápiz y bolígrafo: abrir, desplazar, descargar y volver; las hojas se ven con malla', (t) async {
    // 12 hojas, cada una con trazos de lápiz y de bolígrafo (las mallas se arman al cargar y se sueltan al descargar)
    final s = Storage(root: root);
    await s.init();
    final nb = Notebook.create('Mallas');
    while (nb.sheets.length < 12) {
      nb.sheets.add(nb.newSheet());
    }
    final doc = NotebookDoc(nb);
    for (var k = 0; k < nb.sheets.length; k++) {
      for (var j = 0; j < 20; j++) {
        final y = k * kSheetStep + 80 + j * 40.0;
        final kind = j.isEven ? 'pencil' : 'pen';
        doc.strokes['m$k-$j'] = Stroke('m$k-$j', kind, '#22211e', 3, [
          for (var i = 0; i < 120; i++) ...[100 + i * 6.0, y + (i % 5) * 3, .3 + (i % 7) * .08]
        ]);
      }
    }
    await s.saveIndex(NotesIndex(last: nb.id, notebooks: [nb]));
    await s.saveNotebook(doc);

    await start(t);
    await t.tap(find.byKey(const Key('nb-Mallas')));
    await settle(t, 1500);
    final ed = editor(t);
    expect(ed.doc.sheetCount, 12);

    bool conMalla(int k) {
      final id = ed.doc.sheets[k].id;
      if (!ed.doc.isLoaded(id)) return false;
      final mine = [for (final st in ed.doc.strokes.values) if (ed.doc.sheetOfElement(st) == k) st];
      return mine.length == 20 && mine.every((st) => st.mesh != null);
    }

    await settle(t, 800);
    expect(conMalla(ed.visibleSheet), isTrue, reason: 'la hoja inicial llega con malla');

    // hasta el final y de vuelta, rápido
    final max = ed.scroll.position.maxScrollExtent;
    for (var i = 0; i < 25 && ed.scroll.offset < max - 50; i++) {
      await t.fling(find.byType(PageEditor), const Offset(0, -600), 6000);
      await settle(t, 250);
    }
    for (var i = 0; i < 25 && ed.scroll.offset > 50; i++) {
      await t.fling(find.byType(PageEditor), const Offset(0, 600), 6000);
      await settle(t, 250);
    }
    expect(t.takeException(), isNull);

    // descargar una hoja lejana a mano (suelta mallas y lotes) y volver a ella: se recarga y se ve con malla
    final far = ed.doc.sheetCount - 1;
    final farId = ed.doc.sheets[far].id;
    final farStrokes = [for (final st in ed.doc.strokes.values) if (ed.doc.sheetOfElement(st) == far) st];
    final r = await t.runAsync(() => ed.widget.store.unloadSheets(ed.doc, [farId]));
    if (r != null && r.unloaded.contains(farId)) {
      for (final st in farStrokes) {
        expect(st.mesh, isNull, reason: 'la hoja descargada soltó la malla');
        expect(st.batchCache, isNull, reason: 'y el lote');
      }
      expect(ed.doc.isLoaded(farId), isFalse);
    }
    ed.scrollToSheet(far, animate: false);
    for (var i = 0; i < 40 && !conMalla(far); i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(t.takeException(), isNull);
    expect(ed.doc.isLoaded(farId), isTrue, reason: 'volvió a cargarse');
    // las mallas del trazo recién cargado llegan del isolate o se arman al primer dibujo
    await settle(t, 600);
    expect(conMalla(far), isTrue, reason: 'tras recargar, la hoja vuelve con malla');
    expect(t.takeException(), isNull);
  });

  testWidgets('sincronización: "Sincronizar ahora" sube un cuaderno y otro dispositivo lo baja (remoto falso)', (t) async {
    final remote = FakeRemoteStore();
    await t.pumpWidget(ApuntesApp(root: root, backend: FakeBackend(remote)));
    await settle(t, 1500);
    await createNotebook(t, 'Para nube');
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
    await t.tap(find.byKey(const Key('libraryMenu')));
    await settle(t);
    await t.tap(find.byKey(const Key('syncMenu')));
    await settle(t, 600);
    expect(find.byKey(const Key('syncConnect')), findsOneWidget);
    await t.tap(find.byKey(const Key('syncConnect')));
    for (var i = 0; i < 60 && find.byKey(const Key('syncNow')).evaluate().isEmpty; i++) {
      await settle(t, 100);
    }
    await t.tap(find.byKey(const Key('syncNow')));
    for (var i = 0; i < 200 && !remote.has('index.json'); i++) {
      await settle(t, 100);
    }
    await settle(t, 1500);
    expect(remote.has('index.json'), isTrue);
    expect(remote.paths.where((p) => p.endsWith('/notebook.json')), hasLength(1));

    // otro "dispositivo" (otra carpeta) baja lo subido
    final other = await Directory.systemTemp.createTemp('apuntes_test_otro');
    addTearDown(() => other.delete(recursive: true));
    final s2 = Storage(root: other);
    await s2.init();
    await SyncEngine(s2, remote, account: 'x').sync();
    expect((await s2.loadIndex()).notebooks.map((n) => n.name), ['Para nube']);
    expect(t.takeException(), isNull);
  });

  testWidgets('sincronización automática: lo escrito en un cuaderno abierto llega a la nube solo, y un cambio de la nube avisa', (t) async {
    final remote = FakeRemoteStore();
    final backend = FakeBackend(remote);
    await backend.signIn(); // ya conectado: la app retoma la sesión al abrir
    await t.pumpWidget(ApuntesApp(
        root: root, backend: backend, syncPoll: const Duration(seconds: 4), syncDebounce: const Duration(seconds: 2)));
    await settle(t, 1500);
    await createNotebook(t, 'Auto');
    expect(find.byKey(const Key('syncIndicator')), findsOneWidget, reason: 'indicador en el editor');

    // 1) un trazo con el cuaderno ABIERTO; sin tocar "Sincronizar ahora" llega a la nube en pocos segundos
    final c = sheetCenter(t);
    await stylusLine(t, c - const Offset(120, 40), c + const Offset(120, 40));
    int strokesInRemote() {
      var n = 0;
      for (final p in remote.paths.where((p) => p.endsWith('.sheet'))) {
        n += decodeSheet(remote.bytesOf(p)!).strokes.length;
      }
      return n;
    }

    var waited = 0;
    while (strokesInRemote() == 0 && waited < 20) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
      await settle(t, 250);
      waited++;
    }
    expect(strokesInRemote(), 1, reason: 'subido solo, con el cuaderno abierto (esperó ~${waited / 2} s)');
    expect(find.byKey(const Key('remoteBanner')), findsNothing);

    // 2) otro dispositivo cambia la misma hoja: el cuaderno abierto no se pisa; aparece el aviso
    final other = await Directory.systemTemp.createTemp('apuntes_test_otro2');
    addTearDown(() => other.delete(recursive: true));
    final s2 = Storage(root: other);
    await s2.init();
    await SyncEngine(s2, remote, account: 'otro').sync();
    final idx2 = await s2.loadIndex();
    final d2 = await s2.loadNotebook(idx2.notebooks.firstWhere((n) => n.name == 'Auto'));
    d2.texts['t'] = TextBlock('t', 90, 44, 800, 'desde la otra tablet');
    d2.markDirtyAt(44);
    await s2.saveNotebook(d2);
    await s2.saveIndex(idx2);
    await SyncEngine(s2, remote, account: 'otro').sync();
    waited = 0;
    while (find.byKey(const Key('remoteBanner')).evaluate().isEmpty && waited < 40) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
      await settle(t, 250);
      waited++;
    }
    expect(find.byKey(const Key('remoteBanner')), findsOneWidget);
    expect(editor(t).doc.strokes, hasLength(1), reason: 'lo local sigue intacto');

    // 3) "Actualizar": se cierra, baja y se vuelve a abrir con el cambio y el trazo
    await t.tap(find.byKey(const Key('remoteRefresh')));
    waited = 0;
    while ((find.byKey(const Key('remoteBanner')).evaluate().isNotEmpty || find.byType(PageEditor).evaluate().isEmpty) && waited < 60) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
      await settle(t, 250);
      waited++;
    }
    await settle(t, 1000);
    expect(find.byKey(const Key('remoteBanner')), findsNothing);
    expect(editor(t).doc.texts.values.map((x) => x.text), contains('desde la otra tablet'));
    expect(editor(t).doc.strokes, hasLength(1));
    expect(t.takeException(), isNull);
  });
}
