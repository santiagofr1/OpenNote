// Tests de la app corriendo en la tablet.
// Cada test usa una carpeta temporal propia: NO toca los cuadernos reales.
//
//   flutter test integration_test -d <id de la tablet>

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:apuntes/app.dart';
import 'package:apuntes/data/export.dart';
import 'package:apuntes/data/export_folder.dart';
import 'package:apuntes/data/media_import.dart';
import 'package:apuntes/data/sheet_codec.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/data/templates.dart';
import 'package:apuntes/data/system_clipboard.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/fake_audio_source.dart';
import 'package:apuntes/editor/handwriting.dart';
import 'package:apuntes/editor/link_open.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:apuntes/editor/pdf_page_image.dart';
import 'package:apuntes/editor/voice_recorder.dart';
import 'package:apuntes/editor/selection.dart';
import 'package:apuntes/editor/selection_menu.dart';
import 'package:apuntes/editor/viewport.dart' show kTopPad;
import 'package:apuntes/rendering/ink_layers.dart';
import 'package:apuntes/rendering/sheet_image_cache.dart';
import 'package:apuntes/rendering/text_layout.dart';
import 'package:apuntes/sync/fake_backend.dart';
import 'package:apuntes/sync/fake_remote_store.dart';
import 'package:apuntes/sync/sync_engine.dart';
import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' hide testWidgets;
import 'package:image/image.dart' as pimg;
import 'package:integration_test/integration_test.dart';
import 'package:pdf/pdf.dart' show PdfColor;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'tablet_sim.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  // en la PC (Linux) se simula la pantalla de la tablet; en la tablet no hace falta
  setUpAll(() async {
    if (!Platform.isAndroid) await loadRoboto();
  });
  setUp(() async => root = await Directory.systemTemp.createTemp('apuntes_test'));
  tearDown(() async {
    await Storage.settleWrites(); // que no llegue una escritura tardía a una carpeta ya borrada
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

  /// Una muestra de 30 dp de la paleta del panel (el primer color que no es favorito).
  Finder panelSwatch(String c) => find.byWidgetPredicate((w) => w is Container && w.constraints?.maxWidth == 30 && (w.decoration as BoxDecoration?)?.color == parseColor(c)).first;

  /// Toca [f] esperando a que aparezca (hasta 3 s) y llevándolo a la vista (diálogos más altos que la pantalla).
  Future<void> tapV(WidgetTester t, Finder f) async {
    for (var i = 0; i < 60 && f.evaluate().isEmpty; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.ensureVisible(f);
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(f);
  }

  Future<void> settle(WidgetTester t, [int ms = 400]) async {
    for (var i = 0; i < ms ~/ 50; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  /// En la PC, la pantalla de la tablet como se usa: horizontal y con la letra del sistema al 110 % (en Android, nada).
  /// Un test que fije su propio tamaño lo hace DESPUÉS.
  void sim(WidgetTester t) {
    if (!Platform.isAndroid) simulateTablet(t, physical: kTabletLandscape, textScale: kTabletTextScale);
  }

  Future<void> start(WidgetTester t) async {
    sim(t);
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

  testWidgets('barra: 4 colores favoritos fijos; tocar elige sin reordenar y mantener apretado abre el panel editando ese favorito (issue #23)', (t) async {
    await start(t);
    await createNotebook(t, 'Favoritos');
    final ts = editor(t).ts;
    final antes = List<String>.from(ts.favorites);
    await t.tap(find.byKey(const ValueKey('fav-2')));
    await settle(t);
    expect(ts.pen.color, antes[2]);
    expect(ts.favorites, antes, reason: 'elegir un favorito no los reordena');
    await t.longPress(find.byKey(const ValueKey('fav-0')));
    await settle(t);
    expect(find.byKey(const Key('colorSquare')), findsOneWidget, reason: 'mantener apretado abre el panel editando');
    expect(find.text('Listo'), findsOneWidget);
    final nuevo = palette.firstWhere((c) => !antes.contains(c));
    await t.ensureVisible(panelSwatch(nuevo));
    await t.tap(panelSwatch(nuevo));
    await settle(t);
    expect(ts.favorites, [nuevo, antes[1], antes[2], antes[3]]);
    // cerrar el panel
    await t.tapAt(const Offset(4, 600));
    await settle(t);
    expect(find.byKey(const Key('colorSquare')), findsNothing);
    // dejar los favoritos como estaban
    ts.setFavorite(0, antes[0]);
    editor(t).widget.onPrefsChanged();
    expect(ts.favorites, antes);
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

  testWidgets('hojas: borrar y deshacer, mover con el asa y deshacer, exportar e importar .vynote', (t) async {
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

    // exportar .vynote (el diálogo del sistema se reemplaza) e importarlo
    await t.tap(find.byKey(const Key('pagesBtn')));
    await settle(t, 600);
    Uint8List? saved;
    final savedSave = saveVynote, savedPick = Pickers.vynote;
    saveVynote = (bytes, name) async {
      saved = bytes;
      return true;
    };
    addTearDown(() {
      saveVynote = savedSave;
      Pickers.vynote = savedPick;
    });
    await openMore(t, 'Exportar');
    await t.tap(find.byKey(const Key('export-vynote')));
    await settle(t, 600);
    expect(saved, isNotNull);
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
    Pickers.vynote = () async => saved;
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

  testWidgets('texto con teclado como en Word: va donde se toca, tocar debajo sigue el bloque y Ctrl+Shift+H resalta (issue #16)', (t) async {
    await start(t);
    await createNotebook(t, 'Word');
    final ed = editor(t);
    await t.tap(find.byTooltip('Texto con teclado'));
    await settle(t, 600);
    FocusManager.instance.primaryFocus?.unfocus(); // el bloque vacío del botón se borra solo
    await settle(t, 300);
    expect(ed.doc.texts, isEmpty);

    // en el margen de arriba, antes de la primera línea del rayado
    ed.tapTextAt(const Offset(150, 20));
    await settle(t, 400);
    var b = ed.doc.texts.values.single;
    expect(b.y, lessThan(mmToUnits(24)), reason: 'queda arriba de la primera línea');
    await t.enterText(find.byKey(Key('para-${b.id}-0')), 'hola');
    await settle(t, 300);
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(t, 300);

    // justo debajo: sigue el mismo bloque
    final rect = textRect(b, ed.doc.lineAt(b.y));
    ed.tapTextAt(Offset(170, rect.bottom + 3));
    await settle(t, 400);
    expect(ed.doc.texts.length, 1);
    b = ed.doc.texts.values.single;
    expect(b.body.paras.length, 2);
    await t.enterText(find.byKey(Key('para-${b.id}-1')), 'chau');
    await settle(t, 300);

    // Ctrl+A y Ctrl+Shift+H: el párrafo queda resaltado
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyA);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyH);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await settle(t, 300);
    expect(b.body.paras[1].runs.every((r) => r.style.highlight != null), isTrue);
    expect(b.body.paras[1].text, 'chau');
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
    await tapV(t, find.byKey(const Key('pagesBtn')));
    await settle(t, 600);
    await tapV(t, find.byKey(const Key('addPage')));
    await settle(t, 800);

    // solo la hoja que se ve (la 2, que acaba de agregarse)
    await openMore(t, 'Estilo de hoja');
    await tapV(t, find.byKey(const Key('applySheet')));
    await tapV(t, find.byKey(const Key('size-a3')));
    await tapV(t, find.text('Cuadriculado'));
    await settle(t, 300);
    await tapV(t, find.byKey(const Key('spacing-7')));
    await tapV(t, find.byTooltip('Crema'));
    await settle(t);
    await tapV(t, find.byKey(const Key('styleOk')));
    await settle(t, 1200);

    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
    var nb = await savedNotebook('Estilo');
    expect([nb.sheets[0].bg, nb.sheets[0].spacing], ['lined', 8.0], reason: 'la otra hoja no cambia');
    expect([nb.sheets[1].bg, nb.sheets[1].paper, nb.sheets[1].spacing], ['grid', '#fbf3e0', 7.0]);
    expect([nb.bg, nb.spacing], ['lined', 8.0], reason: 'las hojas nuevas siguen igual');
    expect([nb.sheets[0].size, nb.sheets[1].size, nb.size], ['a4', 'a3', 'a4'], reason: 'el tamaño es por hoja');
    expect(textLine('grid', 7, size: 'a3'), lessThan(textLine('grid', 7)), reason: 'en A3 el renglón es más chico en unidades');

    // todo el cuaderno (es lo que viene marcado), y también las hojas nuevas
    await tapV(t, find.byKey(const Key('nb-Estilo')));
    await settle(t, 1200);
    await openMore(t, 'Estilo de hoja');
    await tapV(t, find.byKey(const Key('applyAll')));
    await tapV(t, find.byKey(const Key('size-a4'))); // se vuelve a A4 para todo el cuaderno
    await tapV(t, find.text('Rayado'));
    await settle(t, 300);
    await tapV(t, find.byKey(const Key('spacing-10')));
    await tapV(t, find.byTooltip('Celeste'));
    await settle(t);
    await tapV(t, find.byKey(const Key('styleOk')));
    await settle(t, 1200);

    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
    nb = await savedNotebook('Estilo');
    expect(nb.sheets.length, 2);
    expect([nb.bg, nb.paper, nb.spacing], ['lined', '#eaf3fb', 10.0], reason: 'también el estilo de las hojas nuevas');
    for (final sheet in nb.sheets) {
      expect([sheet.bg, sheet.paper, sheet.spacing, sheet.size], ['lined', '#eaf3fb', 10.0, 'a4']);
    }
  });

  testWidgets('estilo de hoja: en horizontal entra sin scroll, en dos columnas', (t) async {
    await start(t);
    // tablet en horizontal (1333 x 752 lógicos) con la letra del sistema al 110 %
    t.view.physicalSize = const Size(1333.4, 752) * t.view.devicePixelRatio;
    t.platformDispatcher.textScaleFactorTestValue = 1.1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    await settle(t);
    await createNotebook(t, 'Horizontal');
    await openMore(t, 'Estilo de hoja');

    final dialog = find.byType(AlertDialog);
    final scroll = find.descendant(of: dialog, matching: find.byType(Scrollable));
    final pos = t.state<ScrollableState>(scroll.first).position;
    expect(pos.maxScrollExtent, 0, reason: 'el diálogo entra entero, sin scroll');
    final screen = Offset.zero & (t.view.physicalSize / t.view.devicePixelRatio);
    for (final k in ['applyAll', 'styleOk']) {
      final r = t.getRect(find.byKey(Key(k)));
      expect(screen.contains(r.topLeft) && screen.contains(r.bottomRight), isTrue, reason: '$k dentro de la pantalla: $r');
    }
    final dx = (t.getCenter(find.byKey(const Key('size-a4'))).dx - t.getCenter(find.byKey(const Key('applyAll'))).dx).abs();
    expect(dx, greaterThan(200), reason: 'tamaño y "Aplicar a" van en columnas distintas');

    await t.tap(find.text('Cancelar'));
    await settle(t, 600);
    expect(t.takeException(), isNull);
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

  testWidgets('candado del zoom: un dedo no mueve la hoja y dos dedos sí', (t) async {
    await start(t);
    await createNotebook(t, 'Candado');
    final ed = editor(t);
    ed.widget.tools.zoomLocked = false;
    final c = sheetCenter(t);

    Future<void> drag(int fingers) async {
      final gs = [for (var i = 0; i < fingers; i++) await t.createGesture(kind: PointerDeviceKind.touch)];
      for (var i = 0; i < gs.length; i++) {
        await gs[i].down(c + Offset(i * 100.0, 200));
        await t.pump(const Duration(milliseconds: 30));
      }
      for (var s = 1; s <= 10; s++) {
        for (var i = 0; i < gs.length; i++) {
          await gs[i].moveTo(c + Offset(i * 100.0, 200 - s * 25.0));
        }
        await t.pump(const Duration(milliseconds: 16));
      }
      for (final g in gs) {
        await g.up();
      }
      await settle(t, 300);
    }

    await t.tap(find.byTooltip('Fijar el zoom'));
    await settle(t);
    expect(ed.widget.tools.zoomLocked, isTrue);
    final y0 = ed.scroll.offset;
    await drag(1);
    expect(ed.scroll.offset, y0, reason: 'un dedo no mueve la hoja con el candado');
    await drag(2);
    expect(ed.scroll.offset, greaterThan(y0 + 50), reason: 'dos dedos sí');
    await t.tap(find.byWidgetPredicate((w) => w is Tooltip && (w.message ?? '').startsWith('Zoom fijo')));
    await settle(t);
    expect(ed.widget.tools.zoomLocked, isFalse);
  });

  testWidgets('candado del zoom: al final, tirar con dos dedos y mantener agrega una hoja', (t) async {
    await start(t);
    await createNotebook(t, 'CandadoHoja');
    final ed = editor(t);
    ed.widget.tools.zoomLocked = false;
    await t.tap(find.byTooltip('Fijar el zoom'));
    await settle(t);
    expect(ed.widget.tools.zoomLocked, isTrue);
    ed.scroll.jumpTo(ed.scroll.position.maxScrollExtent); // al final de la última hoja
    await settle(t);
    final n0 = ed.doc.sheetCount, c = sheetCenter(t);

    final a = await t.createGesture(kind: PointerDeviceKind.touch);
    final b = await t.createGesture(kind: PointerDeviceKind.touch);
    await a.down(c + const Offset(-60, 200));
    await t.pump(const Duration(milliseconds: 30));
    await b.down(c + const Offset(60, 200));
    await t.pump(const Duration(milliseconds: 30));
    for (var s = 1; s <= 12; s++) {
      await a.moveTo(c + Offset(-60, 200 - s * 25.0));
      await b.moveTo(c + Offset(60, 200 - s * 25.0));
      await t.pump(const Duration(milliseconds: 16));
    }
    // mantener ~1,2 s (tiempo real) hasta que se llene el círculo
    final end = DateTime.now().add(const Duration(milliseconds: 1200));
    while (DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await t.pump();
    }
    await a.up();
    await b.up();
    await settle(t, 1200);
    expect(ed.doc.sheetCount, n0 + 1, reason: 'se agregó una hoja');

    await t.tap(find.byWidgetPredicate((w) => w is Tooltip && (w.message ?? '').startsWith('Zoom fijo')));
    await settle(t);
    expect(ed.widget.tools.zoomLocked, isFalse);
  });

  testWidgets('zoom en la PC: Ctrl + rueda agranda alrededor del cursor y la rueda sola scrollea', (t) async {
    await start(t);
    await createNotebook(t, 'Rueda');
    final ed = editor(t);
    ed.widget.tools.zoom = 1;
    ed.widget.tools.zoomLocked = false;
    final c = sheetCenter(t);
    final vp = find
        .descendant(of: find.byType(PageEditor), matching: find.byType(Listener))
        .evaluate()
        .map((e) => e.renderObject as RenderBox)
        .firstWhere((b) => b.hasSize && (b.size.height - ed.scroll.position.viewportDimension).abs() < .5);
    Offset off() => Offset(ed.hscroll.hasClients ? ed.hscroll.offset : 0, ed.scroll.offset);

    Future<void> wheel(double dy, Offset at) async {
      await t.sendEventToBinding(PointerScrollEvent(kind: PointerDeviceKind.mouse, position: at, scrollDelta: Offset(0, dy)));
      await settle(t, 300);
    }

    // rueda sola: scrollea y no cambia el zoom
    final z0 = ed.ts.zoom, y0 = ed.scroll.offset;
    await wheel(120, c);
    expect(ed.ts.zoom, z0, reason: 'la rueda sola no cambia el zoom');
    expect(ed.scroll.offset, greaterThan(y0 + 20), reason: 'la rueda sola scrollea');

    // Ctrl + rueda hacia arriba: agranda y deja quieto el punto bajo el cursor
    final p = c + const Offset(40, 60);
    final f = p - vp.localToGlobal(Offset.zero);
    final y1 = ed.scroll.offset, z1 = ed.ts.zoom;
    final before = ed.layout.toPage(f, off());
    await simulateKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await wheel(-120, p);
    expect(ed.ts.zoom, closeTo(z1 * exp(.24), .01), reason: 'Ctrl + rueda hacia arriba agranda');
    final after = ed.layout.toPage(f, off());
    expect((after - before).distance * ed.ts.zoom, lessThan(2), reason: 'el punto bajo el cursor no se mueve');
    expect(ed.scroll.offset, isNot(y1), reason: 'el scroll solo cambió para sostener el punto');

    // con el candado puesto, Ctrl + rueda no cambia el zoom
    await simulateKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.tap(find.byTooltip('Fijar el zoom'));
    await settle(t);
    expect(ed.ts.zoomLocked, isTrue);
    final fixed = ed.ts.zoom, yFixed = ed.scroll.offset;
    await simulateKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await wheel(-120, p);
    await simulateKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(ed.ts.zoom, fixed, reason: 'con el candado no hay zoom');
    expect(ed.scroll.offset, yFixed, reason: 'ni scroll con Ctrl');
    expect(t.takeException(), isNull);
  });

  testWidgets('pellizco después de poner y sacar el candado: el zoom crece parejo y la hoja no tiembla (#27)', (t) async {
    await start(t);
    await createNotebook(t, 'Pellizco');
    final ed = editor(t);
    ed.widget.tools.zoom = 1;
    ed.widget.tools.zoomLocked = false;
    await t.tap(find.byTooltip('Fijar el zoom'));
    await settle(t);
    await t.tap(find.byWidgetPredicate((w) => w is Tooltip && (w.message ?? '').startsWith('Zoom fijo')));
    await settle(t);
    expect(ed.widget.tools.zoomLocked, isFalse);

    final c = sheetCenter(t);
    final vp = find
        .descendant(of: find.byType(PageEditor), matching: find.byType(Listener))
        .evaluate()
        .map((e) => e.renderObject as RenderBox)
        .firstWhere((b) => b.hasSize && (b.size.height - ed.scroll.position.viewportDimension).abs() < .5);
    final f = c - vp.localToGlobal(Offset.zero);
    Offset off() => Offset(ed.hscroll.hasClients ? ed.hscroll.offset : 0, ed.scroll.offset);
    final p0 = ed.layout.toPage(f, off());
    final a = await t.createGesture(kind: PointerDeviceKind.touch);
    final b = await t.createGesture(kind: PointerDeviceKind.touch);
    await a.down(c - const Offset(100, 0));
    await b.down(c + const Offset(100, 0));
    await t.pump(const Duration(milliseconds: 16));
    var last = ed.widget.tools.zoom;
    for (var i = 1; i <= 20; i++) {
      // se mide al terminar de pintar el cuadro, antes de cualquier corrección posterior
      double? err;
      WidgetsBinding.instance.addPostFrameCallback((_) => err = (ed.layout.scrollFor(p0, f) - off()).distance);
      await a.moveTo(c - Offset(100 + 10.0 * i, 0));
      await b.moveTo(c + Offset(100 + 10.0 * i, 0));
      await t.pump(const Duration(milliseconds: 16));
      expect(ed.widget.tools.zoom, greaterThanOrEqualTo(last - 1e-9), reason: 'zoom monótono (cuadro $i)');
      last = ed.widget.tools.zoom;
      expect(err, isNotNull);
      expect(err!, lessThan(3), reason: 'la hoja no se corre del foco (cuadro $i)');
    }
    await a.up();
    await b.up();
    await settle(t, 300);
    expect(ed.widget.tools.zoom, greaterThan(2));
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

  testWidgets('PDF importado: 50 páginas en menos de 2 s, entran en la hoja que se ve, se dibujan y se exportan (rápido, sin imágenes)',
      (t) async {
    final pdfBytes = (await t.runAsync(() async {
      final d = pw.Document();
      for (var i = 1; i <= 50; i++) {
        d.addPage(pw.Page(
          margin: const pw.EdgeInsets.all(40),
          build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Tema $i', style: pw.TextStyle(fontSize: 40, fontWeight: pw.FontWeight.bold)),
            for (var k = 0; k < 20; k++) pw.Paragraph(text: 'Linea $k de la pagina $i, con bastante texto para que se note.'),
          ]),
        ));
      }
      return Uint8List.fromList(await d.save());
    }))!;
    final savedPick = Pickers.pdf;
    addTearDown(() => Pickers.pdf = savedPick);
    Pickers.pdf = () async => (pdfBytes, 'Apuntes');
    await start(t);
    await createNotebook(t, 'PDF importado');
    final ed = editor(t);
    ed.doc.addSheet();
    ed.doc.addSheet();
    // un trazo en la hoja 2 (índice 1) para saber adónde va a parar
    final mark = Stroke('marca', 'pen', '#22211e', 2.6, [100, kSheetStep + 200, .5, 500, kSheetStep + 200, .5]);
    ed.doc.strokes[mark.id] = mark;
    ed.doc.markDirtyElement(mark);
    // ignore: invalid_use_of_protected_member
    ed.setState(() {});
    await settle(t, 600);
    ed.scrollToSheet(1, animate: false);
    await settle(t, 800);
    expect(ed.mostVisibleSheet, 1);
    final oldSheetId = ed.doc.sheets[1].id;
    expect(ed.doc.sheetCount, 3);

    final sw = Stopwatch()..start();
    await t.tap(find.byKey(const Key('insert')));
    await settle(t);
    await t.tap(find.text('PDF'));
    while (ed.doc.sheetCount < 53 && sw.elapsedMilliseconds < 10000) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await t.pump();
    }
    final ms = sw.elapsedMilliseconds;
    debugPrint('PDFIMPORT 50 paginas: $ms ms');
    expect(ed.doc.sheetCount, 3 + 50);
    expect(ms, lessThan(2000), reason: 'importar no rasteriza nada');
    await settle(t, 600);

    // la primera página quedó EN la hoja que se veía; la que se veía (y la marca) se corrió al final del PDF
    final first = ed.doc.items.values.where((i) => ed.doc.sheetOfY(i.y) == 1).single;
    expect([first.type, first.page], ['pdf', 0]);
    expect(ed.doc.sheets[51].id, oldSheetId, reason: 'la hoja que se veía quedó después del PDF');
    expect(ed.doc.sheetOfY(ed.doc.strokes['marca']!.bounds.top), 51);
    final media = Directory('${root.path}/media').listSync().map((e) => e.path.split('/').last).toList();
    expect(media.where((n) => n.endsWith('.pdf')).length, 1, reason: 'un solo PDF para las 50 páginas');
    expect(media.where((n) => n.endsWith('.png')), isEmpty);

    // la página visible termina mostrando imagen
    final shown = find.descendant(of: find.byType(PdfPageImage), matching: find.byType(RawImage));
    final sw2 = Stopwatch()..start();
    while (shown.evaluate().isEmpty && sw2.elapsedMilliseconds < 3000) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await t.pump();
    }
    expect(shown, findsAtLeastNWidgets(1), reason: 'la página se dibuja a demanda');

    // exportar la hoja: la página sale dibujada (no todo blanco)
    final s = Storage(root: root);
    await s.init();
    final dark = await t.runAsync(() async {
      final images = await loadImages(s, ed.doc, sheet: 1);
      final png = await renderSheetPng(ed.doc, 1, images: images);
      for (final im in images.values) {
        im.dispose();
      }
      final img = await decodeImage(png);
      final px = (await img.toByteData())!.buffer.asUint8List();
      img.dispose();
      for (var i = 0; i < px.length; i += 4) {
        if (px[i] < 100 && px[i + 1] < 100 && px[i + 2] < 100) return true;
      }
      return false;
    });
    expect(dark, isTrue, reason: 'la hoja exportada trae el texto del PDF');

    await t.tap(find.byTooltip('Deshacer'));
    await settle(t, 800);
    expect(ed.doc.sheetCount, 3, reason: 'importar es un solo paso de deshacer');
  });

  testWidgets('PDF importado: la miniatura del cuaderno en la biblioteca muestra la página (no queda en blanco)', (t) async {
    final pdfBytes = (await t.runAsync(() async {
      final d = pw.Document();
      d.addPage(pw.Page(
        margin: const pw.EdgeInsets.all(40),
        build: (_) => pw.Container(color: const PdfColor.fromInt(0xFF3B82F6), width: 400, height: 600),
      ));
      return Uint8List.fromList(await d.save());
    }))!;
    final savedPick = Pickers.pdf;
    addTearDown(() => Pickers.pdf = savedPick);
    Pickers.pdf = () async => (pdfBytes, 'Azul');
    await start(t);
    await createNotebook(t, 'Miniatura PDF');
    await t.tap(find.byKey(const Key('insert')));
    await settle(t);
    await t.tap(find.text('PDF'));
    await settle(t, 1500);
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);

    // la miniatura pide la página de PDF a demanda: se espera a que aparezca algo que no sea papel blanco
    final card = find.byKey(const Key('nb-Miniatura PDF'));
    expect(card, findsOneWidget);
    final cover = find.descendant(of: card, matching: find.byType(RepaintBoundary)).first;
    var colored = false;
    final sw = Stopwatch()..start();
    while (!colored && sw.elapsedMilliseconds < 5000) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await t.pump();
      final b = t.renderObject<RenderRepaintBoundary>(cover);
      final data = await t.runAsync(() async {
        final img = await b.toImage();
        final bytes = (await img.toByteData())!;
        img.dispose();
        return bytes;
      });
      for (var i = 0; i < data!.lengthInBytes; i += 4) {
        final r = data.getUint8(i), g = data.getUint8(i + 1), bl = data.getUint8(i + 2);
        if (bl > r + 60 && bl > g) {
          colored = true; // hay azul: la página del PDF
          break;
        }
      }
    }
    expect(colored, isTrue, reason: 'la miniatura muestra la página del PDF importado, no un recuadro blanco');
  });

  testWidgets('PDF importado: la goma sobre la página pinta un corrector del color del fondo', (t) async {
    final pdfBytes = (await t.runAsync(() async {
      final d = pw.Document();
      d.addPage(pw.Page(
        pageTheme: pw.PageTheme(
          margin: const pw.EdgeInsets.all(40),
          buildBackground: (_) => pw.FullPage(ignoreMargins: true, child: pw.Container(color: const PdfColor.fromInt(0xFFFFF0C0))),
        ),
        build: (_) => pw.Text('Tema 1', style: pw.TextStyle(fontSize: 40)),
      ));
      return Uint8List.fromList(await d.save());
    }))!;
    final savedPick = Pickers.pdf;
    addTearDown(() => Pickers.pdf = savedPick);
    Pickers.pdf = () async => (pdfBytes, 'Fondo');
    await start(t);
    await createNotebook(t, 'Goma en PDF');
    final ed = editor(t);
    await t.tap(find.byKey(const Key('insert')));
    await settle(t);
    await t.tap(find.text('PDF'));
    await settle(t, 1500);
    final pdf = ed.doc.items.values.firstWhere((i) => i.type == 'pdf');
    await settle(t, 800);

    // goma (punta de goma del lápiz) por el medio de la página, lejos del texto
    final toScreen = docToScreen(t);
    // a la altura del centro de lo que se ve (en horizontal la hoja A4 no entra entera en la pantalla)
    final cy = sheetCenter(t).dy;
    final a = Offset(toScreen(Offset(pdf.x + pdf.w * .2, 0)).dx, cy), b = Offset(toScreen(Offset(pdf.x + pdf.w * .8, 0)).dx, cy);
    final g = await t.startGesture(a, kind: PointerDeviceKind.invertedStylus);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(a, b, i / 10)!);
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await settle(t, 300);
    final covers = [for (final s in ed.doc.strokes.values) if (s.k == kCoverTip) s];
    expect(covers, hasLength(1), reason: 'la goma sobre el PDF deja un corrector');

    // el color real llega (primero es blanco) y es el del fondo
    final sw = Stopwatch()..start();
    while (ed.doc.strokes[covers.single.id]!.c == '#ffffff' && sw.elapsedMilliseconds < 5000) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await t.pump();
    }
    final cover = ed.doc.strokes[covers.single.id]!;
    expect(cover.c, isNot('#ffffff'));

    // exportada la hoja, el centro del trazo es del color del fondo
    final s = Storage(root: root);
    await s.init();
    final sheet = ed.doc.sheetOfY(pdf.y);
    final px = await t.runAsync(() async {
      final images = await loadImages(s, ed.doc, sheet: sheet);
      final png = await renderSheetPng(ed.doc, sheet, images: images);
      for (final im in images.values) {
        im.dispose();
      }
      final img = await decodeImage(png);
      final data = (await img.toByteData())!.buffer.asUint8List();
      final k = img.width / kW;
      final cx = (cover.pts[0] + cover.pts[cover.pts.length - 3]) / 2, cy = cover.pts[1] - sheet * kSheetStep;
      final i = ((cy * k).round() * img.width + (cx * k).round()) * 4;
      final out = [data[i], data[i + 1], data[i + 2]];
      img.dispose();
      return out;
    });
    final want = cover.color.toARGB32();
    expect(px![0], closeTo((want >> 16) & 0xFF, 6));
    expect(px[1], closeTo((want >> 8) & 0xFF, 6));
    expect(px[2], closeTo(want & 0xFF, 6));
    expect((px[0] - 0xFF).abs() + (px[2] - 0xFF).abs(), greaterThan(30), reason: 'no es blanco: es el fondo del PDF');
  });

  testWidgets('índice: la herramienta Título marca un renglón impreso de una página de PDF y lo sugiere del texto (issue #41)', (t) async {
    final pdfBytes = (await t.runAsync(() async {
      final d = pw.Document();
      d.addPage(pw.Page(
        margin: const pw.EdgeInsets.all(40),
        build: (_) => pw.Text('Capitulo Uno', style: pw.TextStyle(fontSize: 40)),
      ));
      return Uint8List.fromList(await d.save());
    }))!;
    final savedPick = Pickers.pdf;
    addTearDown(() => Pickers.pdf = savedPick);
    Pickers.pdf = () async => (pdfBytes, 'Libro');
    await start(t);
    await createNotebook(t, 'Indice PDF');
    final ed = editor(t);
    await t.tap(find.byKey(const Key('insert')));
    await settle(t);
    await t.tap(find.text('PDF'));
    await settle(t, 1500);
    final pdf = ed.doc.items.values.firstWhere((i) => i.type == 'pdf');
    await settle(t, 800);

    // recuadro sobre el renglón impreso (arriba de la página A4: 595 x 842 pt, texto entre los 40 y los 90 pt)
    await t.tap(find.byTooltip('Título para el índice'));
    await settle(t);
    final toScreen = docToScreen(t);
    await stylusDrag(t, toScreen(Offset(pdf.x + pdf.w * .03, pdf.y + pdf.h * .03)),
        toScreen(Offset(pdf.x + pdf.w * .9, pdf.y + pdf.h * .12)));
    await settle(t, 800);
    expect(find.byKey(const Key('headingName')), findsOneWidget);
    expect(t.widget<TextField>(find.byKey(const Key('headingName'))).controller!.text, 'Capitulo Uno');
    await t.tap(find.byKey(const Key('headingOk')));
    await settle(t, 600);

    final h = ed.doc.sheets[ed.doc.sheetOfY(pdf.y)].heads.single;
    expect(h.ids, [pdf.id]);
    expect(h.box, isNotNull);
    expect(h.y, lessThan(pdf.h * .12), reason: 'la marca queda en el renglón, no arriba de toda la página');

    await t.tap(find.byKey(const Key('indexBtn')));
    await settle(t, 600);
    expect(find.byKey(Key('indexEntry-${h.id}')), findsOneWidget);
    expect(find.descendant(of: find.byKey(Key('indexEntry-${h.id}')), matching: find.text('Capitulo Uno')), findsOneWidget);
  });

  testWidgets('la página de un PDF no se selecciona ni se mueve con el dedo (issue #42)', (t) async {
    final pdfBytes = (await t.runAsync(() async {
      final d = pw.Document();
      d.addPage(pw.Page(build: (_) => pw.Text('Hola', style: pw.TextStyle(fontSize: 40))));
      return Uint8List.fromList(await d.save());
    }))!;
    final savedPick = Pickers.pdf;
    addTearDown(() => Pickers.pdf = savedPick);
    Pickers.pdf = () async => (pdfBytes, 'Libro');
    await start(t);
    await createNotebook(t, 'Mover PDF');
    final ed = editor(t);
    await t.tap(find.byKey(const Key('insert')));
    await settle(t);
    await t.tap(find.text('PDF'));
    await settle(t, 1500);
    final pdf = ed.doc.items.values.firstWhere((i) => i.type == 'pdf');
    final x0 = pdf.x, y0 = pdf.y;
    final p = docToScreen(t);
    final c = p(Offset(pdf.x + pdf.w / 2, pdf.y + pdf.h / 2));

    // mantener con el dedo y arrastrar: la página no se mueve ni queda elegida
    final g = await t.startGesture(c, kind: PointerDeviceKind.touch);
    await t.pump(const Duration(milliseconds: 700));
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(c + Offset(12.0 * i, 0));
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await settle(t, 400);
    expect((pdf.x, pdf.y), (x0, y0));
    expect(ed.selI, isEmpty);

    // con la herramienta seleccionar, un toque sobre el PDF tampoco lo elige
    await t.tap(find.byKey(const ValueKey('tool-select')));
    await settle(t);
    final g2 = await t.startGesture(c, kind: PointerDeviceKind.stylus);
    await t.pump(const Duration(milliseconds: 50));
    await g2.up();
    await settle(t, 300);
    expect(ed.selI, isEmpty);
    expect((pdf.x, pdf.y), (x0, y0));
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

  testWidgets('exportar carpeta: un .zip con una carpeta por cuaderno y sus PNG', (t) async {
    await start(t);
    await createNotebook(t, 'Apuntes'); // se abre solo: dibujar un trazo y volver
    await stylusLine(t, sheetCenter(t) + const Offset(-100, 0), sheetCenter(t) + const Offset(100, 40));
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
    await createFolder(t, 'Facultad');
    await holdOn(t, find.byKey(const Key('nb-Apuntes')));
    await settle(t);
    await t.tap(find.byKey(const Key('moveTo')));
    await settle(t);
    await t.tap(find.byKey(const Key('moveTarget-Facultad')));
    await settle(t, 800);

    Uint8List? zipBytes;
    String? zipName;
    final savedZip = saveFolderZip;
    saveFolderZip = (zip, name) async {
      zipBytes = await zip.readAsBytes();
      zipName = name;
      return true;
    };
    addTearDown(() => saveFolderZip = savedZip);
    await holdOn(t, find.byKey(const Key('folder-Facultad')));
    await settle(t);
    await t.tap(find.byKey(const Key('exportFolder')));
    await settle(t, 600);
    await t.tap(find.byKey(const Key('folderExport-png')));
    for (var i = 0; i < 200 && zipBytes == null; i++) {
      await settle(t, 100);
    }
    expect(zipBytes, isNotNull);
    expect(zipName, 'Facultad');
    final entries = ZipDecoder().decodeBytes(zipBytes!).where((f) => f.isFile).toList();
    expect(entries.map((f) => f.name), ['Facultad/Apuntes/Apuntes - hoja 01.png']);
    expect(entries.single.content.take(4).toList(), [0x89, 0x50, 0x4E, 0x47]);
    // el aviso sale cuando saveFolderZip devuelve y se borra el temporal (E/S real): se espera a que aparezca
    for (var i = 0; i < 40 && find.text('Carpeta exportada').evaluate().isEmpty; i++) {
      await settle(t, 100);
    }
    expect(find.text('Carpeta exportada'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('importar carpeta: el .zip exportado vuelve con sus subcarpetas y cuadernos', (t) async {
    await start(t);
    await createFolder(t, 'Facultad');
    await t.tap(find.byKey(const Key('folder-Facultad')));
    await settle(t, 800);
    await createNotebook(t, 'Apuntes');
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
    await createFolder(t, 'Sub');
    await t.tap(find.byKey(const Key('folder-Sub')));
    await settle(t, 800);
    await createNotebook(t, 'Parcial');
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
    await t.tap(find.byKey(const Key('up')));
    await settle(t, 800);
    await t.tap(find.byKey(const Key('up')));
    await settle(t, 800);

    Uint8List? zipBytes;
    final savedZip = saveFolderZip, savedPick = Pickers.folderZip;
    saveFolderZip = (zip, name) async {
      zipBytes = await zip.readAsBytes();
      return true;
    };
    addTearDown(() {
      saveFolderZip = savedZip;
      Pickers.folderZip = savedPick;
    });
    await holdOn(t, find.byKey(const Key('folder-Facultad')));
    await settle(t);
    await t.tap(find.byKey(const Key('exportFolder')));
    await settle(t, 600);
    await t.tap(find.byKey(const Key('folderExport-vynote')));
    for (var i = 0; i < 200 && zipBytes == null; i++) {
      await settle(t, 100);
    }
    expect(zipBytes, isNotNull);
    await settle(t, 600);

    Pickers.folderZip = () async => zipBytes;
    await t.tap(find.byKey(const Key('new')));
    await settle(t);
    await t.tap(find.byKey(const Key('importFolder')));
    for (var i = 0; i < 100 && find.textContaining('importada').evaluate().isEmpty; i++) {
      await settle(t, 100);
    }
    expect(find.textContaining('importada'), findsOneWidget);
    expect(find.byKey(const Key('folder-Facultad (2)')), findsOneWidget);
    await t.tap(find.byKey(const Key('folder-Facultad (2)')));
    await settle(t, 800);
    // la carpeta es nueva: los cuadernos conservan su nombre (los repetidos solo cuentan dentro de la misma carpeta)
    expect(find.byKey(const Key('nb-Apuntes')), findsOneWidget);
    expect(find.byKey(const Key('folder-Sub')), findsOneWidget);
    await t.tap(find.byKey(const Key('folder-Sub')));
    await settle(t, 800);
    expect(find.byKey(const Key('nb-Parcial')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

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
    await stylusDrag(t, rot, c + Offset(r, 0), during: () {
      expect(find.byKey(const Key('rotateAngleText')), findsOneWidget, reason: 'mientras se rota se ven los grados');
      expect((t.widget(find.byKey(const Key('rotateAngleText'))) as Text).data, endsWith('°'));
    });
    expect(find.byKey(const Key('rotateAngleText')), findsNothing, reason: 'al soltar desaparece la etiqueta');
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

  testWidgets('#28: llevar una selección al borde de abajo desplaza el cuaderno', (t) async {
    await start(t);
    await createNotebook(t, 'BordeAuto');
    final ed = editor(t);
    for (var i = 0; i < 2; i++) {
      ed.doc.nb.sheets.add(ed.doc.nb.newSheet()); // varias hojas: hay hasta dónde bajar
    }
    final st = Stroke('st28', 'pen', '#22211e', 2.6, [150, 200, .5, 450, 200, .5]);
    ed.doc.strokes[st.id] = st;
    ed.doc.markDirtyElement(st);
    // ignore: invalid_use_of_protected_member
    ed.setState(() {});
    await settle(t, 800);

    await t.tap(find.byTooltip('Seleccionar'));
    await settle(t);
    final p = docToScreen(t), view = t.getRect(find.byType(PageEditor));
    final before = st.bounds, y0 = ed.scroll.offset;
    await stylusDrag(t, p(before.topLeft - const Offset(25, 25)), p(before.bottomRight + const Offset(25, 25)));
    expect(ed.sel.strokes, {st.id});

    // arrastrar el trazo hasta 20 px del borde de abajo y quedarse ahí ~1 s (tiempo real)
    final a = p(before.center), b = Offset(a.dx, view.bottom - 20);
    final g = await t.startGesture(a, kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(a, b, i / 10)!);
      await t.pump(const Duration(milliseconds: 16));
    }
    // quieto ~2,5 s, pero temblando como el lápiz de verdad: cada temblor no lo devuelve a la pantalla de arriba
    final end = DateTime.now().add(const Duration(milliseconds: 2500));
    var j = 0;
    while (DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await g.moveBy(Offset((j++).isEven ? .5 : -.5, 0));
      await t.pump();
    }
    final y1 = ed.scroll.offset;
    await g.up();
    await settle(t, 600);
    expect(y1, greaterThan(y0 + 100), reason: 'el cuaderno bajó solo');
    final moved = ed.doc.strokes[st.id]!.bounds;
    expect(moved.top, greaterThan(kSheetStep), reason: 'pasó a la hoja siguiente');
    expect(moved.top * ed.scale - ed.scroll.offset, greaterThan(0), reason: 'el trazo quedó a la vista');
    expect(moved.top, greaterThan(before.top + (b.dy - a.dy) / ed.scale + 50), reason: 'viajó con la hoja');
    final yEnd = ed.scroll.offset;
    await settle(t, 300);
    expect(ed.scroll.offset, yEnd, reason: 'al soltar el scroll para');

    // deshacer: el trazo vuelve (no cambia los casos siguientes)
    await t.tap(find.byTooltip('Deshacer'));
    await settle(t);
    expect(ed.doc.strokes[st.id]!.bounds, before);
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

  testWidgets('menú de la hoja: solo "Pegar acá", y solo si hay algo copiado (issue #25)', (t) async {
    // el portapapeles del sistema de la tablet puede tener una imagen copiada: acá se lo da por vacío
    final hasImg = SystemClipboard.hasImage;
    SystemClipboard.hasImage = () async => false;
    addTearDown(() => SystemClipboard.hasImage = hasImg);
    await start(t);
    await createNotebook(t, 'Todo');
    final ed = editor(t);
    final st = Stroke('st0', 'pen', '#22211e', 2.6, [100, 200, .5, 500, 200, .5]);
    ed.doc.strokes[st.id] = st;
    ed.doc.markDirtyElement(st);
    // ignore: invalid_use_of_protected_member
    ed.setState(() {});
    await settle(t, 800);

    Future<void> mantener() async {
      final g = await t.startGesture(sheetCenter(t) + const Offset(0, 250)); // lugar vacío, debajo del trazo
      final end = DateTime.now().add(const Duration(milliseconds: 750));
      while (DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await t.pump();
      }
      await g.up();
      await settle(t, 500);
    }

    // portapapeles vacío: no hay menú
    await mantener();
    expect(find.text('Pegar acá'), findsNothing);

    // con algo copiado: solo "Pegar acá"
    ed.ts.clipboard.strokes = [st];
    await mantener();
    expect(find.text('Pegar acá'), findsOneWidget);
    for (final x in ['Escribir acá', 'Seleccionar todo', 'Seleccionar todo el cuaderno', 'Agregar hoja al final', 'Zoom al ancho de la hoja']) {
      expect(find.text(x), findsNothing, reason: '"$x" ya no está en el menú');
    }
    await t.tap(find.text('Pegar acá'));
    await settle(t, 1000);
    expect(ed.doc.strokes.length, 2, reason: 'pegó una copia del trazo');
  });

  testWidgets('Exportar: una sola opción con PDF, PNG y .vynote', (t) async {
    await start(t);
    await createNotebook(t, 'Exporta');
    for (var i = 0; i < 2; i++) {
      await t.tap(find.byKey(const Key('insert')));
      await settle(t);
      await t.tap(find.text('Hoja nueva'));
      await settle(t, 800);
    }
    // dentro del cuaderno: el menú ⋮ tiene una sola entrada "Exportar" (sin "Guardar como" ni el .vynote suelto)
    await t.tap(find.byKey(const Key('more')));
    await settle(t);
    expect(find.text('Exportar'), findsOneWidget);
    expect(find.text('Guardar como'), findsNothing);
    expect(find.text('Exportar cuaderno (.vynote)'), findsNothing);
    await t.tap(find.text('Exportar'));
    await settle(t, 600);
    for (final k in ['pdf', 'sheet', 'sheetpng', 'png', 'vynote']) {
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
    for (final k in ['pdf', 'png', 'vynote']) {
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
    sim(t);
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
    sim(t);
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
    sim(t);
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
    sim(t);
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
    sim(t);
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

    await tapV(t, find.byKey(const Key('cryptoEnable'))); // en horizontal queda abajo en la hoja: hay que llevarlo a la vista
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
  // ---------------- fondos y plantillas (#31, #33) ----------------
  testWidgets('fondos nuevos: milimetrado y ejes cartesianos (issue #31)', (t) async {
    await start(t);
    await createNotebook(t, 'Fondos');
    await openMore(t, 'Estilo de hoja');
    await tapV(t, find.byKey(const Key('bg-mm')));
    await tapV(t, find.byKey(const Key('applySheet')));
    await settle(t);
    await tapV(t, find.byKey(const Key('styleOk')));
    await settle(t, 800);
    expect(editor(t).doc.sheets[0].bg, 'mm');

    await openMore(t, 'Estilo de hoja');
    await tapV(t, find.byKey(const Key('bg-axes')));
    await tapV(t, find.byKey(const Key('applySheet')));
    await settle(t);
    await tapV(t, find.byKey(const Key('spacing-7')));
    await settle(t);
    await tapV(t, find.byKey(const Key('styleOk')));
    await settle(t, 800);
    expect([editor(t).doc.sheets[0].bg, editor(t).doc.sheets[0].spacing], ['axes', 7.0]);
  });

  testWidgets('plantillas incluidas: aplicar una a la hoja y crear una hoja nueva con otra (issue #33)', (t) async {
    await start(t);
    await createNotebook(t, 'Plantillas');
    await openMore(t, 'Estilo de hoja');
    await tapV(t, find.byKey(const Key('bg-cornell')));
    await tapV(t, find.byKey(const Key('applySheet')));
    await settle(t);
    await tapV(t, find.byKey(const Key('styleOk')));
    await settle(t, 800);
    expect(editor(t).doc.sheets[0].bg, 'cornell');

    await tapV(t, find.byKey(const Key('pagesBtn')));
    await settle(t, 600);
    await holdOn(t, find.byKey(const Key('thumb-1')));
    await settle(t, 500);
    await tapV(t, find.text('Hoja nueva con plantilla…'));
    await settle(t, 800);
    expect(find.text('Hoja nueva'), findsOneWidget);
    expect(find.byKey(const Key('applySheet')), findsNothing, reason: 'una hoja nueva no tiene "Aplicar a"');
    await tapV(t, find.byKey(const Key('bg-staff')));
    await settle(t);
    await tapV(t, find.byKey(const Key('styleOk')));
    await settle(t, 900);
    expect(editor(t).doc.sheetCount, 2);
    expect([editor(t).doc.sheets[0].bg, editor(t).doc.sheets[1].bg], ['cornell', 'staff']);
  });

  testWidgets('plantillas propias: guardar una hoja como plantilla y usarla de fondo (issue #33)', (t) async {
    await start(t);
    await createNotebook(t, 'Propias');
    final c = sheetCenter(t);
    await stylusLine(t, c, c + const Offset(200, 0));
    await tapV(t, find.byKey(const Key('pagesBtn')));
    await settle(t, 600);
    await holdOn(t, find.byKey(const Key('thumb-1')));
    await settle(t, 500);
    await tapV(t, find.text('Guardar como plantilla'));
    await settle(t, 600);
    await tapV(t, find.byKey(const Key('tplSave')));
    await settle(t, 2000);

    final st = Storage(root: root);
    await st.init();
    final list = await readTemplates(st);
    expect(list.length, 1);
    final tpl = list.single;
    expect(File('${root.path}/templates/${tpl.id}.json').existsSync(), isTrue);
    expect(st.media(tpl.file).existsSync(), isTrue);

    await openMore(t, 'Estilo de hoja');
    await tapV(t, find.byKey(Key('tpl-${tpl.id}')));
    await tapV(t, find.byKey(const Key('applySheet')));
    await settle(t);
    await tapV(t, find.byKey(const Key('styleOk')));
    await settle(t, 1000);
    final m = editor(t).doc.sheets[0];
    expect([m.bg, m.image], ['image', tpl.file]);
    expect(find.byKey(ValueKey('bgImage-${m.id}')), findsOneWidget);
  });

  testWidgets('plantilla desde una imagen de la tablet: todo el cuaderno y hojas nuevas (issue #33)', (t) async {
    final saved = Pickers.bgImage;
    addTearDown(() => Pickers.bgImage = saved);
    final png = File('${root.path}/fondo.png')..writeAsBytesSync(img.encodePng(img.Image(width: 300, height: 400)));
    Pickers.bgImage = () async => png;
    await start(t);
    await createNotebook(t, 'Imagen');
    await openMore(t, 'Estilo de hoja');
    await tapV(t, find.byKey(const Key('tplFromImage')));
    await settle(t, 1500);
    await tapV(t, find.byKey(const Key('applyAll')));
    await settle(t);
    await tapV(t, find.byKey(const Key('styleOk')));
    await settle(t, 1000);
    final ed = editor(t);
    final file = ed.doc.nb.image;
    expect(file, isNotNull);
    expect(ed.doc.nb.bg, 'image');
    for (final m in ed.doc.sheets) {
      expect([m.bg, m.image], ['image', file]);
    }
    await tapV(t, find.byKey(const Key('pagesBtn')));
    await settle(t, 600);
    await tapV(t, find.byKey(const Key('addPage')));
    await settle(t, 900);
    expect(ed.doc.sheetCount, 2);
    expect([ed.doc.sheets[1].bg, ed.doc.sheets[1].image], ['image', file], reason: 'la hoja nueva sale con la imagen');
  });

  // ---- pegar imagen del sistema (issue #32) ----
  Future<void> mantenerVacio(WidgetTester t) async {
    final g = await t.startGesture(sheetCenter(t) + const Offset(0, 250));
    final end = DateTime.now().add(const Duration(milliseconds: 750));
    while (DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await t.pump();
    }
    await g.up();
    await settle(t, 500);
  }

  void fakeClipboard(bool has, Uint8List? bytes) {
    final h = SystemClipboard.hasImage, r = SystemClipboard.readImage;
    SystemClipboard.hasImage = () async => has;
    SystemClipboard.readImage = () async => bytes;
    addTearDown(() {
      SystemClipboard.hasImage = h;
      SystemClipboard.readImage = r;
    });
  }

  testWidgets('pegar imagen del sistema desde el menú de la hoja (issue #32)', (t) async {
    final png = Uint8List.fromList(pimg.encodePng(pimg.Image(width: 300, height: 200)));
    fakeClipboard(true, png);
    await start(t);
    await createNotebook(t, 'PegarImg');
    final ed = editor(t);
    final antes = ed.doc.items.length;

    await mantenerVacio(t);
    expect(find.text('Pegar acá'), findsOneWidget, reason: 'con una imagen en el sistema hay menú aunque no se copió nada');
    await t.tap(find.text('Pegar acá'));
    await settle(t, 1200);
    expect(ed.doc.items.length, antes + 1);
    final it = ed.doc.items.values.firstWhere((i) => i.type == 'image');
    expect(it.w, 560);
    expect(it.h, closeTo(373.3, 1));
    expect(ed.widget.store.media(it.file!).existsSync(), isTrue, reason: 'la imagen quedó en media/');

    ed.undo();
    await settle(t, 600);
    expect(ed.doc.items.length, antes, reason: 'deshacer saca la imagen');
  });

  testWidgets('sin imagen en el sistema ni nada copiado no hay menú de pegar (issue #32)', (t) async {
    fakeClipboard(false, null);
    await start(t);
    await createNotebook(t, 'SinNada');
    await mantenerVacio(t);
    expect(find.text('Pegar acá'), findsNothing);
  });

  testWidgets('sin imagen en el sistema, "Pegar acá" pega lo copiado en la app (issue #32)', (t) async {
    fakeClipboard(false, null);
    await start(t);
    await createNotebook(t, 'PegarApp');
    final ed = editor(t);
    final st = Stroke('st0', 'pen', '#22211e', 2.6, [100, 200, .5, 500, 200, .5]);
    ed.doc.strokes[st.id] = st;
    ed.doc.markDirtyElement(st);
    // ignore: invalid_use_of_protected_member
    ed.setState(() {});
    await settle(t, 800);
    ed.ts.clipboard.strokes = [st];

    await mantenerVacio(t);
    expect(find.text('Pegar acá'), findsOneWidget);
    await t.tap(find.text('Pegar acá'));
    await settle(t, 1000);
    expect(ed.doc.strokes.length, 2, reason: 'pegó una copia del trazo');
    expect(ed.doc.items.values.where((i) => i.type == 'image'), isEmpty);
  });

  testWidgets('favoritos: Cambiar en el panel del lápiz y arrastrar en el cuadrado deja el color nuevo en el favorito 0 de la barra', (t) async {
    await start(t);
    await createNotebook(t, 'Selector');
    final ts = editor(t).ts;
    final antes = ts.favorites[0];
    await t.tap(find.byTooltip('Lápiz · tocá de nuevo para opciones'));
    await settle(t);
    await t.tap(find.byKey(const Key('favEdit')));
    await settle(t);
    final sq = find.byKey(const Key('colorSquare'));
    await t.ensureVisible(sq);
    await settle(t);
    await t.dragFrom(t.getTopLeft(sq) + const Offset(60, 40), const Offset(50, 60));
    await settle(t);
    final nuevo = ts.favorites[0];
    expect(nuevo, isNot(antes));
    expect(nuevo, ts.pen.color);
    await t.tapAt(const Offset(4, 600)); // cierra el panel
    await settle(t);
    expect(find.byKey(const Key('colorSquare')), findsNothing);
    expect(ts.favorites[0], nuevo);
    final dot = find.descendant(of: find.byKey(const ValueKey('fav-0')), matching: find.byWidgetPredicate((w) => w is Container && (w.decoration as BoxDecoration?)?.color == parseColor(nuevo)));
    expect(dot, findsOneWidget, reason: 'la barra muestra el color nuevo');
    // dejar el favorito como estaba
    ts.setFavorite(0, antes);
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
  });

  // ---------------- links (issue #34) ----------------
  /// Una raya de tinta, elegida con el lazo, y el diálogo de "Link" abierto con la barrita. Devuelve la raya.
  Future<Stroke> selectInkForLink(WidgetTester t, Offset Function(Offset) p) async {
    await stylusLine(t, p(const Offset(200, 200)), p(const Offset(500, 200)));
    final ed = editor(t);
    final ink = ed.doc.strokes.values.single;
    await t.tap(find.byTooltip('Seleccionar'));
    await settle(t);
    await stylusDrag(t, p(const Offset(150, 150)), p(const Offset(550, 250)));
    expect(ed.sel.strokes, {ink.id});
    await t.tap(find.text('Link'));
    await settle(t);
    return ink;
  }

  testWidgets('link a una web: el dedo lo abre, el lápiz sigue escribiendo y deshacer saca el trazo y después el link (issue #34)', (t) async {
    final opened = <Uri>[];
    final prev = linkLauncher;
    linkLauncher = (u) async {
      opened.add(u);
      return true;
    };
    addTearDown(() => linkLauncher = prev);
    await start(t);
    await createNotebook(t, 'Links');
    final p = docToScreen(t);
    final ed = editor(t);
    await selectInkForLink(t, p);
    await t.tap(find.byKey(const Key('linkKindWeb')));
    await settle(t);
    await t.enterText(find.byKey(const Key('linkUrl')), 'ejemplo.com');
    await t.pump();
    await t.tap(find.byKey(const Key('linkOk')));
    await settle(t);
    final link = ed.doc.items.values.singleWhere((i) => i.type == 'link');
    expect(link.text, 'https://ejemplo.com');
    expect(find.byKey(ValueKey('link-${link.id}')), findsOneWidget, reason: 'la zona se marca en el editor');

    // con la herramienta del lápiz: el dedo abre
    await t.tap(find.byTooltip('Lápiz · tocá de nuevo para opciones'));
    await settle(t);
    expect(ed.sel.isEmpty, isTrue);
    await t.tapAt(p(link.rect.center));
    await settle(t);
    expect(opened, [Uri.parse('https://ejemplo.com')]);

    // el lápiz escribe encima y no abre
    await stylusLine(t, p(link.rect.center + const Offset(-80, 6)), p(link.rect.center + const Offset(80, 6)));
    expect(opened.length, 1);
    expect(ed.doc.strokes.length, 2, reason: 'el lápiz dibujó un trazo sobre el link');

    // deshacer: primero el trazo, después el link
    await t.tap(find.byTooltip('Deshacer'));
    await settle(t);
    expect(ed.doc.strokes.length, 1);
    expect(ed.doc.items.values.where((i) => i.type == 'link'), isNotEmpty);
    await t.tap(find.byTooltip('Deshacer'));
    await settle(t);
    expect(ed.doc.items.values.where((i) => i.type == 'link'), isEmpty);
  });

  testWidgets('link a otra hoja: tocarlo con el dedo lleva a esa hoja (issue #34)', (t) async {
    await start(t);
    await createNotebook(t, 'LinkHoja');
    final ed = editor(t);
    ed.doc.addSheet();
    ed.doc.addSheet();
    // ignore: invalid_use_of_protected_member
    ed.setState(() {});
    await settle(t, 600);
    expect(ed.doc.sheetCount, 3);
    final p = docToScreen(t);
    await selectInkForLink(t, p);
    await t.tap(find.byKey(const Key('linkKindSheet')));
    await settle(t);
    await t.tap(find.byKey(Key('linkSheet-${ed.doc.sheets[2].id}')));
    await settle(t);
    await t.tap(find.byKey(const Key('linkOk')));
    await settle(t);
    final link = ed.doc.items.values.singleWhere((i) => i.type == 'link');
    expect(link.text, 'sheet:${ed.doc.sheets[2].id}');
    await t.tap(find.byTooltip('Lápiz · tocá de nuevo para opciones'));
    await settle(t);
    expect(ed.mostVisibleSheet, 0);
    await t.tapAt(p(link.rect.center));
    await settle(t, 1500);
    expect(ed.mostVisibleSheet, 2, reason: 'el link lleva a la hoja 3');
  });

  testWidgets('quitar y editar un link (issue #34)', (t) async {
    await start(t);
    await createNotebook(t, 'LinkQuitar');
    final p = docToScreen(t);
    final ed = editor(t);
    await selectInkForLink(t, p);
    await t.enterText(find.byKey(const Key('linkUrl')), 'ejemplo.com');
    await t.pump();
    await t.tap(find.byKey(const Key('linkOk')));
    await settle(t);
    final link = ed.doc.items.values.singleWhere((i) => i.type == 'link');

    // con la selección de herramienta, tocar el link con el dedo lo elige (no lo abre)
    await t.tap(find.byTooltip('Deseleccionar'));
    await settle(t);
    await t.tapAt(p(link.rect.center));
    await settle(t);
    expect(ed.sel.items, {link.id});
    expect(find.text('Link'), findsNothing, reason: 'un link no se vuelve a convertir en link');

    // editar: cambia el destino con un paso de deshacer
    await t.tap(find.text('Editar link'));
    await settle(t);
    await t.enterText(find.byKey(const Key('linkUrl')), 'otro.org/x');
    await t.pump();
    await t.tap(find.byKey(const Key('linkOk')));
    await settle(t);
    expect(ed.doc.items[link.id]!.text, 'https://otro.org/x');
    ed.undo();
    await settle(t);
    expect(ed.doc.items[link.id]!.text, 'https://ejemplo.com');

    // quitar
    if (ed.sel.items.isEmpty) {
      await t.tapAt(p(link.rect.center));
      await settle(t);
    }
    await t.tap(find.text('Quitar link'));
    await settle(t);
    expect(ed.doc.items.values.where((i) => i.type == 'link'), isEmpty);
    ed.undo();
    await settle(t);
    expect(ed.doc.items.values.where((i) => i.type == 'link'), isNotEmpty, reason: 'quitar se deshace');
  });

  // ---------------- formas exactas (#38) ----------------
  testWidgets('formas: rectángulo con relleno pegado a la cuadrícula, con medida, manija y deshacer (issue #38)', (t) async {
    await start(t);
    await createNotebook(t, 'Formas');
    final ed = editor(t);
    ed.doc.sheets[0].setBg('grid');
    // ignore: invalid_use_of_protected_member
    ed.setState(() {});
    await settle(t, 600);

    await t.tap(find.byKey(const ValueKey('tool-shape')));
    await settle(t);
    await t.tap(find.byKey(const ValueKey('tool-shape'))); // de nuevo: abre las opciones
    await settle(t);
    await t.tap(find.byKey(const Key('shapeKind-rect')));
    await t.tap(find.byKey(const Key('shapeFillSwitch')));
    await settle(t);
    expect(ed.ts.shapeKind, 'rect');
    expect(ed.ts.shapeFill, isTrue);
    await t.tapAt(const Offset(4, 600)); // cierra el panel
    await settle(t);

    final p = docToScreen(t);
    await stylusDrag(t, p(const Offset(203, 307)), p(const Offset(498, 512)));
    expect(ed.doc.strokes.length, 1);
    final s = ed.doc.strokes.values.single;
    expect(s.fill, ed.ts.shapeFillColor);
    // las esquinas caen en la cuadrícula de 5 mm
    final xs = gridXs(5), ys = gridYs(5);
    bool onGrid(double x, double y) => xs.any((v) => (v - x).abs() < .5) && ys.any((v) => (v - y).abs() < .5);
    expect(onGrid(s.pts[0], s.pts[1]), isTrue, reason: 'primera esquina');
    final b = s.bounds.deflate(s.w * 1.6);
    expect(onGrid(b.right, b.bottom), isTrue, reason: 'esquina opuesta');
    expect(find.byKey(const Key('shapeMeasure')), findsOneWidget);
    expect(find.textContaining('×'), findsOneWidget);

    // una manija cambia la medida
    final texto = (t.widget(find.descendant(of: find.byKey(const Key('shapeMeasure')), matching: find.byType(Text))) as Text).data;
    final c = t.getCenter(find.byKey(const ValueKey('shapeHandle-2')));
    await stylusDrag(t, c, c + const Offset(90, 70));
    final texto2 = (t.widget(find.descendant(of: find.byKey(const Key('shapeMeasure')), matching: find.byType(Text))) as Text).data;
    expect(texto2, isNot(texto));
    expect(ed.doc.strokes.length, 1);

    // deshacer: vuelve al antes de la manija; otra vez, y la forma desaparece
    ed.undo();
    await settle(t);
    expect(ed.doc.strokes.values.single.pts, s.pts);
    ed.undo();
    await settle(t);
    expect(ed.doc.strokes, isEmpty);
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
  });

  testWidgets('formas: la recta con el dedo dibuja una recta y no scrollea (issue #38)', (t) async {
    await start(t);
    await createNotebook(t, 'FormasDedo');
    final ed = editor(t);
    await t.tap(find.byKey(const ValueKey('tool-shape')));
    await settle(t);
    await t.tap(find.byKey(const ValueKey('tool-shape')));
    await settle(t);
    await t.tap(find.byKey(const Key('shapeKind-line')));
    await settle(t);
    await t.tapAt(const Offset(4, 600));
    await settle(t);
    expect(ed.ts.shapeKind, 'line');

    final y0 = ed.scroll.offset;
    final p = docToScreen(t);
    final a = p(const Offset(200, 400)), b = p(const Offset(600, 480));
    final g = await t.startGesture(a, kind: PointerDeviceKind.touch);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(a, b, i / 10)!);
      await t.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await settle(t, 400);
    expect(ed.doc.strokes.length, 1);
    expect(ed.scroll.offset, y0, reason: 'un dedo no scrollea con las formas');
    expect(find.textContaining('mm ·'), findsOneWidget, reason: 'largo y ángulo');
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
  });

  testWidgets('marcadores: marcar la hoja que se ve con nombre, lista en el panel y volver a ella (issue #35)', (t) async {
    await start(t);
    await createNotebook(t, 'Marcadores');
    await t.tap(find.byKey(const Key('insert')));
    await settle(t);
    await t.tap(find.text('Hoja nueva'));
    await settle(t, 800);
    expect(find.text('2 / 2'), findsOneWidget);
    await t.tap(find.byKey(const Key('bookmarkSheet')));
    await settle(t);
    await t.enterText(find.byKey(const Key('bookmarkName')), 'Parcial');
    await t.tap(find.byKey(const Key('bookmarkSave')));
    await settle(t, 800);
    final d = editor(t).doc;
    expect([d.sheets[1].bookmark, d.sheets[1].title], [true, 'Parcial']);
    final id = d.sheets[1].id;
    await t.tap(find.byKey(const Key('pagesBtn')));
    await settle(t, 600);
    await t.tap(find.byTooltip('Solo marcadas'));
    await settle(t);
    expect(find.descendant(of: find.byKey(Key('bookmarkItem-$id')), matching: find.text('Parcial')), findsOneWidget);
    // a la hoja 1 (sin filtro) y de vuelta con el ítem de la lista
    await t.tap(find.byTooltip('Ver todas'));
    await settle(t);
    await t.tap(find.byKey(const Key('thumb-1')));
    await settle(t, 800);
    expect(editor(t).visibleSheet, 0);
    await t.tap(find.byTooltip('Solo marcadas'));
    await settle(t);
    await t.tap(find.byKey(Key('bookmarkItem-$id')));
    await settle(t, 800);
    expect(find.text('Parcial · 2 / 2'), findsOneWidget);
    // desmarcar con el botón de arriba
    await t.tap(find.byKey(const Key('bookmarkSheet')));
    await settle(t, 600);
    expect(editor(t).doc.sheets[1].bookmark, isFalse);
    expect(find.byKey(Key('bookmarkItem-$id')), findsNothing);
    expect(find.byKey(const Key('noBookmarks')), findsOneWidget);
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
  });

  testWidgets('exportar sin el fondo de la hoja: PNG sobre blanco; con fondo, papel y cuadrícula (issue #39)', (t) async {
    await start(t);
    await createNotebook(t, 'SinFondo');
    final d = editor(t).doc;
    d.sheets[0]
      ..bg = 'grid'
      ..paper = '#fbf3e0';
    d.strokes['trazo'] = Stroke('trazo', 'pen', '#22211e', 3, [300, 400, .5, 500, 450, .5, 700, 400, .5]);
    await settle(t, 800);
    final savedImages = saveImages;
    addTearDown(() => saveImages = savedImages);
    final ts = editor(t).ts;
    final antes = ts.exportBackground;

    Future<img.Image> exportar(bool fondo) async {
      await t.tap(find.byKey(const Key('more')));
      await settle(t);
      await t.tap(find.text('Exportar'));
      await settle(t, 600);
      final sw = t.widget<SwitchListTile>(find.byKey(const Key('exportBg')));
      if (sw.value != fondo) {
        await t.tap(find.byKey(const Key('exportBg')));
        await settle(t);
      }
      Uint8List? out;
      saveImages = (bytes, name, zip) async {
        out = bytes;
        return true;
      };
      await t.tap(find.byKey(const Key('export-png')));
      for (var i = 0; i < 100 && out == null; i++) {
        await settle(t, 100);
      }
      expect(out, isNotNull);
      return img.decodePng(out!)!;
    }

    bool blanco(img.Pixel p) => p.r == 255 && p.g == 255 && p.b == 255;
    final sin = await exportar(false);
    expect(blanco(sin.getPixel(8, 8)), isTrue, reason: 'sin fondo: blanco lejos del trazo');
    expect(ts.exportBackground, isFalse, reason: 'la elección quedó recordada');
    final con = await exportar(true);
    expect(blanco(con.getPixel(8, 8)), isFalse, reason: 'con fondo: papel crema');
    // restaurar la preferencia
    if (ts.exportBackground != antes) {
      await t.tap(find.byKey(const Key('more')));
      await settle(t);
      await t.tap(find.text('Exportar'));
      await settle(t, 600);
      await t.tap(find.byKey(const Key('exportBg')));
      await settle(t);
      await t.tapAt(const Offset(10, 10));
      await settle(t, 600);
    }
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
  });

  // ---------------- lienzo infinito (issue #36) ----------------
  /// Como [createNotebook] pero elige el tipo (por defecto Hojas, como el helper de siempre).
  Future<void> createKindNotebook(WidgetTester t, String name, {required bool canvas}) async {
    await t.tap(find.byKey(const Key('new')));
    await settle(t);
    await t.tap(find.byKey(const Key('newNotebook')));
    await settle(t);
    await t.enterText(find.byKey(const Key('askText')), name);
    await t.tap(find.byKey(Key(canvas ? 'nbKindCanvas' : 'nbKindSheets')));
    await settle(t, 200);
    await t.tap(find.byKey(const Key('askOk')));
    await settle(t, 1500);
  }

  testWidgets('lienzo infinito: crece a la derecha y hacia abajo, sin botón de hojas, y se conserva (issue #36)', (t) async {
    await start(t);
    await createKindNotebook(t, 'Mapa', canvas: true);
    expect(find.byKey(const Key('pagesBtn')), findsNothing);
    final ed = editor(t);
    expect(ed.doc.nb.canvas, isTrue);
    expect(ed.doc.nb.canvasW, 2000);
    final antes = ed.hscroll.position.maxScrollExtent;
    expect(antes, greaterThan(0), reason: 'el lienzo es más ancho que la pantalla');

    // derecha: se va al borde y se escribe pegado a él
    ed.hscroll.jumpTo(ed.hscroll.position.maxScrollExtent);
    await settle(t, 300);
    final box = t.getRect(find.byType(PageEditor));
    final y = box.top + 300;
    await stylusDrag(t, Offset(box.right - 120, y), Offset(box.right - 40, y + 30));
    expect(ed.doc.strokes.length, 1);
    expect(ed.doc.nb.canvasW, greaterThan(2000));
    expect(ed.hscroll.position.maxScrollExtent, greaterThan(antes), reason: 'se puede scrollear más a la derecha');

    // abajo: se va al final y se escribe cerca del borde de abajo
    ed.scroll.jumpTo(ed.scroll.position.maxScrollExtent);
    await settle(t, 300);
    final sheets = ed.doc.sheetCount;
    await stylusDrag(t, Offset(box.left + 300, box.bottom - 80), Offset(box.left + 400, box.bottom - 60));
    expect(ed.doc.sheetCount, greaterThan(sheets));

    final w = ed.doc.nb.canvasW;
    await t.tap(find.byKey(const Key('back')));
    await settle(t, 1200);
    final nb = await savedNotebook('Mapa');
    expect(nb.canvas, isTrue);
    expect(nb.canvasW, w);
    await t.tap(find.byKey(const Key('nb-Mapa')));
    await settle(t, 1500);
    expect(editor(t).doc.nb.canvasW, w);
    expect(editor(t).doc.strokes.length, 2, reason: 'los trazos quedaron guardados');
    expect(find.byKey(const Key('pagesBtn')), findsNothing);
  });

  testWidgets('cuaderno de hojas con el tipo por defecto: sigue igual (issue #36)', (t) async {
    await start(t);
    await createKindNotebook(t, 'Hojas', canvas: false);
    expect(find.byKey(const Key('pagesBtn')), findsOneWidget);
    expect(editor(t).doc.nb.canvas, isFalse);
    expect(editor(t).doc.width, kW);
  });

  testWidgets('scroll rápido: el pulgar del costado aparece al scrollear, lleva a la última hoja arrastrándolo y se esconde solo',
      (t) async {
    await start(t);
    await createNotebook(t, 'Scroll rápido');
    final ed = editor(t);
    while (ed.doc.sheetCount < 12) {
      ed.doc.addSheet();
    }
    // ignore: invalid_use_of_protected_member
    ed.setState(() {});
    await settle(t, 600);
    final thumb = find.byKey(const Key('fastScrollThumb'));
    bool tocable() => !t.widget<IgnorePointer>(find.ancestor(of: thumb, matching: find.byType(IgnorePointer)).first).ignoring;

    // un fling con el dedo: el pulgar aparece
    await t.fling(find.byType(PageEditor), const Offset(0, -400), 1500);
    await settle(t, 200);
    expect(thumb, findsOneWidget);
    expect(tocable(), isTrue);

    // se arrastra hasta abajo: la burbuja dice en qué hoja va
    final g = await t.startGesture(t.getCenter(thumb));
    var vistaBurbuja = false;
    // de sobra para cualquier alto de pantalla: el pulgar se frena al final del recorrido
    for (var i = 0; i < 25; i++) {
      await g.moveBy(const Offset(0, 80));
      await t.pump(const Duration(milliseconds: 50));
      if (find.textContaining('de 12').evaluate().isNotEmpty) vistaBurbuja = true;
    }
    expect(vistaBurbuja, isTrue);
    await g.up();
    await settle(t, 300);
    expect(ed.mostVisibleSheet, anyOf(11, 10));

    // sin tocar nada, se esconde solo
    await settle(t, 2000);
    expect(tocable(), isFalse);
  });



  testWidgets('resaltador sobre un PDF: el texto queda por encima y en la hoja exportada sigue negro', (t) async {
    final pdfBytes = (await t.runAsync(() async {
      final d = pw.Document();
      d.addPage(pw.Page(
        margin: const pw.EdgeInsets.all(40),
        build: (_) => pw.Align(
          alignment: pw.Alignment.topLeft,
          child: pw.Container(width: 400, height: 60, color: const PdfColor.fromInt(0xFF000000)),
        ),
      ));
      return Uint8List.fromList(await d.save());
    }))!;
    final savedPick = Pickers.pdf;
    addTearDown(() => Pickers.pdf = savedPick);
    Pickers.pdf = () async => (pdfBytes, 'Resaltado');
    await start(t);
    await createNotebook(t, 'Resaltador en PDF');
    final ed = editor(t);
    await t.tap(find.byKey(const Key('insert')));
    await settle(t);
    await t.tap(find.text('PDF'));
    await settle(t, 1500);
    final pdf = ed.doc.items.values.firstWhere((i) => i.type == 'pdf');
    final shown = find.descendant(of: find.byType(PdfPageImage), matching: find.byType(RawImage));
    final sw0 = Stopwatch()..start();
    while (shown.evaluate().isEmpty && sw0.elapsedMilliseconds < 5000) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await t.pump();
    }
    await settle(t, 800);

    // el rectángulo negro va de (40, 40) a (440, 100) puntos de una página A4 (595 x 842); línea horizontal por su borde de abajo
    final sx = pdf.w / 595, sy = pdf.h / 842;
    final edgeY = pdf.y + 100 * sy;
    final x0 = pdf.x + 140 * sx, x1 = pdf.x + 340 * sx;
    await t.tap(find.byKey(const ValueKey('tool-hl')));
    await settle(t);
    final toScreen = docToScreen(t);
    final a = toScreen(Offset(x0, edgeY)), b = toScreen(Offset(x1, edgeY));

    // lo que se ve en pantalla (el boundary que envuelve al editor, 1 px por px lógico) en un punto de la pantalla
    Future<List<int>> pantalla(Offset onBlack, Offset onWhite) async {
      final boundary = t.renderObject<RenderRepaintBoundary>(
          find.ancestor(of: find.byType(PageEditor), matching: find.byType(RepaintBoundary)).first);
      final res = await t.runAsync(() async {
        final image = await boundary.toImage();
        final data = (await image.toByteData())!;
        List<int> at(Offset g) {
          final l = boundary.globalToLocal(g);
          final i = (l.dy.round() * image.width + l.dx.round()) * 4;
          return [data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2)];
        }

        final out = [...at(onBlack), ...at(onWhite)];
        image.dispose();
        return out;
      });
      return res!;
    }

    void amarilloSobreBlanco(List<int> p, String cuando) {
      expect(p.sublist(0, 3), everyElement(lessThan(60)), reason: 'en pantalla $cuando: el negro del PDF queda por encima ($p)');
      expect(p[3], greaterThan(170), reason: 'en pantalla $cuando: sobre el blanco se ve amarillo ($p)');
      expect(p[4], greaterThan(170), reason: '$p');
      expect(p[5], lessThan(p[3] - 40), reason: '$p');
    }

    // el trazo mide 22: cubre 11 hacia cada lado del borde; se mira en el medio del tramo
    final mid = Offset.lerp(a, b, .5)!;
    final up = Offset(0, 5 * ed.scale);
    // antes de trazar, la página tiene que verse ya en esos dos puntos (negro arriba del borde, blanco abajo); con la
    // tablet cargada después de muchos casos, la imagen de la página puede tardar más
    var base = await pantalla(mid - up, mid + up);
    bool listo(List<int> p) => p.sublist(0, 3).every((v) => v < 60) && p.sublist(3).every((v) => v > 230);
    final sw1 = Stopwatch()..start();
    while (!listo(base) && sw1.elapsedMilliseconds < 8000) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await t.pump();
      base = await pantalla(mid - up, mid + up);
    }
    expect(listo(base), isTrue, reason: 'antes de resaltar se ve el PDF: negro y blanco en esos puntos ($base)');
    final g = await t.startGesture(a, kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 12; i++) {
      await g.moveTo(Offset.lerp(a, b, i / 12)!);
      await t.pump(const Duration(milliseconds: 8));
    }
    await t.pump();
    // con el trazo en curso (lápiz apoyado) ya se mezcla con el PDF
    amarilloSobreBlanco(await pantalla(mid - up, mid + up), 'con el trazo en curso');
    await g.up();
    await settle(t, 600);
    amarilloSobreBlanco(await pantalla(mid - up, mid + up), 'con el trazo terminado');

    // (1) quedó un trazo de resaltador
    final hls = [for (final s in ed.doc.strokes.values) if (s.k == 'hl') s];
    expect(hls, hasLength(1), reason: 'el resaltador deja un trazo hl');

    // (2) la tanda de resaltadores se pinta multiplicando
    final multiplied = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is InkPainter && (w.painter! as InkPainter).multiply);
    expect(multiplied, findsAtLeastNWidgets(1), reason: 'la tanda de resaltadores se compone multiplicando');

    // (3) exportada la hoja: sobre el negro sigue oscuro y sobre el blanco es amarillento
    final s = Storage(root: root);
    await s.init();
    final sheet = ed.doc.sheetOfY(pdf.y);
    final px = await t.runAsync(() async {
      final images = await loadImages(s, ed.doc, sheet: sheet);
      final png = await renderSheetPng(ed.doc, sheet, images: images);
      for (final im in images.values) {
        im.dispose();
      }
      final img = await decodeImage(png);
      final data = (await img.toByteData())!.buffer.asUint8List();
      final k = img.width / kW;
      List<int> at(double y) {
        final cx = (x0 + x1) / 2;
        final i = (((y - sheet * kSheetStep) * k).round() * img.width + (cx * k).round()) * 4;
        return [data[i], data[i + 1], data[i + 2]];
      }

      final out = (at(edgeY - 5), at(edgeY + 5)); // el trazo mide 22: cubre 11 hacia cada lado
      img.dispose();
      return out;
    });
    final (onBlack, onWhite) = px!;
    expect(onBlack, everyElement(lessThan(60)), reason: 'el negro del PDF queda por encima del resaltador');
    expect(onWhite[0], greaterThan(170));
    expect(onWhite[1], greaterThan(170));
    expect(onWhite[2], lessThan(onWhite[0] - 40), reason: 'sobre el blanco se ve amarillo');
  });


  testWidgets('índice: al cerrarlo la vista se queda en el título elegido', (t) async {
    // 1200 x 800 lógicos, sea cual sea la densidad: la escala depende del ancho (hasta 1100 de hoja) y el panel del
    // índice se come parte; más ancho que esto, con el panel abierto la hoja seguiría en su tope y no cambiaría nada
    sim(t); // en la PC: densidad y barra de la tablet; el tamaño es el de acá abajo
    t.view.physicalSize = const Size(1200, 800) * t.view.devicePixelRatio;
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(ApuntesApp(root: root));
    await settle(t, 1500);
    await createNotebook(t, 'IndiceSalto');
    var ed = editor(t);
    while (ed.doc.sheetCount < 8) {
      ed.doc.addSheet();
    }
    ed.sheetsChanged();
    await settle(t, 600);
    final head = Heading(newId('h'), level: 1, title: 'Capítulo cinco', y: 400);
    ed.doc.sheets[5].heads.add(head);
    ed.headingsChanged();
    await settle(t);

    double docY() => (ed.scroll.offset - kTopPad) / ed.scale;
    final scale0 = ed.scale;

    // abrir el índice y tocar el título
    await t.tap(find.byKey(const Key('indexBtn')));
    await settle(t, 800);
    expect(ed.scale, isNot(closeTo(scale0, 1e-3)), reason: 'el panel tiene que cambiar la escala para que valga el caso');
    await t.tap(find.byKey(Key('indexEntry-${head.id}')));
    await settle(t, 800);
    expect(ed.visibleSheet, 5);
    final y0 = docY();

    // cerrarlo: la vista se queda
    await t.tap(find.byKey(const Key('indexBtn')));
    await settle(t, 800);
    expect(ed.visibleSheet, 5);
    expect((docY() - y0).abs(), lessThan(2));

    // abrirlo de nuevo sin tocar nada: sigue ahí
    await t.tap(find.byKey(const Key('indexBtn')));
    await settle(t, 800);
    expect(ed.visibleSheet, 5);
    expect((docY() - y0).abs(), lessThan(2));

    // volver arriba, tocar el título y cerrar enseguida (el scroll animado todavía no terminó)
    ed.scrollToSheet(0, animate: false);
    await settle(t, 400);
    expect(ed.visibleSheet, 0);
    await t.tap(find.byKey(Key('indexEntry-${head.id}')));
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.byKey(const Key('indexBtn')));
    await settle(t, 800);
    expect(ed.visibleSheet, 5);
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
