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
