import 'dart:async';
import 'dart:io';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:apuntes/l10n/l10n.dart';
import 'package:apuntes/rendering/pdf_cover.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// La goma sobre un PDF importado: si arranca sin tocar tinta, pinta un corrector del color del fondo.
void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('apuntes_cover');
    pdfCoverColor = (_, _, _, _) async => 0xFFFFF0C0;
  });
  tearDown(() {
    pdfCoverColor = coverColorAt;
    root.deleteSync(recursive: true);
  });

  final pdfRect = const Rect.fromLTWH(100, 200, 400, 500);

  NotebookDoc armado({bool withPdf = true}) {
    final doc = NotebookDoc(Notebook.create('T'));
    if (withPdf) doc.items['pdf'] = Item('pdf', 'pdf', pdfRect.left, pdfRect.top, pdfRect.width, pdfRect.height, file: 'x.pdf');
    return doc;
  }

  Stroke ink(String id, Offset a, Offset b) =>
      Stroke(id, 'pen', '#000000', 2, [a.dx, a.dy, .5, (a.dx + b.dx) / 2, (a.dy + b.dy) / 2, .5, b.dx, b.dy, .5]);

  Future<({PageEditorState ed, Offset Function(Offset) toGlobal})> open(WidgetTester t, NotebookDoc doc) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = Storage(root: root);
    await t.runAsync(store.init);
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      locale: const Locale('es'),
      
      home: Scaffold(
        body: PageEditor(doc: doc, tools: ToolState(), store: store, onChanged: () {}, onPrefsChanged: () {}),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
    final ed = t.state<PageEditorState>(find.byType(PageEditor));
    final layers = find
        .descendant(of: find.byType(PageEditor), matching: find.byType(Listener))
        .evaluate()
        .map((e) => e.renderObject as RenderBox)
        .firstWhere((b) => b.hasSize && (b.size.width - kW * ed.scale).abs() < .5);
    return (ed: ed, toGlobal: (Offset p) => layers.localToGlobal(p * ed.scale));
  }

  // pasa la goma (punta de goma del lápiz) por [pts] (coordenadas del documento)
  Future<void> erase(WidgetTester t, dynamic h, List<Offset> pts, {bool wait = true}) async {
    final g = await t.startGesture(h.toGlobal(pts.first) as Offset, kind: PointerDeviceKind.invertedStylus);
    for (final p in pts.skip(1)) {
      await g.moveTo(h.toGlobal(p) as Offset);
      await t.pump();
    }
    await g.up();
    await t.pump();
    if (wait) await t.pump(const Duration(milliseconds: 10));
  }

  List<Stroke> covers(PageEditorState ed) => [for (final s in ed.doc.strokes.values) if (s.k == kCoverTip) s];

  testWidgets('goma que arranca sobre el PDF sin tinta: deja un corrector del color del fondo; deshacer lo saca', (t) async {
    final h = await open(t, armado());
    final r = h.ed.widget.tools.eraserRadius;
    await erase(t, h, [const Offset(150, 300), const Offset(300, 300), const Offset(600, 300)]);
    final c = covers(h.ed).single;
    expect(c.c, '#fff0c0');
    expect(c.w, 2 * r);
    for (var i = 0; i < c.pts.length; i += 3) {
      expect(c.pts[i], inInclusiveRange(pdfRect.left, pdfRect.right), reason: 'recortado al rect del PDF');
      expect(c.pts[i + 1], inInclusiveRange(pdfRect.top, pdfRect.bottom));
    }
    expect(c.pts[c.pts.length - 3], pdfRect.right, reason: 'el último punto (afuera) queda en el borde');
    await t.tap(find.byTooltip('Deshacer'));
    await t.pump();
    expect(covers(h.ed), isEmpty);
    await t.tap(find.byTooltip('Rehacer'));
    await t.pump();
    expect(covers(h.ed).single.c, '#fff0c0');
  });

  testWidgets('goma que arranca sobre tinta encima del PDF: borra la tinta y no crea corrector', (t) async {
    final doc = armado();
    doc.strokes['a'] = ink('a', const Offset(200, 400), const Offset(300, 400));
    final h = await open(t, doc);
    await erase(t, h, [const Offset(250, 400), const Offset(250, 500)]);
    expect(h.ed.doc.strokes.containsKey('a'), isFalse);
    expect(covers(h.ed), isEmpty);
  });

  testWidgets('modo corrector que pasa por tinta: la borra y deshacer devuelve la tinta y saca el corrector', (t) async {
    final doc = armado();
    doc.strokes['a'] = ink('a', const Offset(200, 500), const Offset(300, 500));
    final h = await open(t, doc);
    await erase(t, h, [const Offset(250, 300), const Offset(250, 450), const Offset(250, 500), const Offset(250, 600)]);
    expect(h.ed.doc.strokes.containsKey('a'), isFalse);
    expect(covers(h.ed), hasLength(1));
    await t.tap(find.byTooltip('Deshacer'));
    await t.pump();
    expect(h.ed.doc.strokes.containsKey('a'), isTrue);
    expect(covers(h.ed), isEmpty);
    await t.tap(find.byTooltip('Rehacer'));
    await t.pump();
    expect(h.ed.doc.strokes.containsKey('a'), isFalse);
    expect(covers(h.ed), hasLength(1));
  });

  testWidgets('goma sobre papel sin PDF: no hace nada', (t) async {
    final h = await open(t, armado(withPdf: false));
    await erase(t, h, [const Offset(150, 300), const Offset(300, 300)]);
    expect(h.ed.doc.strokes, isEmpty);
  });

  testWidgets('segunda pasada sobre un corrector: no lo borra, agrega otro', (t) async {
    final h = await open(t, armado());
    await erase(t, h, [const Offset(150, 300), const Offset(300, 300)]);
    expect(covers(h.ed), hasLength(1));
    await erase(t, h, [const Offset(160, 300), const Offset(290, 300)]);
    expect(covers(h.ed), hasLength(2));
  });

  testWidgets('el color llega después de soltar: se reemplaza el trazo y deshacer/rehacer usan el final', (t) async {
    final color = Completer<int>();
    pdfCoverColor = (_, _, _, _) => color.future;
    final h = await open(t, armado());
    await erase(t, h, [const Offset(150, 300), const Offset(300, 300)], wait: false);
    expect(covers(h.ed).single.c, '#ffffff', reason: 'hasta que llega el color queda blanco');
    color.complete(0xFFC0FFEE);
    await t.pump();
    await t.pump();
    expect(covers(h.ed).single.c, '#c0ffee');
    await t.tap(find.byTooltip('Deshacer'));
    await t.pump();
    await t.tap(find.byTooltip('Rehacer'));
    await t.pump();
    expect(covers(h.ed).single.c, '#c0ffee');
  });
}
