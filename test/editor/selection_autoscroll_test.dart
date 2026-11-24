import 'dart:io';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:apuntes/editor/viewport.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Issue #28: al llevar lo seleccionado hasta el borde del visor, el cuaderno se desplaza solo y lo seleccionado viaja con
/// él. Solo al mover (no al escalar con las manijas); al soltar, para.
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('apuntes_autoscroll'));
  tearDown(() => root.deleteSync(recursive: true));

  Stroke line(String id, List<Offset> pts) => Stroke(id, 'pen', '#000000', 2, [for (final p in pts) ...[p.dx, p.dy, .5]]);

  Future<({PageEditorState ed, NotebookDoc doc, Offset Function(double, double) at})> open(WidgetTester t,
      {bool locked = false}) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final doc = NotebookDoc(Notebook.create('T'));
    for (var i = 0; i < 3; i++) {
      doc.nb.sheets.add(doc.nb.newSheet());
    }
    doc.strokes['s'] = line('s', [for (var i = 0; i < 20; i++) Offset(300 + i * 15.0, 400)]);
    final store = Storage(root: root);
    await t.runAsync(store.init);
    final tools = ToolState()
      ..tool = Tool.select
      ..zoomLocked = locked;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PageEditor(doc: doc, tools: tools, store: store, onChanged: () {}, onPrefsChanged: () {}),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
    final ed = t.state<PageEditorState>(find.byType(PageEditor));
    final layers = find
        .descendant(of: find.byType(PageEditor), matching: find.byType(Listener))
        .evaluate()
        .map((e) => e.renderObject as RenderBox)
        .firstWhere((b) => b.hasSize && (b.size.width - kW * ed.scale).abs() < .5);
    return (ed: ed, doc: doc, at: (double x, double y) => layers.localToGlobal(Offset(x, y) * ed.scale));
  }

  // elige el trazo con un toque de lápiz
  Future<void> select(WidgetTester t, Offset p) async {
    final g = await t.startGesture(p, kind: PointerDeviceKind.stylus);
    await g.up();
    await t.pump(const Duration(milliseconds: 100));
  }

  // bounds del trazo en página mientras se arrastra (el trazo queda quieto en el doc: se le suma el corrimiento en vivo)
  Rect bounds(({PageEditorState ed, NotebookDoc doc, Offset Function(double, double) at}) h) =>
      h.doc.strokes['s']!.bounds.shift(h.ed.sel.drag?.xf.shift ?? Offset.zero);

  Future<void> hold(WidgetTester t, int ms) async {
    for (var i = 0; i < ms ~/ 16; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
  }

  // lleva el puntero hasta [to], se queda quieto ~1 s y suelta; el scroll no se mueve tras soltar
  Future<void> dragAndHold(WidgetTester t, PageEditorState ed, Offset from, Offset to, PointerDeviceKind kind,
      {required bool scrolls, required Rect Function() bounds}) async {
    final y0 = ed.scroll.offset, b0 = bounds();
    final g = await t.startGesture(from, kind: kind);
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 8)!);
      await t.pump(const Duration(milliseconds: 16));
    }
    await hold(t, 1000);
    final y1 = ed.scroll.offset;
    if (scrolls) {
      expect(y1, greaterThan(y0 + 100), reason: 'el cuaderno bajó solo');
      final screenDown = (to.dy - from.dy) / ed.scale;
      expect(bounds().top - b0.top, greaterThan(screenDown + 50), reason: 'lo seleccionado viajó con la hoja');
    } else {
      expect(y1, y0, reason: 'no desplaza');
    }
    await g.up();
    await t.pump();
    final y2 = ed.scroll.offset;
    await hold(t, 64);
    expect(ed.scroll.offset, y2, reason: 'al soltar el scroll para');
  }

  testWidgets('con el lápiz, llevar la selección al borde de abajo desplaza el cuaderno y el trazo viaja con él', (t) async {
    final h = await open(t);
    await select(t, h.at(450, 400));
    expect(h.ed.sel.strokes, {'s'});
    await dragAndHold(t, h.ed, h.at(450, 400), const Offset(800, 980), PointerDeviceKind.stylus,
        scrolls: true, bounds: () => bounds(h));
  });

  testWidgets('con el lápiz temblando en el borde, lo seleccionado sigue bajando y pasa a la hoja siguiente', (t) async {
    final h = await open(t);
    await select(t, h.at(450, 400));
    final from = h.at(450, 400), to = const Offset(800, 980);
    final g = await t.startGesture(from, kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 8)!);
      await t.pump(const Duration(milliseconds: 16));
    }
    // el lápiz de verdad nunca está quieto: cada evento de movimiento traía la posición con el scroll del principio
    for (var i = 0; i < 40; i++) {
      await hold(t, 64);
      await g.moveBy(Offset(i.isEven ? .5 : -.5, 0));
    }
    final y = h.ed.scroll.offset, top = bounds(h).top;
    final screenTop = (top * h.ed.scale + kTopPad - y) / h.ed.scale;
    expect(top, greaterThan(kSheetStep), reason: 'pasó a la hoja siguiente');
    expect(screenTop, greaterThan(0), reason: 'sigue a la vista, junto al lápiz');
    await g.up();
    await t.pump();
  });

  testWidgets('con el dedo sobre lo seleccionado pasa lo mismo', (t) async {
    final h = await open(t);
    await select(t, h.at(450, 400));
    await dragAndHold(t, h.ed, h.at(450, 400), const Offset(800, 980), PointerDeviceKind.touch,
        scrolls: true, bounds: () => bounds(h));
  });

  testWidgets('con el zoom fijado también desplaza', (t) async {
    final h = await open(t, locked: true);
    await select(t, h.at(450, 400));
    await dragAndHold(t, h.ed, h.at(450, 400), const Offset(800, 980), PointerDeviceKind.stylus,
        scrolls: true, bounds: () => bounds(h));
  });

  testWidgets('con la manija de escalar llevada al borde el cuaderno NO se desplaza', (t) async {
    final h = await open(t);
    await select(t, h.at(450, 400));
    final br = t.getCenter(find.byKey(const ValueKey('selHandle-br')));
    await dragAndHold(t, h.ed, br, const Offset(800, 980), PointerDeviceKind.stylus,
        scrolls: false, bounds: () => bounds(h));
  });
}
