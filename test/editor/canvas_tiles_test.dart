import 'dart:io';
import 'dart:ui' as ui;

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:apuntes/l10n/l10n.dart';
import 'package:apuntes/rendering/ink_layers.dart';
import 'package:apuntes/rendering/sheet_image_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Lienzo: la tinta de cada tanda va partida en columnas de [kCanvasTileW], cada una con su capa y su imagen.
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('apuntes_tiles'));
  tearDown(() => root.deleteSync(recursive: true));

  Stroke line(String id, double x0, double y, double x1) =>
      Stroke(id, 'pen', '#000000', 6, [x0, y, .5, (x0 + x1) / 2, y, .5, x1, y, .5]);

  NotebookDoc canvasDoc() {
    final doc = NotebookDoc(Notebook.create('L', canvas: true));
    doc.strokes['a'] = line('a', 100, 200, 400); // columna 0
    doc.strokes['b'] = line('b', 900, 300, 1100); // cruza 0 y 1
    doc.strokes['c'] = line('c', 2100, 400, 2300); // columna 2 (el lienzo mide 2000: crece)
    return doc;
  }

  Future<void> open(WidgetTester t, NotebookDoc doc) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      locale: const Locale('es'),
      home: Scaffold(
        body: PageEditor(
            doc: doc, tools: ToolState()..tool = Tool.pen, store: Storage(root: root), onChanged: () {}, onPrefsChanged: () {}),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
  }

  Set<String> inkKeys(WidgetTester t) => {
        for (final w in t.widgetList(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('ink-'))))
          (w.key as ValueKey<String>).value
      };

  Map<String, InkPainter> painters(WidgetTester t) => {
        for (final w in t.widgetList<CustomPaint>(find.byType(CustomPaint)))
          if (w.painter is InkPainter) (w.painter as InkPainter).cacheKey: w.painter as InkPainter
      };

  testWidgets('lienzo: una capa de tinta por columna con trazos; el trazo que cruza va en las dos', (t) async {
    final doc = canvasDoc();
    doc.nb.canvasW = 3000;
    await open(t, doc);
    final id = doc.sheets.first.id;
    expect(inkKeys(t), {'ink-$id-0-c0', 'ink-$id-0-c1', 'ink-$id-0-c2'});
    final p = painters(t);
    expect(p['ink-$id-0-c0']!.strokes.map((s) => s.id), ['a', 'b']);
    expect(p['ink-$id-0-c1']!.strokes.map((s) => s.id), ['b']);
    expect(p['ink-$id-0-c2']!.strokes.map((s) => s.id), ['c']);
    expect(p['ink-$id-0-c1']!.sheet, Rect.fromLTWH(kCanvasTileW, 0, kCanvasTileW, kSheetStep));
    expect(p['ink-$id-0-c2']!.sheetId, tileId(id, 2));
  });

  NotebookDoc wide() {
    final doc = NotebookDoc(Notebook.create('W', canvas: true));
    doc.nb.canvasW = 12000;
    for (var j = 0; j < 12; j++) {
      doc.strokes['w$j'] = line('w$j', j * kCanvasTileW + 100, 200, j * kCanvasTileW + 300);
    }
    return doc;
  }

  Future<PageEditorState> openEd(WidgetTester t, NotebookDoc doc) async {
    await open(t, doc);
    return t.state<PageEditorState>(find.byType(PageEditor));
  }

  Set<int> cols(WidgetTester t) => {for (final k in inkKeys(t)) int.parse(k.substring(k.lastIndexOf('-c') + 2))};

  testWidgets('lienzo ancho: solo hay capas de las columnas que se ven más una de margen', (t) async {
    final ed = await openEd(t, wide());
    final v = ed.debugColRange;
    expect(cols(t), {for (var j = v.first; j <= v.last; j++) j});
    expect(cols(t), contains(0));
    expect(cols(t).length, lessThan(6));
    expect(cols(t), isNot(contains(11)));
  });

  testWidgets('lienzo ancho: scrollear en horizontal cambia las columnas armadas', (t) async {
    final ed = await openEd(t, wide());
    ed.hscroll.jumpTo(ed.hscroll.position.maxScrollExtent);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(cols(t), contains(11));
    expect(cols(t), isNot(contains(0)));
  });

  testWidgets('lienzo ancho: alejar el zoom ensancha el rango', (t) async {
    final doc = wide();
    final ed = await openEd(t, doc);
    final n1 = cols(t).length;
    ed.ts.zoom = .5;
    // ignore: invalid_use_of_protected_member
    ed.setState(() {});
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(cols(t).length, greaterThan(n1));
  });

  testWidgets('lienzo ancho: una columna fuera del rango sigue sin capa pero su trazo entra al scrollear', (t) async {
    final doc = wide();
    final ed = await openEd(t, doc);
    expect(cols(t), isNot(contains(8)));
    doc.strokes['nuevo'] = line('nuevo', 8 * kCanvasTileW + 400, 500, 8 * kCanvasTileW + 700);
    ed.hscroll.jumpTo(ed.hscroll.position.maxScrollExtent * 8 / 11);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(cols(t), contains(8));
    final p = painters(t).values.where((p) => p.sheet.left == 8 * kCanvasTileW).single;
    expect(p.strokes.map((s) => s.id), containsAll(['w8', 'nuevo']));
  });

  testWidgets('lienzo ancho: mover una selección que sale del rango no pierde sus trazos', (t) async {
    final doc = wide();
    final ed = await openEd(t, doc);
    // mientras se mueve no se dibuja en las capas sino en la capa en vivo, que cubre todo el ancho (no depende del rango)
    final live = t.widgetList<CustomPaint>(find.byType(CustomPaint)).where((w) => w.painter is LivePainter);
    expect(live, isNotEmpty);
    // al soltarlo en otra columna (fuera del rango) y volver a verla, el trazo está en su capa
    final s = doc.strokes['w0']!;
    doc.strokes.remove('w0');
    final moved = Stroke('w0', 'pen', '#000000', 6, [9 * kCanvasTileW + 100, 200, .5, 9 * kCanvasTileW + 300, 200, .5]);
    doc.strokes['w0'] = moved;
    expect(s, isNot(same(moved)));
    ed.hscroll.jumpTo(ed.hscroll.position.maxScrollExtent * 9 / 11);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    final q = painters(t).values.firstWhere((p) => p.sheet.left == 9 * kCanvasTileW);
    expect(q.strokes.map((x) => x.id), contains('w0'));
  });

  testWidgets('hojas: la tanda sigue siendo una sola capa ink-<id>-<i>', (t) async {
    final doc = NotebookDoc(Notebook.create('P'));
    doc.strokes['a'] = line('a', 100, 200, 400);
    doc.strokes['b'] = line('b', 500, 300, 900);
    await open(t, doc);
    expect(inkKeys(t), {'ink-${doc.sheets.first.id}-0'});
  });

  test('ofSheet e invalidateSheet cubren las columnas de la hoja', () {
    expect(SheetImageCache.ofSheet('h1', 'h1'), isTrue);
    expect(SheetImageCache.ofSheet(tileId('h1', 3), 'h1'), isTrue);
    expect(SheetImageCache.ofSheet(tileId('h10', 3), 'h1'), isFalse);
    expect(SheetImageCache.ofSheet('h2', 'h1'), isFalse);
    final c = SheetImageCache();
    c.entry('k0', tileId('h1', 0));
    c.entry('k1', tileId('h1', 1));
    c.entry('k2', tileId('h2', 0));
    expect(c.entriesOf('h1').length, 2);
    expect(c.entriesOf(tileId('h1', 1)).length, 1);
    c.dropSheet('h1');
    expect(c.entriesOf('h1'), isEmpty);
    expect(c.entriesOf(tileId('h1', 0)), isEmpty);
    expect(c.entriesOf('h2').length, 1);
    c.dispose();
  });

  test('invalidateSheet(id) invalida las entradas de las columnas (y no las de otra hoja)', () {
    final c = SheetImageCache();
    final e = c.entry('k', tileId('h1', 2));
    final o = c.entry('o', tileId('h2', 2));
    e.refused = true; // se limpia al invalidar
    o.refused = true;
    c.invalidateSheet('h1');
    expect(e.refused, isFalse);
    expect(o.refused, isTrue);
    c.dispose();
  });

  test('InkPainter con sheet.left > 0 dibuja el trazo en su lugar', () async {
    final doc = NotebookDoc(Notebook.create('L', canvas: true));
    final s = line('a', 1500, 100, 1700);
    doc.strokes['a'] = s;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(const Rect.fromLTWH(0, 0, 1000, 300), Paint()..color = const Color(0xFFFFFFFF));
    InkPainter(doc, [s], const Rect.fromLTWH(1000, 0, 1000, kSheetStep), 1, ValueNotifier(0), () => const {})
        .paint(c, const Size(1000, kSheetStep));
    final img = await rec.endRecording().toImage(1000, 300);
    final d = (await img.toByteData())!;
    int px(int x, int y) => d.getUint32((y * 1000 + x) * 4) >> 8;
    expect(px(600, 100), lessThan(0x404040), reason: 'x = 1600 del lienzo cae en 600 de la columna');
    expect(px(100, 100), 0xFFFFFF, reason: 'a x = 100 no hay nada (el trazo está en la columna 1)');
    expect(px(600, 250), 0xFFFFFF);
  });
}
