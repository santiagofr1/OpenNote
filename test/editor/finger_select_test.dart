import 'dart:io';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Elegir y mover imágenes, audios y notas con el DEDO, en cualquier herramienta (issue #11a): un toque elige, arrastrar
/// lo ya elegido lo mueve (no scrollea), arrastrar en otro lado sigue scrolleando y las manijas responden al dedo.
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('apuntes_finger'));
  tearDown(() => root.deleteSync(recursive: true));

  NotebookDoc armado() {
    final doc = NotebookDoc(Notebook.create('T'));
    doc.items['img'] = Item('img', 'image', 200, 300, 300, 200, file: 'no-existe.png');
    doc.items['aud'] = Item('aud', 'audio', 200, 700, 360, 64, file: 'no-existe.m4a', dur: 4000);
    doc.items['nota'] = Item('nota', 'sticky', 700, 300, 240, 160);
    return doc;
  }

  Future<({PageEditorState ed, ToolState tools, Offset Function(double, double) at})> open(WidgetTester t, NotebookDoc doc,
      {Tool tool = Tool.pen, bool locked = false}) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = Storage(root: root);
    await t.runAsync(store.init);
    final tools = ToolState()
      ..tool = tool
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
    return (ed: ed, tools: tools, at: (double x, double y) => layers.localToGlobal(Offset(x, y) * ed.scale));
  }

  Future<void> fingerTap(WidgetTester t, Offset p) async {
    final g = await t.startGesture(p, kind: PointerDeviceKind.touch);
    await t.pump(const Duration(milliseconds: 40));
    await g.up();
    await t.pump(const Duration(milliseconds: 100));
  }

  Future<void> fingerDrag(WidgetTester t, Offset a, Offset b, {void Function()? during}) async {
    final g = await t.startGesture(a, kind: PointerDeviceKind.touch);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(a, b, i / 10)!);
      await t.pump(const Duration(milliseconds: 16));
    }
    during?.call();
    await g.up();
    await t.pump(const Duration(milliseconds: 100));
  }

  for (final tool in [Tool.pen, Tool.hl, Tool.select]) {
    testWidgets('con el dedo, un toque elige imagen, nota y audio (herramienta ${tool.name}) y la herramienta no cambia',
        (t) async {
      final h = await open(t, armado(), tool: tool);
      await fingerTap(t, h.at(350, 400));
      expect(h.ed.sel.items, {'img'});
      expect(h.tools.tool, tool, reason: 'elegir con el dedo no cambia de herramienta');
      expect(find.text('Copiar'), findsOneWidget, reason: 'la misma barrita que con el lápiz');
      for (final n in ['tl', 'tr', 'br', 'bl']) {
        expect(find.byKey(ValueKey('selHandle-$n')), findsOneWidget, reason: 'manija $n');
      }
      await fingerTap(t, h.at(800, 380));
      expect(h.ed.sel.items, {'nota'});
      await fingerTap(t, h.at(450, 730)); // el audio, afuera del botón de reproducir
      expect(h.ed.sel.items, {'aud'});
    });
  }

  testWidgets('en modo texto un toque del dedo es para escribir: no elige', (t) async {
    final h = await open(t, armado(), tool: Tool.text);
    await fingerTap(t, h.at(350, 400));
    expect(h.ed.sel.isEmpty, isTrue);
  });

  testWidgets('un toque en el botón de reproducir del audio NO lo elige (reproduce)', (t) async {
    final h = await open(t, armado());
    await fingerTap(t, h.at(200 + 25, 700 + 32));
    expect(h.ed.sel.isEmpty, isTrue);
  });

  testWidgets('tocar afuera con el dedo deselecciona; tocar un hueco del recuadro no', (t) async {
    final h = await open(t, armado());
    await fingerTap(t, h.at(350, 400));
    expect(h.ed.sel.items, {'img'});
    await fingerTap(t, h.at(600, 600));
    expect(h.ed.sel.isEmpty, isTrue);
  });

  testWidgets('arrastrar con el dedo lo ya elegido lo mueve (sin scrollear) y es UN paso de deshacer', (t) async {
    final doc = armado();
    final h = await open(t, doc);
    await fingerTap(t, h.at(350, 400));
    final y0 = h.ed.scroll.offset;
    final from = h.at(350, 400), to = h.at(550, 560);
    var live = Offset.zero;
    await fingerDrag(t, from, to, during: () => live = Offset(doc.items['img']!.x, doc.items['img']!.y));
    expect(live.dx, greaterThan(300), reason: 'se ve moverse mientras se arrastra');
    final it = doc.items['img']!;
    expect(it.x, closeTo(400, 12));
    expect(it.y, closeTo(460, 12));
    expect(h.ed.scroll.offset, y0, reason: 'no scrolleó');
    expect(h.ed.sel.items, {'img'}, reason: 'sigue elegida');
    expect(doc.items['nota']!.x, 700, reason: 'lo demás no se mueve');
    await t.tap(find.byTooltip('Deshacer'));
    await t.pump();
    expect(doc.items['img']!.x, 200);
    expect(doc.items['img']!.y, 300);
  });

  testWidgets('arrastrar con el dedo algo NO elegido sigue scrolleando, y no elige nada', (t) async {
    final doc = armado();
    final h = await open(t, doc);
    final y0 = h.ed.scroll.offset;
    await fingerDrag(t, h.at(350, 400), h.at(350, 400) + const Offset(0, -300));
    expect(h.ed.scroll.offset, greaterThan(y0 + 100), reason: 'scrolleó');
    expect(h.ed.sel.isEmpty, isTrue);
    expect(doc.items['img']!.x, 200);
    // y arrastrar en un lugar vacío también scrollea
    final y1 = h.ed.scroll.offset;
    await fingerDrag(t, const Offset(1100, 700), const Offset(1100, 400));
    expect(h.ed.scroll.offset, greaterThan(y1 + 100));
  });

  testWidgets('con algo elegido, arrastrar el dedo en otro lado sigue scrolleando', (t) async {
    final doc = armado();
    final h = await open(t, doc);
    await fingerTap(t, h.at(350, 400));
    final y0 = h.ed.scroll.offset;
    await fingerDrag(t, const Offset(1400, 800), const Offset(1400, 500));
    expect(h.ed.scroll.offset, greaterThan(y0 + 100));
    expect(doc.items['img']!.x, 200, reason: 'lo elegido no se movió');
  });

  testWidgets('las manijas responden al dedo: arrastrar una esquina escala la imagen', (t) async {
    final doc = armado();
    final h = await open(t, doc);
    await fingerTap(t, h.at(350, 400));
    final w0 = doc.items['img']!.w;
    final y0 = h.ed.scroll.offset;
    final br = t.getCenter(find.byKey(const ValueKey('selHandle-br')));
    await fingerDrag(t, br, br + const Offset(120, 80));
    expect(doc.items['img']!.w, greaterThan(w0 * 1.2), reason: 'creció');
    expect(h.ed.scroll.offset, y0, reason: 'no scrolleó');
  });

  testWidgets('dos dedos siguen haciendo zoom aunque haya algo elegido', (t) async {
    final doc = armado();
    final h = await open(t, doc);
    await fingerTap(t, h.at(350, 400));
    final z0 = h.tools.zoom;
    final a = await t.startGesture(const Offset(600, 500), kind: PointerDeviceKind.touch);
    final b = await t.startGesture(const Offset(700, 500), kind: PointerDeviceKind.touch);
    for (var i = 1; i <= 8; i++) {
      await a.moveTo(Offset(600 - i * 20.0, 500));
      await b.moveTo(Offset(700 + i * 20.0, 500));
      await t.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await t.pump(const Duration(milliseconds: 1200));
    expect(h.tools.zoom, isNot(z0));
    expect(doc.items['img']!.x, 200);
  });

  testWidgets('mantener el dedo quieto sobre la hoja sigue abriendo el menú (y no elige)', (t) async {
    final h = await open(t, armado());
    final g = await t.startGesture(h.at(350, 400), kind: PointerDeviceKind.touch);
    await t.pump(const Duration(milliseconds: 700));
    await g.up();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Pegar acá'), findsWidgets, reason: 'se abrió el menú de la hoja');
    while (t.takeException() != null) {} // (con la fuente de los tests el menú desborda unos píxeles)
    expect(h.ed.sel.isEmpty, isTrue, reason: 'mantener apretado no elige');
  });

  // ---------------- scroll con dos dedos y candado del zoom (issue #18) ----------------
  Future<(TestGesture, TestGesture)> twoDown(WidgetTester t, Offset a, Offset b) async {
    final g1 = await t.startGesture(a, kind: PointerDeviceKind.touch);
    await t.pump(const Duration(milliseconds: 16));
    final g2 = await t.startGesture(b, kind: PointerDeviceKind.touch);
    await t.pump(const Duration(milliseconds: 16));
    return (g1, g2);
  }

  Future<void> twoDrag(WidgetTester t, (TestGesture, TestGesture) g, Offset a, Offset b, Offset by,
      {int steps = 10, int ms = 16}) async {
    // los eventos de prueba llevan marca de tiempo 0: se la ponemos para que haya velocidad
    var now = Duration.zero;
    for (var i = 1; i <= steps; i++) {
      now += Duration(milliseconds: ms);
      await g.$1.moveTo(a + by * (i / steps), timeStamp: now);
      await g.$2.moveTo(b + by * (i / steps), timeStamp: now);
      await t.pump(Duration(milliseconds: ms));
    }
  }

  group('candado del zoom: scroll con dos dedos', () {
    const a = Offset(1100, 800), b = Offset(1200, 800);

    testWidgets('un dedo no mueve la hoja', (t) async {
      final h = await open(t, armado(), locked: true);
      final y0 = h.ed.scroll.offset;
      await fingerDrag(t, const Offset(1100, 800), const Offset(1100, 500));
      expect(h.ed.scroll.offset, y0);
    });

    testWidgets('dos dedos arrastran la hoja sin cambiar el zoom', (t) async {
      final h = await open(t, armado(), locked: true);
      final y0 = h.ed.scroll.offset, z0 = h.tools.zoom;
      final g = await twoDown(t, a, b);
      await twoDrag(t, g, a, b, const Offset(0, -300));
      await t.pump(const Duration(milliseconds: 400)); // quietos un rato: sin inercia
      expect(h.ed.scroll.offset - y0, closeTo(300, 20));
      expect(h.tools.zoom, z0);
      await g.$1.up();
      await g.$2.up();
      await t.pumpAndSettle();
    });

    testWidgets('al soltar con un movimiento rápido sigue por inercia', (t) async {
      final h = await open(t, armado(), locked: true);
      final y0 = h.ed.scroll.offset;
      final g = await twoDown(t, a, b);
      await twoDrag(t, g, a, b, const Offset(0, -250), steps: 5, ms: 8);
      final suelto = h.ed.scroll.offset;
      expect(suelto, greaterThan(y0 + 100));
      await g.$1.up();
      await g.$2.up();
      await t.pumpAndSettle();
      expect(h.ed.scroll.offset, greaterThan(suelto + 10), reason: 'siguió después de soltar');
    });

    testWidgets('sin candado: un dedo scrollea y dos dedos separándose hacen zoom', (t) async {
      final h = await open(t, armado());
      final y0 = h.ed.scroll.offset;
      await fingerDrag(t, const Offset(1100, 800), const Offset(1100, 500));
      expect(h.ed.scroll.offset, greaterThan(y0 + 100));
      final z0 = h.tools.zoom;
      final g = await twoDown(t, const Offset(600, 500), const Offset(700, 500));
      for (var i = 1; i <= 8; i++) {
        await g.$1.moveTo(Offset(600 - i * 20.0, 500));
        await g.$2.moveTo(Offset(700 + i * 20.0, 500));
        await t.pump(const Duration(milliseconds: 16));
      }
      await g.$1.up();
      await g.$2.up();
      await t.pump(const Duration(milliseconds: 1200));
      expect(h.tools.zoom, greaterThan(z0));
    });

    testWidgets('con candado un toque corto sigue eligiendo', (t) async {
      final h = await open(t, armado(), locked: true);
      await fingerTap(t, h.at(350, 400));
      expect(h.ed.sel.isEmpty, isFalse, reason: 'eligió la imagen');
    });
  });
}
