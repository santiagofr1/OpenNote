import 'dart:io';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:apuntes/l10n/l10n.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Herramienta Formas: arrastrar crea la forma exacta, queda con manijas y medidas, se ajusta y se deshace.
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('apuntes_shape'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<({PageEditorState ed, ToolState tools, Offset Function(Offset) toGlobal})> open(WidgetTester t) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final doc = NotebookDoc(Notebook.create('T'));
    final tools = ToolState()
      ..tool = Tool.shape
      ..shapeKind = 'rect'
      ..shapeGrid = false;
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      locale: const Locale('es'),
      
      home: Scaffold(
        body: PageEditor(doc: doc, tools: tools, store: Storage(root: root), onChanged: () {}, onPrefsChanged: () {}),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
    final ed = t.state<PageEditorState>(find.byType(PageEditor));
    final layers = find
        .descendant(of: find.byType(PageEditor), matching: find.byType(Listener))
        .evaluate()
        .map((e) => e.renderObject as RenderBox)
        .firstWhere((b) => b.hasSize && (b.size.width - kW * ed.scale).abs() < .5);
    return (ed: ed, tools: tools, toGlobal: (Offset p) => layers.localToGlobal(p * ed.scale));
  }

  Future<void> drag(WidgetTester t, Offset from, Offset to, {PointerDeviceKind kind = PointerDeviceKind.stylus}) async {
    final g = await t.startGesture(from, kind: kind);
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 8)!);
      await t.pump();
    }
    await g.up();
    await t.pump();
  }

  testWidgets('arrastrar crea un trazo, aparecen las manijas y la medida; una manija lo cambia y deshacer lo devuelve', (t) async {
    final h = await open(t);
    final ed = h.ed;
    await drag(t, h.toGlobal(const Offset(200, 300)), h.toGlobal(const Offset(500, 500)));
    expect(ed.doc.strokes.length, 1);
    final s = ed.doc.strokes.values.single;
    expect(s.k, 'fine');
    expect(s.fill, isNull);
    expect(find.byKey(const ValueKey('shapeHandle-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('shapeHandle-3')), findsOneWidget);
    expect(find.byKey(const Key('shapeMeasure')), findsOneWidget);
    expect(find.textContaining('×'), findsOneWidget);

    final antes = List<double>.of(s.pts);
    final hd = find.byKey(const ValueKey('shapeHandle-2')); // esquina de abajo a la derecha
    final c = t.getCenter(hd);
    await drag(t, c, c + const Offset(60, 40));
    expect(ed.doc.strokes.length, 1, reason: 'el mismo trazo, no uno nuevo');
    final despues = ed.doc.strokes.values.single;
    expect(despues.id, s.id);
    expect(despues.pts, isNot(antes));
    expect(despues.bounds.right, greaterThan(s.bounds.right + 20));

    ed.undo();
    await t.pump();
    expect(ed.doc.strokes.values.single.pts, antes, reason: 'un solo paso de deshacer por arrastre');
    expect(find.byKey(const ValueKey('shapeHandle-0')), findsNothing, reason: 'al deshacer ya no hay manijas');
  });

  testWidgets('tocar afuera saca las manijas; un arrastre corto no crea nada', (t) async {
    final h = await open(t);
    await drag(t, h.toGlobal(const Offset(200, 300)), h.toGlobal(const Offset(500, 500)));
    expect(find.byKey(const ValueKey('shapeHandle-0')), findsOneWidget);
    await drag(t, h.toGlobal(const Offset(700, 650)), h.toGlobal(const Offset(702, 651)));
    expect(find.byKey(const ValueKey('shapeHandle-0')), findsNothing);
    expect(h.ed.doc.strokes.length, 1, reason: 'menos de 6 unidades: nada');
  });

  testWidgets('relleno: el trazo lleva el color elegido; la recta nunca', (t) async {
    final h = await open(t);
    h.tools
      ..shapeFill = true
      ..shapeFillColor = '#86efac';
    await drag(t, h.toGlobal(const Offset(200, 300)), h.toGlobal(const Offset(500, 500)));
    expect(h.ed.doc.strokes.values.single.fill, '#86efac');
    h.tools.shapeKind = 'line';
    await drag(t, h.toGlobal(const Offset(200, 700)), h.toGlobal(const Offset(500, 800)));
    expect(h.ed.doc.strokes.values.where((s) => s.fill == null).length, 1);
  });

  testWidgets('el dedo dibuja la forma y no scrollea', (t) async {
    final h = await open(t);
    h.tools.shapeKind = 'line';
    final y0 = h.ed.scroll.offset;
    await drag(t, h.toGlobal(const Offset(200, 300)), h.toGlobal(const Offset(500, 340)), kind: PointerDeviceKind.touch);
    await t.pump(const Duration(milliseconds: 400));
    expect(h.ed.doc.strokes.length, 1);
    expect(h.ed.scroll.offset, y0);
  });

  testWidgets('arrastrar el contorno mueve la forma entera', (t) async {
    final h = await open(t);
    await drag(t, h.toGlobal(const Offset(200, 300)), h.toGlobal(const Offset(500, 500)));
    final antes = h.ed.doc.strokes.values.single.bounds;
    final on = h.toGlobal(const Offset(350, 300)); // sobre el lado de arriba
    await drag(t, on, on + const Offset(0, 80));
    final despues = h.ed.doc.strokes.values.single.bounds;
    expect(despues.top - antes.top, greaterThan(40 / h.ed.scale));
    expect(despues.width, closeTo(antes.width, .01));
  });
}
