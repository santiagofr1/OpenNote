// Tests de la app corriendo en la tablet.
// Cada test usa una carpeta temporal propia: NO toca los cuadernos reales.
//
//   flutter test integration_test -d <id de la tablet>

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apuntes/app.dart';
import 'package:apuntes/data/export.dart';
import 'package:apuntes/data/media_import.dart';
import 'package:apuntes/data/sheet_codec.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/fake_audio_source.dart';
import 'package:apuntes/editor/handwriting.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:apuntes/editor/voice_recorder.dart';
import 'package:apuntes/editor/selection.dart';
import 'package:apuntes/editor/selection_menu.dart';
import 'package:apuntes/rendering/sheet_image_cache.dart';
import 'package:apuntes/rendering/text_layout.dart';
import 'package:apuntes/sync/fake_backend.dart';
import 'package:apuntes/sync/fake_remote_store.dart';
import 'package:apuntes/sync/sync_engine.dart';
import 'package:archive/archive.dart';
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

  testWidgets('decorador: su botón abre el panel, elige forma, tipo de trazo y fondo (y lo apaga una vez), y cada franja deja su trazo con su malla (issue #6)', (t) async {
    await start(t);
    await createNotebook(t, 'Franjas');
    final c = sheetCenter(t);
    expect(find.byTooltip('Decorador · tocá de nuevo para opciones'), findsOneWidget);
    await t.tap(find.byTooltip('Decorador · tocá de nuevo para opciones'));
    await settle(t);
    expect(editor(t).ts.tool, Tool.paint);
    var y = -150.0;
    final fondos = ['8fd8e0', 'e3cfa0', 'c9b3ec', 'f8c4a0', 'a8e2c4'];
    final estilos = ['brush', 'hl', 'marker', 'brush'];
    var i = 0;
    for (final id in ['paint-stars', 'paint-hearts', 'paint-moons', 'paint-clouds']) {
      await t.tap(find.byTooltip('Decorador · tocá de nuevo para opciones'));
      await settle(t);
      expect(find.byKey(const Key('paintPreview')), findsOneWidget);
      await t.ensureVisible(find.byKey(Key('paintShape-$id')));
      await t.tap(find.byKey(Key('paintShape-$id')));
      await settle(t);
      expect(editor(t).ts.paint.tip, id);
      await t.ensureVisible(find.byKey(Key('paintSt-${estilos[i]}')));
      await t.tap(find.byKey(Key('paintSt-${estilos[i]}')));
      await settle(t);
      expect(editor(t).ts.paintParams.style, estilos[i]);
      await t.ensureVisible(find.byKey(Key('paint-${fondos[i]}')));
      await t.tap(find.byKey(Key('paint-${fondos[i]}')));
      await settle(t);
      expect(editor(t).ts.paint.color, '#${fondos[i]}');
      if (i == 3) {
        await t.ensureVisible(find.byKey(const Key('paintBgSwitch')));
        await t.tap(find.byKey(const Key('paintBgSwitch'))); // apaga el fondo: quedan formas y brillo
        await settle(t);
        expect(editor(t).ts.paintParams.bg, false);
      }
      // cierra el panel desde adentro (no a ciegas sobre la cortina)
      Navigator.of(t.element(find.byKey(const Key('paintPreview')))).pop();
      await settle(t);
      expect(find.byKey(const Key('paintPreview')), findsNothing);
      final before = editor(t).doc.strokes.length;
      await stylusLine(t, c + Offset(-100, y), c + Offset(100, y));
      y += 70;
      expect(editor(t).doc.strokes.length, before + 1, reason: id);
      final s = editor(t).doc.strokes.values.last;
      expect(s.k, id);
      expect(s.c, '#${fondos[i]}');
      expect(s.pp, isNotNull);
      expect(s.pp!.style, estilos[i]);
      expect(s.ensureMesh()!.vertexCount, greaterThan(0));
      i++;
    }
    expect(editor(t).doc.strokes.values.last.pp!.bg, false);
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

  testWidgets('secciones: crear una, escribir en ella, volver a la otra (no se ve), cerrar y reabrir el cuaderno', (t) async {
    await start(t);
    await createNotebook(t, 'Secciones');
    await t.tap(find.byKey(const Key('pagesBtn')));
    await settle(t, 600);

    // el botón siempre está y muestra la sección activa
    expect((t.widget(find.byKey(const Key('sectionName'))) as Text).data, 'General');
    final c = sheetCenter(t);
    await stylusLine(t, c, c + const Offset(200, 40));
    expect(editor(t).doc.strokes.length, 1);

    // nueva sección "Práctica": se abre con una hoja en blanco (no se ve lo de General)
    await t.tap(find.byKey(const Key('sectionsButton')));
    await settle(t);
    await t.tap(find.byKey(const Key('newSection')));
    await settle(t);
    await t.enterText(find.byKey(const Key('askText')), 'Práctica');
    await t.tap(find.byKey(const Key('askOk')));
    await settle(t, 2000);
    expect((t.widget(find.byKey(const Key('sectionName'))) as Text).data, 'Práctica');
    expect(editor(t).doc.sheetCount, 1);
    expect(editor(t).doc.strokes, isEmpty);

    // se escribe en ella
    await stylusLine(t, sheetCenter(t), sheetCenter(t) + const Offset(0, 120));
    expect(editor(t).doc.strokes.length, 1);
    final practicaStroke = editor(t).doc.strokes.keys.single;

    // volver a General: está su trazo y no el de Práctica
    await t.tap(find.byKey(const Key('sectionsButton')));
    await settle(t);
    await t.tap(find.byKey(const Key('section-$kGeneralSection')));
    await settle(t, 2000);
    expect((t.widget(find.byKey(const Key('sectionName'))) as Text).data, 'General');
    expect(editor(t).doc.strokes.length, 1);
    expect(editor(t).doc.strokes.containsKey(practicaStroke), isFalse);

    // cerrar y reabrir el cuaderno: todo persiste
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
    final nb = await savedNotebook('Secciones');
    expect(nb.sections.map((s) => s.name), ['General', 'Práctica']);
    expect(nb.totalSheets, 2);
    await t.tap(find.byKey(const Key('nb-Secciones')));
    await settle(t, 1500);
    await t.tap(find.byKey(const Key('pagesBtn')));
    await settle(t, 600);
    expect((t.widget(find.byKey(const Key('sectionName'))) as Text).data, 'General');
    expect(editor(t).doc.strokes.length, 1);
    await t.tap(find.byKey(const Key('sectionsButton')));
    await settle(t);
    await t.tap(find.byKey(Key('section-${nb.sections.last.id}')));
    await settle(t, 2000);
    expect((t.widget(find.byKey(const Key('sectionName'))) as Text).data, 'Práctica');
    expect(editor(t).doc.strokes.keys.single, practicaStroke, reason: 'lo escrito en Práctica sigue ahí');
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
    await openMore(t, 'Exportar');
    await t.tap(find.byKey(const Key('export-opennote')));
    await settle(t, 600);
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

  testWidgets('texto: tamaño en puntos desde la barra, A+ / A- y queda guardado', (t) async {
    await start(t);
    await createNotebook(t, 'Tamaño');
    await t.tap(find.byTooltip('Texto con teclado'));
    await settle(t, 600);
    final ed = editor(t);
    final b = ed.doc.texts.values.single;
    final be = ed.texts.editor(b.id)!;
    final line = ed.doc.lineAt(b.y);
    await t.enterText(find.byKey(Key('para-${b.id}-0')), 'hola mundo');
    await settle(t, 300);
    expect(textRect(b, line).height, closeTo(line, 1), reason: 'letra automática: un renglón');

    // seleccionar "hola", elegir 24 pt en la lista
    be.fields[0].ctl.selection = const TextSelection(baseOffset: 1, extentOffset: 5);
    await t.pump();
    await t.tap(find.byKey(const Key('fmt-size')));
    await t.pump();
    await t.tap(find.byKey(const Key('fmt-size-24')));
    await settle(t, 300);
    expect(b.body.paras[0].runs.first.text, 'hola');
    expect(b.body.paras[0].runs.first.style.size, 24);
    expect(b.body.paras[0].runs.last.style.size, isNull);
    expect(textRect(b, line).height, closeTo(2 * line, 1), reason: 'con 24 pt el bloque ocupa 2 renglones');

    // A+ sube al siguiente de la lista y A- baja
    be.fields[0].ctl.selection = const TextSelection(baseOffset: 1, extentOffset: 5);
    await t.pump();
    await t.tap(find.byKey(const Key('fmt-size-up')));
    await settle(t, 300);
    expect(b.body.paras[0].runs.first.style.size, 28);
    await t.tap(find.byKey(const Key('fmt-size-down')));
    await settle(t, 300);
    expect(b.body.paras[0].runs.first.style.size, 24);
    expect(textRect(b, line).height, closeTo(2 * line, 1));

    // volver y entrar: el tamaño quedó guardado
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1500);
    final nb = await savedNotebook('Tamaño');
    final s = Storage(root: root);
    await s.init();
    final saved = (await s.loadNotebook(nb)).texts.values.single;
    expect(saved.body.paras[0].runs.first.style.size, 24);
    expect(saved.body.paras[0].runs.last.style.size, isNull);
  });

  testWidgets('texto: selección que cruza párrafos (arrastrar), negrita y borrar', (t) async {
    await start(t);
    await createNotebook(t, 'Cruce');
    await t.tap(find.byTooltip('Texto con teclado'));
    await settle(t, 600);
    final ed = editor(t);
    final b = ed.doc.texts.values.single;
    final be = ed.texts.editor(b.id)!;
    await t.enterText(find.byKey(Key('para-${b.id}-0')), 'uno');
    await settle(t, 300);
    await t.enterText(find.byKey(Key('para-${b.id}-0')), 'uno\n');
    await settle(t, 300);
    await t.enterText(find.byKey(Key('para-${b.id}-1')), 'dos');
    await settle(t, 300);
    expect(b.body.paras.length, 2);

    // mantener apretado en el primer párrafo y arrastrar hasta el segundo
    final r0 = t.getRect(find.byKey(Key('para-${b.id}-0')));
    final r1 = t.getRect(find.byKey(Key('para-${b.id}-1')));
    final g = await t.startGesture(Offset(r0.left + 2, r0.center.dy));
    await t.pump(const Duration(milliseconds: 400));
    await g.moveTo(Offset(r1.left + 30, r1.center.dy));
    await t.pump();
    await g.up();
    await settle(t, 300);
    expect(be.across, isNotNull, reason: 'la selección cruzó de un párrafo al otro');
    await t.tap(find.byKey(const Key('fmt-bold')));
    await settle(t, 300);
    expect(b.body.paras[0].runs.first.style.bold, isTrue);
    expect(b.body.paras[1].runs.first.style.bold, isTrue);

    await t.tap(find.byKey(const Key('across-delete')));
    await settle(t, 300);
    expect(b.body.paras.length, 1, reason: 'borrar une los párrafos de las puntas');
    expect(be.across, isNull);
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

  testWidgets('carpetas: mover arrastrando (cuaderno a carpeta, deshacer, carpeta a las migas)', (t) async {
    await start(t);
    await createNotebook(t, 'Suelto');
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
    await createFolder(t, 'Facultad');

    /// Mantener apretado de verdad (la tablet no adelanta el reloj con t.longPress) y llevarlo hasta [to].
    Future<void> arrastrar(Finder from, Finder to) async {
      final g = await t.startGesture(t.getCenter(from));
      final end = DateTime.now().add(const Duration(milliseconds: 750));
      while (DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await t.pump();
      }
      expect(find.byKey(const Key('moveTo')), findsOneWidget, reason: 'el menú aparece mientras sigue apretado');
      final a = t.getCenter(from), b = t.getCenter(to);
      for (var i = 1; i <= 12; i++) {
        await g.moveTo(Offset.lerp(a, b, i / 12)!);
        await t.pump(const Duration(milliseconds: 30));
      }
      expect(find.byKey(const Key('moveTo')), findsNothing, reason: 'al moverse el menú se cierra y arrastra');
      await g.up();
      await settle(t, 800);
    }

    // cuaderno -> carpeta
    await arrastrar(find.byKey(const Key('nb-Suelto')), find.byKey(const Key('folder-Facultad')));
    expect(find.byKey(const Key('nb-Suelto')), findsNothing);
    expect(find.text('Movido a Inicio / Facultad'), findsOneWidget);

    // deshacer desde el aviso
    await t.tap(find.text('Deshacer'));
    await settle(t, 800);
    expect(find.byKey(const Key('nb-Suelto')), findsOneWidget);

    // mantener apretado sin mover: el menú aparece al mantener y queda abierto al soltar
    await holdOn(t, find.byKey(const Key('nb-Suelto')));
    await settle(t);
    expect(find.byKey(const Key('moveTo')), findsOneWidget);
    await t.tapAt(const Offset(5, 5)); // tocar afuera lo cierra
    await settle(t);

    // carpeta Hija adentro de Facultad, y de ahí a "Inicio" en las migas
    await t.tap(find.byKey(const Key('folder-Facultad')));
    await settle(t, 800);
    await createFolder(t, 'Hija');
    await arrastrar(find.byKey(const Key('folder-Hija')), find.byKey(const Key('crumb-inicio')));
    expect(find.byKey(const Key('folder-Hija')), findsNothing);
    await t.tap(find.byKey(const Key('up')));
    await settle(t, 800);
    expect(find.byKey(const Key('folder-Hija')), findsOneWidget, reason: 'ahora está en el inicio');
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

  testWidgets('selección: el resaltador sobre un texto queda seleccionado con él (sin filtros) y se mueven juntos', (t) async {
    await start(t);
    await createNotebook(t, 'HlTexto');
    final ed = editor(t);
    final p = docToScreen(t);
    // un texto escrito con el teclado, como lo hace el usuario
    await t.tap(find.byTooltip('Texto con teclado'));
    await settle(t, 600);
    final tb = ed.doc.texts.values.single;
    await t.enterText(find.byKey(Key('para-${tb.id}-0')), 'hola mundo escrito');
    await settle(t, 300);
    final tbY = tb.y;
    final y = tb.y + ed.doc.lineAt(tb.y) * .5; // mitad del renglón
    // el resaltador encima del texto
    await t.tap(find.byTooltip('Resaltador · tocá de nuevo para opciones'));
    await settle(t, 600);
    await stylusLine(t, p(Offset(tb.x + 10, y)), p(Offset(tb.x + 220, y)));
    final hl = ed.doc.strokes.values.firstWhere((s) => s.k == 'hl', orElse: () => throw StateError('el resaltador no dibujó sobre el texto'));
    final hlBefore = hl.bounds;

    await t.tap(find.byTooltip('Seleccionar'));
    await settle(t);
    // recuadro de captura (derecha a izquierda) sobre todo
    await stylusDrag(t, p(Offset(tb.x + 400, y + 60)), p(Offset(tb.x - 20, tbY - 20)));
    expect(ed.sel.strokes, {hl.id});
    expect(ed.sel.texts, {tb.id});
    expect(find.text('Solo resaltador'), findsNothing, reason: 'ya no hay filtros: lo de adentro queda seleccionado');
    expect(find.text('Sin resaltador'), findsNothing);

    // se mueven juntos
    await stylusDrag(t, p(Offset(tb.x + 100, y)), p(Offset(tb.x + 100, y + 80)));
    expect(ed.doc.texts[tb.id]!.y, greaterThan(tbY + 30), reason: 'el texto se movió con el resaltador');
    expect(ed.doc.strokes[hl.id]!.bounds.top, greaterThan(hlBefore.top + 40));
  });

  testWidgets('selección: escalar con la esquina, rotar con la manija, deshacer y tocar afuera cancela', (t) async {
    await start(t);
    await createNotebook(t, 'Manijas');
    final p = docToScreen(t);
    final ed = editor(t);
    // En la tablet real la parte visible de la hoja es mucho más baja que 800 unidades (escala ~1,6 en horizontal): todo
    // se acomoda dentro de lo que se ve (comprimiendo solo la altura) para no dibujar ni arrastrar fuera de la pantalla.
    final view = t.getRect(find.byType(PageEditor)), origin = p(Offset.zero);
    final visH = view.height / ed.scale;
    final top = (view.top - origin.dy) / ed.scale + visH * .22, ky = (visH * .5 / 600).clamp(0.2, 1.0);
    Offset q(double x, double y) => p(Offset(x, top + (y - 100) * ky));
    // dos trazos que se estiran juntos y uno lejos que no entra al recuadro
    await stylusLine(t, q(200, 200), q(400, 200));
    await stylusLine(t, q(200, 260), q(400, 320));
    await stylusLine(t, q(600, 700), q(800, 700));
    expect(ed.doc.strokes.length, 3);
    final ids = ed.doc.strokes.keys.toList();
    final far = ids.last;
    List<double> ptsOf(String id) => List<double>.of(ed.doc.strokes[id]!.pts);
    final before = {for (final id in ids) id: ptsOf(id)};
    final w0 = ed.doc.strokes[ids.first]!.w;

    await t.tap(find.byTooltip('Seleccionar'));
    await settle(t);
    await stylusDrag(t, q(150, 150), q(450, 360)); // ventana sobre los dos primeros
    expect(ed.sel.strokes, {ids[0], ids[1]});
    for (final n in ['tl', 'tr', 'br', 'bl', 'rotate']) {
      expect(find.byKey(Key('selHandle-$n')), findsOneWidget, reason: 'manija $n');
    }

    // escalar: la esquina de abajo-derecha se aleja el 50 % de la diagonal respecto de la de arriba-izquierda
    final tl = t.getCenter(find.byKey(const Key('selHandle-tl'))), br = t.getCenter(find.byKey(const Key('selHandle-br')));
    var live = 0.0;
    await stylusDrag(t, br, tl + (br - tl) * 1.5, during: () => live = ed.sel.drag!.xf.scale);
    expect(live, greaterThan(1.3));
    expect(ed.sel.isEmpty, isFalse, reason: 'después de escalar sigue seleccionado');
    final k = ed.doc.strokes[ids.first]!.w / w0;
    expect(k, closeTo(live, .01), reason: 'el grosor se multiplica por la escala');
    final sizeAfter = ed.doc.strokes[ids.first]!.bounds.width;
    expect(sizeAfter, greaterThan(200 * 1.3), reason: 'el trazo de 200 de largo quedó más grande');
    expect(ptsOf(far), before[far], reason: 'lo de afuera no se toca');

    // rotar ~90° con la manija de arriba (pantalla: del centro hacia arriba -> hacia la derecha)
    final rot = t.getCenter(find.byKey(const Key('selHandle-rotate')));
    final c = (t.getCenter(find.byKey(const Key('selHandle-tl'))) + t.getCenter(find.byKey(const Key('selHandle-br')))) / 2;
    final r = (rot - c).distance;
    final lenBefore = ed.doc.strokes[ids.first]!.bounds;
    await stylusDrag(t, rot, c + Offset(r, 0));
    final after = ed.doc.strokes[ids.first]!.bounds;
    expect(after.height, greaterThan(lenBefore.height), reason: 'giró: lo que era ancho ahora es más alto');
    expect(ed.doc.strokes[ids.first]!.w, closeTo(w0 * k, 1e-6), reason: 'rotar no cambia el grosor');

    // deshacer: rotar, escalar; cada uno es UN paso y vuelve todo exacto
    await t.tap(find.byTooltip('Deshacer'));
    await settle(t);
    expect(ed.doc.strokes[ids.first]!.bounds.width, closeTo(sizeAfter, 1e-6));
    await t.tap(find.byTooltip('Deshacer'));
    await settle(t);
    for (final id in ids) {
      expect(ptsOf(id), before[id], reason: 'deshacer vuelve los puntos exactos');
    }
    expect(ed.doc.strokes[ids.first]!.w, w0);

    // tocar afuera, sobre el trazo lejano: solo cancela (no elige nada); otro toque sí elige
    await t.tap(find.byTooltip('Rehacer'));
    await settle(t);
    await stylusDrag(t, q(100, 100), q(600, 450)); // vuelve a seleccionar los dos
    expect(ed.sel.strokes.length, 2);
    Future<void> tapAt(Offset d) async {
      final g = await t.startGesture(q(d.dx, d.dy), kind: PointerDeviceKind.stylus);
      await g.up();
      await settle(t);
    }

    await tapAt(const Offset(700, 700));
    expect(ed.sel.isEmpty, isTrue, reason: 'no quedó nada seleccionado');
    expect(find.byType(SelectionMenu), findsNothing);
    expect(find.byKey(const Key('selHandle-br')), findsNothing);
    await tapAt(const Offset(700, 700));
    expect(ed.sel.strokes, {far}, reason: 'el segundo toque, ya sin selección, elige');
  });

  testWidgets('selección: las manijas del medio estiran solo a lo ancho o solo a lo alto (trazos e imagen)', (t) async {
    final img = await fakeImage(400, 300);
    Pickers.image = (_) async => img;
    await start(t);
    await createNotebook(t, 'Estirar');
    final p = docToScreen(t);
    final ed = editor(t);
    // igual que en el test de escalar: todo dentro de la parte visible de la hoja
    final view = t.getRect(find.byType(PageEditor)), origin = p(Offset.zero);
    final visH = view.height / ed.scale;
    final top = (view.top - origin.dy) / ed.scale + visH * .22, ky = (visH * .5 / 600).clamp(0.2, 1.0);
    Offset q(double x, double y) => p(Offset(x, top + (y - 100) * ky));
    // un trazo en L
    await stylusLine(t, q(200, 200), q(200, 450));
    await stylusLine(t, q(200, 450), q(450, 450));
    expect(ed.doc.strokes.length, 2);

    await t.tap(find.byTooltip('Seleccionar'));
    await settle(t);
    await stylusDrag(t, q(150, 150), q(500, 500)); // ventana sobre la L
    expect(ed.sel.strokes.length, 2);
    for (final n in ['top', 'right', 'bottom', 'left']) {
      expect(find.byKey(Key('selHandle-$n')), findsOneWidget, reason: 'manija $n');
    }
    final r0 = ed.sel.contentRect(ed.doc)!;

    // a la derecha: crece el ancho, el alto no
    final right = t.getCenter(find.byKey(const Key('selHandle-right')));
    await stylusDrag(t, right, right + const Offset(120, 0));
    final r1 = ed.sel.contentRect(ed.doc)!;
    expect(r1.width, greaterThanOrEqualTo(r0.width * 1.3), reason: 'se estiró a lo ancho');
    expect((r1.height - r0.height).abs(), lessThan(2), reason: 'el alto no cambia');

    // deshacer vuelve (y suelta la selección, como siempre): se mide la L directamente y se vuelve a seleccionar
    final lIds = Set.of(ed.sel.strokes);
    await t.tap(find.byTooltip('Deshacer'));
    await settle(t);
    final r2 = contentBounds([for (final id in lIds) ed.doc.strokes[id]!], const [], const [])!;
    expect(r2.width, closeTo(r0.width, 1e-6));
    expect(r2.height, closeTo(r0.height, 1e-6));
    await stylusDrag(t, q(150, 150), q(500, 500));
    expect(ed.sel.strokes, lIds);

    // hacia abajo: crece el alto, el ancho no
    final bottom = t.getCenter(find.byKey(const Key('selHandle-bottom')));
    await stylusDrag(t, bottom, bottom + const Offset(0, 40));
    final r3 = ed.sel.contentRect(ed.doc)!;
    expect(r3.height, greaterThan(r0.height * 1.05), reason: 'se estiró a lo alto');
    expect((r3.width - r0.width).abs(), lessThan(2), reason: 'el ancho no cambia');

    // una imagen sola: estirada a la derecha pierde la proporción
    await t.tap(find.byKey(const Key('insert')));
    await settle(t);
    await t.tap(find.text('Imagen'));
    await settle(t, 1200);
    final it = ed.doc.items.values.single;
    await t.tap(find.byTooltip('Seleccionar'));
    await settle(t);
    final g = await t.startGesture(p(it.rect.center), kind: PointerDeviceKind.stylus);
    await g.up();
    await settle(t);
    expect(ed.sel.items, {it.id});
    expect(ed.sel.strokes, isEmpty);
    final w0 = it.w, h0 = it.h;
    final side = t.getCenter(find.byKey(const Key('selHandle-right')));
    final target = Offset(min(side.dx + 60, view.right - 20), side.dy);
    await stylusDrag(t, side, target);
    final it2 = ed.doc.items[it.id]!;
    expect(it2.w, greaterThan(w0 * 1.02), reason: 'la imagen se ensanchó');
    expect(it2.h, closeTo(h0, 1e-6), reason: 'el alto queda igual: la proporción se rompe');
  });

  testWidgets('con el dedo se selecciona y mueve una imagen / audio (issue #11a)', (t) async {
    final img = await fakeImage(400, 300);
    Pickers.image = (_) async => img;
    final audioSrc = File('${root.path}/clase.m4a')..writeAsBytesSync(List.filled(2048, 3));
    Pickers.audio = () async => audioSrc;
    Pickers.audioLength = (_) async => 4000;
    await start(t);
    await createNotebook(t, 'Dedo');
    for (final label in ['Imagen', 'Archivo de audio']) {
      await t.tap(find.byKey(const Key('insert')));
      await settle(t);
      await t.tap(find.text(label));
      await settle(t, 1200);
    }
    final ed = editor(t);
    final image = ed.doc.items.values.firstWhere((i) => i.type == 'image');
    final audio = ed.doc.items.values.firstWhere((i) => i.type == 'audio');
    // cada uno en su lugar (los dos se insertaron en el centro), uno al lado del otro: en la tablet en horizontal
    // se ven menos de 800 unidades de alto y un audio más abajo quedaba fuera de pantalla
    for (final (it, x, y) in [(image, 40.0, 150.0), (audio, 620.0, 250.0)]) {
      ed.doc.markDirtyElement(it);
      it..x = x..y = y;
      ed.doc.markDirtyElement(it);
    }
    ed.refresh();
    await t.tap(find.byTooltip('Lápiz · tocá de nuevo para opciones'));
    await settle(t);
    final p = docToScreen(t);
    Future<void> fingerTap(Offset a) async {
      final g = await t.startGesture(a, kind: PointerDeviceKind.touch);
      await t.pump(const Duration(milliseconds: 50));
      await g.up();
      await settle(t, 300);
    }

    // un toque del dedo elige (con el lápiz como herramienta) y aparecen la barrita y las manijas
    await fingerTap(p(Offset(image.x + image.w / 2, image.y + image.h / 2)));
    expect(ed.selI, {image.id});
    expect(find.byKey(const Key('selHandle-br')), findsOneWidget);
    await fingerTap(p(Offset(audio.x + 200, audio.y + 32)));
    expect(ed.selI, {audio.id}, reason: 'el audio también, tocando afuera del botón de reproducir');

    // arrastrar con el dedo lo elegido lo mueve, sin scrollear
    final y0 = ed.scroll.offset, x0 = audio.x, yy0 = audio.y;
    final from = p(Offset(audio.x + 200, audio.y + 32));
    final g = await t.startGesture(from, kind: PointerDeviceKind.touch);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(from + Offset(0, -12.0 * i));
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await settle(t, 300);
    expect(ed.scroll.offset, y0, reason: 'no scrolleó');
    expect(audio.y, lessThan(yy0 - 40), reason: 'el audio subió');
    expect(audio.x, closeTo(x0, 2));

    // arrastrar en otro lado sigue scrolleando
    final y1 = ed.scroll.offset;
    final other = t.getCenter(find.byType(PageEditor)) + const Offset(300, 0);
    final g2 = await t.startGesture(other, kind: PointerDeviceKind.touch);
    for (var i = 1; i <= 10; i++) {
      await g2.moveTo(other + Offset(0, -25.0 * i));
      await t.pump(const Duration(milliseconds: 16));
    }
    await g2.up();
    await settle(t, 300);
    expect(ed.scroll.offset, greaterThan(y1 + 50), reason: 'sigue scrolleando');
  });

  testWidgets('grabar voz no bloquea: se puede escribir mientras graba y la etiqueta se mueve (issue #10)', (t) async {
    // el micrófono de verdad no se puede usar en un test: se pone uno falso en el único punto de extensión
    VoiceRecorder.sourceFactory = FakeAudioSource.new;
    addTearDown(() => VoiceRecorder.sourceFactory = RecordAudioSource.new);
    await start(t);
    await createNotebook(t, 'Voz');
    await t.tap(find.byKey(const Key('insert')));
    await settle(t);
    await t.tap(find.text('Grabación de voz'));
    await settle(t, 800);
    final ed = editor(t);
    expect(find.byType(AlertDialog), findsNothing, reason: 'ya no hay un diálogo que bloquee el cuaderno');
    final audio = ed.doc.items.values.single;
    expect(audio.type, 'audio');
    expect(audio.dur, 0);
    expect(find.byKey(const ValueKey('recordingChip')), findsOneWidget);
    expect(find.byKey(const ValueKey('recordingTime')), findsOneWidget);
    expect(find.byKey(const ValueKey('recordingDot')), findsOneWidget);

    // escribir con el teclado mientras graba
    await t.tap(find.byTooltip('Texto con teclado'));
    await settle(t, 600);
    final b = ed.doc.texts.values.single;
    await t.enterText(find.byKey(Key('para-${b.id}-0')), 'escribo mientras grabo');
    await settle(t, 400);
    expect(b.text, 'escribo mientras grabo');
    expect(find.byKey(const ValueKey('recordingChip')), findsOneWidget, reason: 'sigue grabando');

    // una segunda grabación no arranca
    await t.tap(find.byKey(const Key('insert')));
    await settle(t);
    await t.tap(find.text('Grabación de voz'));
    await settle(t, 600);
    expect(find.text('Ya hay una grabación en curso'), findsOneWidget);
    expect(ed.doc.items.values.length, 1);

    // la etiqueta se elige con el dedo y se mueve como cualquier elemento
    await t.tap(find.byTooltip('Lápiz · tocá de nuevo para opciones'));
    await settle(t);
    final p = docToScreen(t);
    final g0 = await t.startGesture(p(Offset(audio.x + 120, audio.y + 32)), kind: PointerDeviceKind.touch);
    await t.pump(const Duration(milliseconds: 50));
    await g0.up();
    await settle(t, 300);
    expect(ed.selI, {audio.id});
    final y0 = audio.y;
    final from = p(Offset(audio.x + 120, audio.y + 32));
    final g = await t.startGesture(from, kind: PointerDeviceKind.touch);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(from + Offset(0, 10.0 * i));
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await settle(t, 300);
    expect(audio.y, greaterThan(y0 + 40), reason: 'la etiqueta de grabación se movió');
    expect(find.byKey(const ValueKey('recordingChip')), findsOneWidget, reason: 'y sigue grabando');

    // parar con el botón de la etiqueta: queda un audio común con duración y el archivo final
    await t.tap(find.byKey(const ValueKey('recordingStop')));
    await settle(t, 1500);
    expect(find.byKey(const ValueKey('recordingChip')), findsNothing);
    expect(audio.dur, greaterThan(0));
    expect(File('${root.path}/media/${audio.file}').existsSync(), isTrue);
    expect(File('${root.path}/media/${audio.file}.tmp').existsSync(), isFalse);

    // volver y entrar: quedó guardado donde se lo movió
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1500);
    final nb = await savedNotebook('Voz');
    final st = Storage(root: root);
    await st.init();
    final saved = (await st.loadNotebook(nb)).items.values.single;
    expect(saved.dur, audio.dur);
    expect(saved.y, closeTo(audio.y, .01));
  });

  testWidgets('indicador de grabación: parar, cancelar y renombrar audios (issue #14)', (t) async {
    VoiceRecorder.sourceFactory = FakeAudioSource.new;
    addTearDown(() => VoiceRecorder.sourceFactory = RecordAudioSource.new);
    await start(t);
    await createNotebook(t, 'Indicador');
    final ed = editor(t);
    Future<void> record() async {
      await t.tap(find.byKey(const Key('insert')));
      await settle(t);
      await t.tap(find.text('Grabación de voz'));
      await settle(t, 800);
    }

    // grabar: aparece el indicador con el nombre; parar desde él guarda "Audio 1"
    expect(find.byKey(const ValueKey('recIndicator')), findsNothing);
    await record();
    expect(find.byKey(const ValueKey('recIndicator')), findsOneWidget);
    expect(find.textContaining('Grabando · Audio 1'), findsWidgets);
    await t.tap(find.byKey(const ValueKey('recIndicatorStop')));
    await settle(t, 1500);
    expect(find.byKey(const ValueKey('recIndicator')), findsNothing);
    final first = ed.doc.items.values.single;
    expect(first.text, 'Audio 1');
    expect(first.dur, greaterThan(0));
    expect(find.textContaining('Audio 1 ·'), findsOneWidget);

    // grabar otro (Audio 2) y cancelarlo desde el indicador: no queda elemento ni archivo
    await record();
    expect(find.textContaining('Grabando · Audio 2'), findsWidgets);
    await t.tap(find.byKey(const ValueKey('recIndicatorCancel')));
    await settle(t, 1500);
    expect(find.byKey(const ValueKey('recIndicator')), findsNothing);
    expect(ed.doc.items.values.single.id, first.id);
    expect(Directory('${root.path}/media').listSync().length, 1);

    // renombrar el primero desde la barrita de la selección
    ed.sel.replace(items: [first.id]);
    ed.refresh();
    await settle(t);
    await t.tap(find.text('Renombrar'));
    await settle(t);
    await t.enterText(find.byKey(const Key('askText')), 'Clase 3');
    await t.tap(find.byKey(const Key('askOk')));
    await settle(t);
    expect(first.text, 'Clase 3');
    expect(find.textContaining('Clase 3 ·'), findsOneWidget);

    // volver: se guarda (sin esto el guardado pendiente escribe cuando el test siguiente ya borró la carpeta)
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1500);
    final st = Storage(root: root);
    await st.init();
    final saved = (await st.loadNotebook(await savedNotebook('Indicador'))).items;
    expect(saved[first.id]?.text, 'Clase 3', reason: 'el nombre quedó guardado');
  });

  testWidgets('texto con teclado: seleccionar, escalar y rotar como una entidad, deshacer (issue #12)', (t) async {
    await start(t);
    await createNotebook(t, 'Texto libre');
    await t.tap(find.byTooltip('Texto con teclado'));
    await settle(t, 600);
    final ed = editor(t);
    final b0 = ed.doc.texts.values.single;
    await t.enterText(find.byKey(Key('para-${b0.id}-0')), 'texto libre');
    await settle(t, 400);
    await t.tap(find.byTooltip('Seleccionar'));
    await settle(t);
    final p = docToScreen(t);
    final r = textRect(b0, ed.doc.lineAt(b0.y));
    // ventana alrededor del texto
    await stylusDrag(t, p(r.topLeft - const Offset(25, 25)), p(r.bottomRight + const Offset(25, 25)));
    expect(ed.sel.texts, {b0.id});
    expect(find.byKey(const Key('selHandle-rotate')), findsOneWidget, reason: 'la manija de rotar también con solo texto');
    final x0 = b0.x, y0 = b0.y;

    // escalar con la esquina de abajo a la derecha
    final tl = t.getCenter(find.byKey(const Key('selHandle-tl'))), br = t.getCenter(find.byKey(const Key('selHandle-br')));
    await stylusDrag(t, br, tl + (br - tl) * 1.5);
    var tx = ed.doc.texts.values.single;
    expect(tx.scale, closeTo(1.5, .15));
    expect(tx.transformed, isTrue);

    // rotar ~90° con la manija de arriba
    final rot = t.getCenter(find.byKey(const Key('selHandle-rotate')));
    final c = (t.getCenter(find.byKey(const Key('selHandle-tl'))) + t.getCenter(find.byKey(const Key('selHandle-br')))) / 2;
    await stylusDrag(t, rot, c + Offset((rot - c).distance, 0));
    tx = ed.doc.texts.values.single;
    expect(tx.angle, closeTo(pi / 2, .2));
    expect(find.text('Enderezar'), findsOneWidget);

    // se guarda con su escala y giro
    await settle(t, 1200);
    final nb = await savedNotebook('Texto libre');
    final st = Storage(root: root);
    await st.init();
    final saved = (await st.loadNotebook(nb)).texts.values.single;
    expect(saved.scale, closeTo(tx.scale, 1e-9));
    expect(saved.angle, closeTo(tx.angle, 1e-9));

    // deshacer: el giro y después la escala; vuelve a su lugar
    await t.tap(find.byTooltip('Deshacer'));
    await settle(t);
    expect(ed.doc.texts.values.single.angle, 0);
    await t.tap(find.byTooltip('Deshacer'));
    await settle(t);
    tx = ed.doc.texts.values.single;
    expect(tx.scale, 1);
    expect(tx.x, closeTo(x0, .01));
    expect(tx.y, closeTo(y0, .01));
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

  testWidgets('menú de la hoja: "Seleccionar todo" toma solo la hoja visible y "Seleccionar todo el cuaderno" todas; deshacer y rehacer andan', (t) async {
    await start(t);
    await createNotebook(t, 'Todo');
    final ed = editor(t);
    // 8 hojas con un trazo en cada una
    while (ed.doc.sheetCount < 8) {
      ed.doc.addSheet();
    }
    for (var k = 0; k < 8; k++) {
      final st = Stroke('st$k', 'pen', '#22211e', 2.6, [100, k * kSheetStep + 200, .5, 500, k * kSheetStep + 200, .5]);
      ed.doc.strokes[st.id] = st;
      ed.doc.markDirtyElement(st);
    }
    // ignore: invalid_use_of_protected_member
    ed.setState(() {});
    await settle(t, 800);
    expect(ed.visibleSheet, 0);
    ed.insertItem(Item('nota', 'sticky', 0, 0, 300, 200, text: 'apunte')); // algo para deshacer, en la hoja visible
    await settle(t, 600);

    Future<void> menu(String item) async {
      final g = await t.startGesture(sheetCenter(t) + const Offset(0, 250)); // debajo de la nota
      final end = DateTime.now().add(const Duration(milliseconds: 750));
      while (DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await t.pump();
      }
      await g.up();
      await settle(t, 500);
      await t.tap(find.text(item));
      await settle(t, 1500);
    }

    await menu('Seleccionar todo');
    expect(ed.sel.strokes, {'st0'}, reason: 'solo lo de la hoja visible');
    expect(ed.sel.items, {'nota'});
    expect(ed.sel.texts, isEmpty);

    await menu('Seleccionar todo el cuaderno');
    expect(ed.sel.strokes, {for (var k = 0; k < 8; k++) 'st$k'}, reason: 'todas las hojas');
    expect(ed.sel.items, {'nota'});

    await t.tap(find.byTooltip('Deshacer'));
    await settle(t, 600);
    expect(ed.doc.items.containsKey('nota'), isFalse);
    expect(ed.doc.strokes.length, 8, reason: 'deshacer la nota no toca los trazos');
    await t.tap(find.byTooltip('Rehacer'));
    await settle(t, 600);
    expect(ed.doc.items.containsKey('nota'), isTrue);
  });

  testWidgets('Exportar: una sola opción con PDF, PNG y .opennote', (t) async {
    await start(t);
    await createNotebook(t, 'Exporta');
    for (var i = 0; i < 2; i++) {
      await t.tap(find.byKey(const Key('insert')));
      await settle(t);
      await t.tap(find.text('Hoja nueva'));
      await settle(t, 800);
    }
    // dentro del cuaderno: el menú ⋮ tiene una sola entrada "Exportar" (sin "Guardar como" ni el .opennote suelto)
    await t.tap(find.byKey(const Key('more')));
    await settle(t);
    expect(find.text('Exportar'), findsOneWidget);
    expect(find.text('Guardar como'), findsNothing);
    expect(find.text('Exportar cuaderno (.opennote)'), findsNothing);
    await t.tap(find.text('Exportar'));
    await settle(t, 600);
    for (final k in ['pdf', 'sheet', 'sheetpng', 'png', 'opennote']) {
      expect(find.byKey(Key('export-$k')), findsOneWidget, reason: 'opción $k');
    }
    // "Imágenes (PNG)" exporta todo el cuaderno: un .zip con un PNG por hoja (el diálogo del sistema se reemplaza)
    Uint8List? zipBytes;
    bool? wasZip;
    final savedImages = saveImages;
    saveImages = (bytes, name, zip) async {
      zipBytes = bytes;
      wasZip = zip;
      return true;
    };
    addTearDown(() => saveImages = savedImages);
    await t.tap(find.byKey(const Key('export-png')));
    for (var i = 0; i < 100 && zipBytes == null; i++) {
      await settle(t, 100);
    }
    expect(zipBytes, isNotNull);
    expect(wasZip, isTrue);
    final entries = ZipDecoder().decodeBytes(zipBytes!).where((f) => f.isFile).toList();
    expect(entries.map((f) => f.name), ['Exporta - hoja 01.png', 'Exporta - hoja 02.png', 'Exporta - hoja 03.png']);
    for (final f in entries) {
      expect(f.content.take(4).toList(), [0x89, 0x50, 0x4E, 0x47], reason: '${f.name} es un PNG');
    }
    await settle(t, 600);
    await t.tap(find.byKey(const Key('more')));
    await settle(t);
    await t.tap(find.text('Exportar'));
    await settle(t, 600);
    await t.tapAt(const Offset(10, 10)); // cierra la hoja sin guardar nada
    await settle(t, 600);
    expect(find.byKey(const Key('export-pdf')), findsNothing);

    // desde la biblioteca: mismas opciones menos "PDF de esta hoja"
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
    await t.longPress(find.byKey(const Key('nb-Exporta')));
    await settle(t, 600);
    expect(find.text('Exportar a PDF'), findsNothing);
    await t.tap(find.byKey(const Key('exportNotebook')));
    await settle(t, 600);
    for (final k in ['pdf', 'png', 'opennote']) {
      expect(find.byKey(Key('export-$k')), findsOneWidget, reason: 'opción $k');
    }
    expect(find.byKey(const Key('export-sheet')), findsNothing);
    expect(find.byKey(const Key('export-sheetpng')), findsNothing);
    await t.tapAt(const Offset(10, 10));
    await settle(t, 600);
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
    // (no es el único: la app crea "Mi cuaderno" de ejemplo al arrancar y, con la nube vacía, también sube)
    expect(remote.paths.where((p) => p.endsWith('/notebook.json')), isNotEmpty);

    // otro "dispositivo" (otra carpeta) baja lo subido
    final other = await Directory.systemTemp.createTemp('apuntes_test_otro');
    addTearDown(() => other.delete(recursive: true));
    final s2 = Storage(root: other);
    await s2.init();
    await SyncEngine(s2, remote, account: 'x').sync();
    expect((await s2.loadIndex()).notebooks.map((n) => n.name), contains('Para nube'));
    expect(t.takeException(), isNull);
  });

  testWidgets('sincronización: borrar un cuaderno sincronizado lo borra de la nube (remoto falso)', (t) async {
    final remote = FakeRemoteStore();
    await t.pumpWidget(ApuntesApp(root: root, backend: FakeBackend(remote)));
    await settle(t, 1500);
    await createNotebook(t, 'Para borrar');
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
    Future<void> syncNow() async {
      await t.tap(find.byKey(const Key('libraryMenu')));
      await settle(t);
      await t.tap(find.byKey(const Key('syncMenu')));
      await settle(t, 600);
      if (find.byKey(const Key('syncConnect')).evaluate().isNotEmpty) {
        await t.tap(find.byKey(const Key('syncConnect')));
        for (var i = 0; i < 60 && find.byKey(const Key('syncNow')).evaluate().isEmpty; i++) {
          await settle(t, 100);
        }
      }
      await t.tap(find.byKey(const Key('syncNow')));
      await settle(t, 3000);
      await t.tapAt(const Offset(5, 5)); // cierra la hoja de sincronización
      await settle(t, 600);
    }

    await syncNow();
    expect(remote.paths.where((p) => p.endsWith('/notebook.json')), isNotEmpty);
    final before = remote.paths.where((p) => p.endsWith('/notebook.json')).length;
    expect(utf8.decode(remote.bytesOf('index.json')!), contains('Para borrar'));

    // mantener apretado el cuaderno → Borrar → confirmar → sincronizar
    await holdOn(t, find.byKey(const Key('nb-Para borrar')));
    await settle(t);
    await t.tap(find.text('Borrar'));
    await settle(t);
    await t.tap(find.byKey(const Key('confirmDelete')));
    await settle(t, 800);
    expect(find.byKey(const Key('nb-Para borrar')), findsNothing);
    await syncNow();
    expect(utf8.decode(remote.bytesOf('index.json')!), isNot(contains('Para borrar')), reason: 'el índice de la nube ya no lo tiene');
    expect(remote.paths.where((p) => p.endsWith('/notebook.json')).length, before - 1, reason: 'sus archivos se borraron de la nube');
    expect(t.takeException(), isNull);
  });

  testWidgets('sincronización en segundo plano: el interruptor aparece (solo en Android), viene encendido y se guarda', (t) async {
    await t.pumpWidget(ApuntesApp(root: root, backend: FakeBackend(FakeRemoteStore())));
    await settle(t, 1500);
    await t.tap(find.byKey(const Key('libraryMenu')));
    await settle(t);
    await t.tap(find.byKey(const Key('syncMenu')));
    await settle(t, 600);
    if (!Platform.isAndroid) {
      expect(find.byKey(const Key('syncBackground')), findsNothing, reason: 'fuera de Android no hay interruptor');
      return;
    }
    expect(t.widget<SwitchListTile>(find.byKey(const Key('syncBackground'))).value, isTrue, reason: 'por defecto encendido');
    await t.tap(find.byKey(const Key('syncBackground')));
    await settle(t, 600);
    expect(t.widget<SwitchListTile>(find.byKey(const Key('syncBackground'))).value, isFalse);
    expect(File('${root.path}/prefs.json').readAsStringSync(), matches(RegExp(r'"bgSync"\s*:\s*false')), reason: 'se guarda en prefs.json');
    await t.tap(find.byKey(const Key('syncBackground')));
    await settle(t, 600);
    expect(t.widget<SwitchListTile>(find.byKey(const Key('syncBackground'))).value, isTrue);
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

  testWidgets('sincronización: sección Cifrado y el diálogo de frase valida que coincidan', (t) async {
    final remote = FakeRemoteStore();
    await t.pumpWidget(ApuntesApp(root: root, backend: FakeBackend(remote)));
    await settle(t, 1500);
    await t.tap(find.byKey(const Key('libraryMenu')));
    await settle(t);
    await t.tap(find.byKey(const Key('syncMenu')));
    await settle(t, 600);
    expect(find.byKey(const Key('cryptoStatus')), findsNothing, reason: 'sin conectar no hay sección Cifrado');
    await t.tap(find.byKey(const Key('syncConnect')));
    for (var i = 0; i < 60 && find.byKey(const Key('cryptoEnable')).evaluate().isEmpty; i++) {
      await settle(t, 100);
    }
    expect(find.text('Cifrado'), findsOneWidget);
    expect(find.byKey(const Key('cryptoStatus')), findsOneWidget);
    expect(find.textContaining('Si olvidás la frase'), findsOneWidget);

    await t.tap(find.byKey(const Key('cryptoEnable')));
    await settle(t, 600);
    await t.enterText(find.byKey(const Key('cryptoPass1')), 'una frase larga');
    await t.enterText(find.byKey(const Key('cryptoPass2')), 'otra frase larga');
    await t.tap(find.byKey(const Key('cryptoDialogOk')));
    await settle(t, 400);
    expect(find.textContaining('no coinciden'), findsOneWidget);
    expect(find.byKey(const Key('cryptoPass1')), findsOneWidget, reason: 'el diálogo sigue abierto');
    expect(remote.has('crypto.json'), isFalse, reason: 'no se activó nada');
    expect(t.takeException(), isNull);
  });

  testWidgets('figuras inteligentes: un círculo a mano con el lápiz quieto se convierte, se agranda arrastrando, el interruptor la apaga (issue #3)', (t) async {
    await start(t);
    await createNotebook(t, 'Figuras');
    final p = docToScreen(t);
    final ed = editor(t);
    // todo dentro de la parte visible de la hoja (ver el test de la selección)
    final view = t.getRect(find.byType(PageEditor)), origin = p(Offset.zero);
    final visH = view.height / ed.scale;
    final cy = (view.top - origin.dy) / ed.scale + visH * .4, r = min(90.0, visH * .22);
    final center = Offset(400, cy);

    /// círculo a mano (40 puntos, ruido determinístico) y se queda quieto ~800 ms reales; devuelve el lápiz apoyado
    Future<TestGesture> circleAndHold() async {
      Offset pt(int i) {
        final a = 2 * pi * i / 40, k = 1 + .02 * sin(i * 2.3);
        return p(center + Offset(cos(a), sin(a)) * r * k);
      }

      final g = await t.startGesture(pt(0), kind: PointerDeviceKind.stylus);
      for (var i = 1; i <= 41; i++) {
        await g.moveTo(pt(i % 40 == 0 ? 0 : i));
        await t.pump(const Duration(milliseconds: 16));
      }
      final end = DateTime.now().add(const Duration(milliseconds: 800));
      while (DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await t.pump();
      }
      return g;
    }

    var g = await circleAndHold();
    expect(ed.snappedKind, ShapeKind.circle);
    final w0 = ed.live!.bounds.width;
    // alejar el lápiz del centro agranda la figura
    final from = p(center + Offset(r, 0));
    for (var i = 1; i <= 5; i++) {
      await g.moveTo(from + Offset(i * 12.0, 0));
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await settle(t);
    expect(ed.snappedKind, isNull, reason: 'al soltar se limpia');
    expect(ed.doc.strokes.length, 1);
    expect(ed.doc.strokes.values.single.bounds.width, greaterThan(w0 + 5));

    await t.tap(find.byTooltip('Deshacer'));
    await settle(t);
    expect(ed.doc.strokes, isEmpty);

    // apagar el interruptor en el panel del lápiz
    await t.tap(find.byTooltip('Lápiz · tocá de nuevo para opciones'));
    await settle(t);
    expect(ed.ts.shapeSnap, isTrue);
    await t.ensureVisible(find.byKey(const Key('shapeSnapSwitch')));
    await t.tap(find.byKey(const Key('shapeSnapSwitch')));
    await settle(t);
    expect(ed.ts.shapeSnap, isFalse);
    Navigator.of(t.element(find.byKey(const Key('shapeSnapSwitch')))).pop();
    await settle(t);
    expect(find.byKey(const Key('shapeSnapSwitch')), findsNothing);

    g = await circleAndHold();
    expect(ed.snappedKind, isNull);
    await g.up();
    await settle(t);
    expect(ed.doc.strokes.length, 1);
    final s = ed.doc.strokes.values.single;
    // a mano quedan los ~42 puntos del gesto; la figura limpia tiene uno cada 2 unidades (más de 100 con este radio)
    expect(s.n, inInclusiveRange(30, 60), reason: 'sigue siendo el trazo a mano');
  });

  testWidgets('índice: la herramienta Título marca tinta (letra reconocida) y texto, el panel numera por niveles y lleva a la hoja (issue #13)', (t) async {
    final saved = handwriting;
    handwriting = _FakeHandwriting('Introducción');
    addTearDown(() => handwriting = saved);
    await start(t);
    await createNotebook(t, 'Indice');
    final ed = editor(t);
    // Todo se acomoda en lo que se ve (como en 'selección: escalar con la esquina...'); se recalcula en cada paso
    // porque el scroll y el ancho del editor (con los paneles abiertos) cambian.
    Offset Function(double, double) mk() {
      final p = docToScreen(t);
      final view = t.getRect(find.byType(PageEditor)), origin = p(Offset.zero);
      final visH = view.height / ed.scale;
      // bien adentro de la hoja que se ve (no en el borde de abajo de la anterior ni en el hueco entre hojas)
      final top = max((view.top - origin.dy) / ed.scale + visH * .22, ed.visibleSheet * kSheetStep + 60.0),
          ky = (visH * .5 / 600).clamp(0.2, 1.0);
      return (x, y) => p(Offset(x, top + (y - 100) * ky));
    }

    String fieldText() => t.widget<TextField>(find.byKey(const Key('headingName'))).controller!.text;
    List<String?> entry(String id) => [
          for (final w in t.widgetList<Text>(find.descendant(of: find.byKey(Key('indexEntry-$id')), matching: find.byType(Text)))) w.data
        ];

    // hoja 1: un trazo marcado con la letra reconocida
    var q = mk();
    await stylusLine(t, q(200, 200), q(400, 200));
    expect(ed.doc.strokes.length, 1);
    final id1 = ed.doc.strokes.keys.single;
    await t.tap(find.byTooltip('Título para el índice'));
    await settle(t);
    await stylusDrag(t, q(150, 150), q(450, 260));
    await settle(t, 600);
    expect(find.byKey(const Key('headingName')), findsOneWidget);
    expect(fieldText(), 'Introducción');
    await t.tap(find.byKey(const Key('headingOk')));
    await settle(t, 600);
    final h1 = ed.doc.sheets[0].heads.single;
    expect(h1.ids, [id1]);

    // hoja 2: otro trazo, con nombre escrito y un nivel más
    await t.tap(find.byKey(const Key('pagesBtn')));
    await settle(t, 600);
    await t.tap(find.byKey(const Key('addPage')));
    await settle(t, 800);
    await t.tap(find.byKey(const Key('pagesBtn'))); // cierra el panel
    await settle(t, 600);
    expect(ed.visibleSheet, 1);
    await t.tap(find.byTooltip('Lápiz · tocá de nuevo para opciones'));
    await settle(t);
    q = mk();
    await stylusLine(t, q(200, 200), q(400, 200));
    expect(ed.doc.strokes.length, 2);
    await t.tap(find.byTooltip('Título para el índice'));
    await settle(t);
    await stylusDrag(t, q(150, 150), q(450, 260));
    await settle(t, 600);
    await t.enterText(find.byKey(const Key('headingName')), 'Objetivos');
    await t.tap(find.byKey(const Key('headingLevelUp')));
    await t.pump();
    await t.tap(find.text('Agregar'));
    await settle(t, 600);
    final h2 = ed.doc.sheets[1].heads.single;

    // el panel: numerado por niveles, con la hoja a la derecha
    await t.tap(find.byKey(const Key('indexBtn')));
    await settle(t, 600);
    expect(entry(h1.id), ['1', 'Introducción', '1']);
    expect(entry(h2.id), ['1.1', 'Objetivos', '2']);

    // tocar una entrada lleva a su hoja
    expect(ed.visibleSheet, 1);
    await t.tap(find.byKey(Key('indexEntry-${h1.id}')));
    await settle(t, 1000);
    expect(ed.visibleSheet, 0);
    expect(t.widget<Text>(find.byKey(const Key('sheetCounter'))).data, '1 / 2');

    // borrar el primer trazo: su entrada desaparece (y Objetivos pasa a ser el 1)
    await t.tap(find.byTooltip('Seleccionar'));
    await settle(t);
    final p = docToScreen(t), r = ed.doc.strokes[id1]!.bounds;
    await stylusDrag(t, p(r.topLeft - const Offset(25, 25)), p(r.bottomRight + const Offset(25, 25)));
    expect(ed.sel.strokes, {id1});
    await t.tap(find.descendant(of: find.byType(SelectionMenu), matching: find.text('Eliminar')));
    await settle(t, 600);
    expect(ed.doc.strokes.length, 1);
    expect(find.byKey(Key('indexEntry-${h1.id}')), findsNothing);
    expect(entry(h2.id), ['1', 'Objetivos', '2']);

    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
  });
}

/// Reconocimiento de letra de mentira: siempre lee [text].
class _FakeHandwriting implements HandwritingRecognizer {
  final String text;
  _FakeHandwriting(this.text);
  @override
  Future<bool> isModelReady() async => true;
  @override
  Future<bool> ensureModel() async => true;
  @override
  Future<String?> recognize(List<Stroke> strokes) async => text;
}
