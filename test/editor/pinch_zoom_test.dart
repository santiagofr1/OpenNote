import 'dart:io';
import 'dart:math';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:apuntes/l10n/l10n.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pellizco de zoom con el dedo (issue #27): la hoja crece suave, sin ir y volver.
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('apuntes_pinch'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<({PageEditorState ed, ToolState tools})> open(WidgetTester t) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = Storage(root: root);
    await t.runAsync(store.init);
    final doc = NotebookDoc(Notebook.create('T'));
    final tools = ToolState()..zoom = 1;
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      locale: const Locale('es'),
      
      home: Scaffold(body: PageEditor(doc: doc, tools: tools, store: store, onChanged: () {}, onPrefsChanged: () {})),
    ));
    await t.pump(const Duration(milliseconds: 300));
    return (ed: t.state<PageEditorState>(find.byType(PageEditor)), tools: tools);
  }

  /// Pellizco como en la mano: el primer dedo apoya y se corre un poco antes de que baje el segundo.
  /// Devuelve una fila por cuadro: zoom, scroll y el punto de la hoja que queda bajo el foco.
  Future<List<({double zoom, double y, double x, Offset anchor})>> pinch(WidgetTester t, PageEditorState ed,
      {double from = 100, double to = 300, double slip = 15, bool inercia = false}) async {
    final c = const Offset(800, 500);
    final rows = <({double zoom, double y, double x, Offset anchor})>[];
    void rec() {
      final off = Offset(ed.hscroll.hasClients ? ed.hscroll.offset : 0, ed.scroll.offset);
      rows.add((zoom: ed.ts.zoom, y: off.dy, x: off.dx, anchor: ed.layout.toPage(c, off)));
    }

    if (!inercia) {
      ed.scroll.jumpTo(300);
      await t.pump(const Duration(milliseconds: 16));
    }
    final a = await t.startGesture(c - Offset(from, 0), kind: PointerDeviceKind.touch);
    rec();
    var pa = c - Offset(from, 0);
    for (var i = 1; i <= 3; i++) {
      pa = c - Offset(from, 0) + Offset(slip * i / 3, -slip * i / 3);
      await a.moveTo(pa);
      await t.pump(const Duration(milliseconds: 16));
      rec();
    }
    final b = await t.startGesture(c + Offset(from, 0), kind: PointerDeviceKind.touch);
    // como el hardware real: varios eventos por cuadro, y el segundo dedo ya se mueve antes del primer cuadro
    for (var i = 1; i <= 60; i++) {
      final d = from + (to - from) * i / 60;
      await a.moveTo(pa - Offset(d - from, 0));
      await b.moveTo(c + Offset(d, 0));
      if (i % 3 == 0) {
        await t.pump(const Duration(milliseconds: 16));
        rec();
      }
    }
    await a.up();
    await b.up();
    await t.pump(const Duration(milliseconds: 400));
    return rows;
  }

  void sinTemblor(List<({double zoom, double y, double x, Offset anchor})> r) {
    for (var i = 1; i < r.length; i++) {
      expect(r[i].zoom, greaterThanOrEqualTo(r[i - 1].zoom - 1e-9), reason: 'zoom monótono (cuadro $i)');
      expect((r[i].y - r[i - 1].y).abs(), lessThan(120), reason: 'el scroll no salta (cuadro $i)');
    }
    expect(r.last.zoom, greaterThan(r.first.zoom + .5), reason: 'separar los dedos agranda');
  }

  testWidgets('pellizco en un editor recién abierto', (t) async {
    final h = await open(t);
    final r = await pinch(t, h.ed);
    sinTemblor(r);
  });

  testWidgets('pellizco después de poner y sacar el candado', (t) async {
    final h = await open(t);
    h.tools.zoomLocked = true;
    t.element(find.byType(PageEditor)).markNeedsBuild();
    await t.pump(const Duration(milliseconds: 100));
    h.tools.zoomLocked = false;
    t.element(find.byType(PageEditor)).markNeedsBuild();
    await t.pump(const Duration(milliseconds: 100));
    final r = await pinch(t, h.ed);
    sinTemblor(r);
  });

  testWidgets('pellizco justo después de arrastrar con dos dedos con candado (inercia andando)', (t) async {
    final h = await open(t);
    h.ed.scroll.jumpTo(100);
    h.tools.zoomLocked = true;
    t.element(find.byType(PageEditor)).markNeedsBuild();
    await t.pump(const Duration(milliseconds: 100));
    final a = await t.startGesture(const Offset(700, 800), kind: PointerDeviceKind.touch);
    final b = await t.startGesture(const Offset(900, 800), kind: PointerDeviceKind.touch);
    for (var i = 1; i <= 8; i++) {
      await a.moveTo(Offset(700, 800 - 40.0 * i));
      await b.moveTo(Offset(900, 800 - 40.0 * i));
      await t.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await t.pump(const Duration(milliseconds: 16));
    // ignore: avoid_print
    print('tras soltar: y=${h.ed.scroll.offset} panning=${h.ed.touch.panning} pinching=${h.ed.touch.pinching}');
    h.tools.zoomLocked = false;
    t.element(find.byType(PageEditor)).markNeedsBuild();
    await t.pump(const Duration(milliseconds: 16));
    final r = await pinch(t, h.ed, inercia: true);
    sinTemblor(r);
  });

  testWidgets('el punto bajo el foco no se corre en el cuadro pintado (un solo pump por paso)', (t) async {
    final h = await open(t);
    h.ed.scroll.jumpTo(300);
    await t.pump(const Duration(milliseconds: 16));
    const c = Offset(800, 500); // global
    // el visor no arranca en (0, 0) de la ventana: el foco en sus coordenadas es c menos su origen
    final vp = find
        .descendant(of: find.byType(PageEditor), matching: find.byType(Listener))
        .evaluate()
        .map((e) => e.renderObject as RenderBox)
        .where((b) => b.hasSize && (b.size.height - h.ed.scroll.position.viewportDimension).abs() < .5)
        .first;
    final f = c - vp.localToGlobal(Offset.zero);
    Offset off() => Offset(h.ed.hscroll.hasClients ? h.ed.hscroll.offset : 0, h.ed.scroll.offset);
    final p0 = h.ed.layout.toPage(f, off());
    final err = <double>[];
    final a = await t.startGesture(c - const Offset(100, 0), kind: PointerDeviceKind.touch);
    final b = await t.startGesture(c + const Offset(100, 0), kind: PointerDeviceKind.touch);
    await t.pump(const Duration(milliseconds: 16));
    for (var i = 1; i <= 20; i++) {
      // se mide al terminar de pintar el cuadro, antes de cualquier corrección posterior (se registra primero)
      WidgetsBinding.instance.addPostFrameCallback((_) => err.add((h.ed.layout.scrollFor(p0, f) - off()).distance));
      await a.moveTo(c - Offset(100 + 10.0 * i, 0));
      await b.moveTo(c + Offset(100 + 10.0 * i, 0));
      await t.pump(const Duration(milliseconds: 16));
    }
    await a.up();
    await b.up();
    await t.pump(const Duration(milliseconds: 400));
    expect(h.tools.zoom, greaterThan(2.5));
    expect(err.reduce(max), lessThan(2), reason: 'errores: $err');
  });
}
