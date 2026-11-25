import 'dart:io';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:apuntes/l10n/l10n.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Manijas de la selección (escalar con las esquinas, rotar con la de arriba), con el editor de verdad:
/// se previsualiza en vivo, es UN paso de deshacer y deshacer vuelve todo exacto.
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('apuntes_selhandles'));
  tearDown(() => root.deleteSync(recursive: true));

  Stroke line(String id, Offset a, Offset b, {String k = 'pen', double w = 4}) => Stroke(id, k, '#000000', w, [
        for (var i = 0; i < 20; i++) ...[Offset.lerp(a, b, i / 19)!.dx, Offset.lerp(a, b, i / 19)!.dy, .5]
      ]);

  Future<({PageEditorState ed, Offset Function(double, double) at})> open(WidgetTester t, NotebookDoc doc) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = Storage(root: root);
    await t.runAsync(store.init);
    final tools = ToolState()..tool = Tool.select;
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      locale: const Locale('es'),
      
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
    return (ed: ed, at: (double x, double y) => layers.localToGlobal(Offset(x, y) * ed.scale));
  }

  Future<void> stylus(WidgetTester t, Offset a, Offset b) async {
    final g = await t.startGesture(a, kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(Offset.lerp(a, b, i / 8)!);
      await t.pump();
    }
    await g.up();
    await t.pump();
  }

  /// Arrastra la manija [name] hasta [to] (pantalla); [during] se mira con el dedo todavía apoyado.
  Future<void> dragHandle(WidgetTester t, String name, Offset to, {void Function()? during}) async {
    final from = t.getCenter(find.byKey(ValueKey('selHandle-$name')));
    final g = await t.startGesture(from, kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 8)!);
      await t.pump();
    }
    during?.call();
    await g.up();
    await t.pump();
  }

  NotebookDoc armado() {
    final doc = NotebookDoc(Notebook.create('T'));
    doc.strokes['a'] = line('a', const Offset(200, 300), const Offset(400, 300), w: 4);
    doc.strokes['h'] = line('h', const Offset(200, 330), const Offset(400, 330), k: 'hl', w: 20);
    doc.items['i'] = Item('i', 'sticky', 500, 280, 100, 80);
    doc.texts['t'] = TextBlock('t', 200, doc.snapTextY(400), 400, 'hola');
    return doc;
  }

  Future<PageEditorState> seleccionarTodo(WidgetTester t, NotebookDoc doc,
      Future<({PageEditorState ed, Offset Function(double, double) at})> Function() openIt) async {
    final h = await openIt();
    await stylus(t, h.at(100, 200), h.at(800, 520));
    expect(h.ed.sel.strokes, {'a', 'h'});
    expect(h.ed.sel.items, {'i'});
    expect(h.ed.sel.texts, {'t'});
    return h.ed;
  }

  testWidgets('las manijas aparecen sobre el recuadro: 4 esquinas y la de rotar (solo con trazos)', (t) async {
    final doc = armado();
    final h = await open(t, doc);
    await stylus(t, h.at(100, 200), h.at(800, 520));
    expect(h.ed.sel.strokes, {'a', 'h'});
    for (final n in ['tl', 'tr', 'br', 'bl', 'rotate']) {
      expect(find.byKey(ValueKey('selHandle-$n')), findsOneWidget, reason: n);
    }
    final z = t.getSize(find.byKey(const ValueKey('selHandle-br')));
    expect(z.width, greaterThanOrEqualTo(24), reason: 'zona de toque cómoda');

    // sin trazos (solo un elemento): esquinas sí, rotar no
    await t.tap(find.byTooltip('Deseleccionar'));
    await t.pump();
    final g = await t.startGesture(h.at(550, 320), kind: PointerDeviceKind.stylus); // toque sobre la nota
    await g.up();
    await t.pump();
    expect(h.ed.sel.items, {'i'});
    expect(find.byKey(const ValueKey('selHandle-br')), findsOneWidget);
    expect(find.byKey(const ValueKey('selHandle-rotate')), findsNothing);
  });

  testWidgets('escalar desde una esquina: trazos (puntos y grosor), elemento y texto; un solo deshacer lo vuelve exacto',
      (t) async {
    final doc = armado();
    final ed = await seleccionarTodo(t, doc, () => open(t, doc));
    final a0 = List<double>.of(doc.strokes['a']!.pts), h0 = List<double>.of(doc.strokes['h']!.pts);
    final i0 = doc.items['i']!.rect, t0 = Offset(doc.texts['t']!.x, doc.texts['t']!.y);
    final box = ed.sel.contentRect(doc)!;
    final br = t.getCenter(find.byKey(const ValueKey('selHandle-br')));
    // llevar la esquina a donde da escala 1,5 desde la esquina de arriba-izquierda
    final tl = t.getCenter(find.byKey(const ValueKey('selHandle-tl')));
    final target = tl + (br - tl) * 1.5;
    var duringScale = 0.0;
    await dragHandle(t, 'br', target, during: () => duringScale = ed.sel.drag!.xf.scale);
    expect(duringScale, closeTo(1.5, .05), reason: 'se previsualiza en vivo (la selección está en arrastre)');
    expect(ed.sel.moving, isFalse);
    final s = doc.strokes['a']!;
    expect(s.w, closeTo(4 * duringScale, .3), reason: 'el grosor también se escala');
    expect(doc.strokes['h']!.w, closeTo(20 * duringScale, 1.5));
    final k = s.w / 4;
    expect(s.pts[0], closeTo(box.left + (a0[0] - box.left) * k, .01), reason: 'la esquina de arriba-izquierda es el ancla');
    expect(s.pts[1], closeTo(box.top + (a0[1] - box.top) * k, .01));
    final it = doc.items['i']!;
    expect(it.w, closeTo(100 * k, .01));
    expect(it.h, closeTo(80 * k, .01));
    expect(it.x, closeTo(box.left + (i0.left - box.left) * k, .01));
    final tb = doc.texts['t']!;
    expect(tb.w, 400, reason: 'el texto no cambia de tamaño');
    expect(Offset(tb.x, tb.y), isNot(t0), reason: 'solo se movió');
    expect(ed.history.canUndo, isTrue);

    await t.tap(find.byTooltip('Deshacer'));
    await t.pump();
    expect(doc.strokes['a']!.pts, a0);
    expect(doc.strokes['a']!.w, 4);
    expect(doc.strokes['h']!.pts, h0);
    expect(doc.strokes['h']!.w, 20);
    expect(doc.items['i']!.rect, i0);
    expect(Offset(doc.texts['t']!.x, doc.texts['t']!.y), t0);
    expect(ed.history.canUndo, isFalse, reason: 'era UN solo paso');
    await t.tap(find.byTooltip('Rehacer'));
    await t.pump();
    expect(doc.strokes['a']!.w, closeTo(4 * k, 1e-9));
    expect(doc.items['i']!.w, closeTo(100 * k, 1e-9));
  });

  testWidgets('rotar 90° con la manija de arriba: giran los trazos; el elemento solo mueve su centro; un paso', (t) async {
    final doc = armado();
    final ed = await seleccionarTodo(t, doc, () => open(t, doc));
    final a0 = List<double>.of(doc.strokes['a']!.pts);
    final c = ed.sel.contentRect(doc)!.center;
    final i0 = doc.items['i']!.rect;
    final rot = t.getCenter(find.byKey(const ValueKey('selHandle-rotate')));
    // el centro en pantalla: la manija está arriba del centro del borde de arriba
    final screenC = (t.getCenter(find.byKey(const ValueKey('selHandle-tl'))) + t.getCenter(find.byKey(const ValueKey('selHandle-br')))) / 2;
    final r = (rot - screenC).distance;
    await dragHandle(t, 'rotate', screenC + Offset(r, 0)); // de arriba a la derecha: 90° en sentido horario
    final a = doc.strokes['a']!;
    // el punto (x, y) gira 90° horario alrededor de c: (dx, dy) -> (-dy, dx)
    final p0 = Offset(a0[0], a0[1]) - c;
    expect(Offset(a.pts[0], a.pts[1]), predicate<Offset>((p) => (p - (c + Offset(-p0.dy, p0.dx))).distance < .5, 'giró 90°'));
    expect(a.w, 4, reason: 'rotar no cambia el grosor');
    final it = doc.items['i']!;
    expect(it.w, 100);
    expect(it.h, 80);
    expect(it.rect.center, predicate<Offset>((p) {
      final q = i0.center - c;
      return (p - (c + Offset(-q.dy, q.dx))).distance < .5;
    }, 'el centro giró'));
    expect(ed.history.canUndo, isTrue);
    await t.tap(find.byTooltip('Deshacer'));
    await t.pump();
    expect(doc.strokes['a']!.pts, a0);
    expect(doc.items['i']!.rect, i0);
    expect(ed.history.canUndo, isFalse);
  });

  testWidgets('soltar una manija donde estaba no cambia nada ni entra al historial', (t) async {
    final doc = armado();
    final ed = await seleccionarTodo(t, doc, () => open(t, doc));
    final a0 = List<double>.of(doc.strokes['a']!.pts);
    final br = t.getCenter(find.byKey(const ValueKey('selHandle-br')));
    await dragHandle(t, 'br', br);
    expect(doc.strokes['a']!.pts, a0);
    expect(ed.history.canUndo, isFalse);
    expect(ed.sel.isEmpty, isFalse);
  });

  testWidgets('mover arrastrando adentro sigue andando y las manijas se esconden mientras se mueve', (t) async {
    final doc = armado();
    final h = await open(t, doc);
    await stylus(t, h.at(100, 200), h.at(800, 520));
    final a0 = doc.strokes['a']!.bounds;
    final g = await t.startGesture(h.at(300, 300), kind: PointerDeviceKind.stylus);
    await g.moveTo(h.at(300, 300) + const Offset(0, 40));
    await t.pump();
    await g.moveTo(h.at(300, 300) + const Offset(0, 80));
    await t.pump();
    expect(find.byKey(const ValueKey('selHandle-br')), findsNothing, reason: 'mientras se mueve no se ven');
    await g.up();
    await t.pump();
    expect(doc.strokes['a']!.bounds.top, closeTo(a0.top + 80 / h.ed.scale, .01));
    expect(find.byKey(const ValueKey('selHandle-br')), findsOneWidget);
  });

  testWidgets('tocar afuera con algo seleccionado solo deselecciona (no elige lo de abajo)', (t) async {
    final doc = armado();
    doc.strokes['x'] = line('x', const Offset(200, 700), const Offset(400, 700));
    final h = await open(t, doc);
    await stylus(t, h.at(100, 200), h.at(800, 520));
    expect(h.ed.sel.isEmpty, isFalse);
    final g = await t.startGesture(h.at(300, 700), kind: PointerDeviceKind.stylus);
    await g.up();
    await t.pump();
    expect(h.ed.sel.isEmpty, isTrue);
    expect(find.byKey(const ValueKey('selHandle-br')), findsNothing);
    final g2 = await t.startGesture(h.at(300, 700), kind: PointerDeviceKind.stylus);
    await g2.up();
    await t.pump();
    expect(h.ed.sel.strokes, {'x'}, reason: 'el segundo toque, ya sin selección, elige');
  });
}
