import 'dart:io';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/ink.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:apuntes/l10n/l10n.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rotar la pantalla (o cambiar el tamaño de la ventana / abrir un panel) EN MEDIO de un gesto: entre el pointer down y el up.
/// Invariantes: ninguna excepción, el trazo queda entero y finito (o no se crea, pero nunca a medias), el scroll y la escala
/// siguen siendo números válidos dentro de su rango, y el editor responde a un gesto nuevo después.
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('apuntes_rot'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<({PageEditorState ed, NotebookDoc doc, ToolState tools, List<int> changes})> open(WidgetTester t) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = Storage(root: root);
    await t.runAsync(store.init);
    final doc = NotebookDoc(Notebook.create('T'));
    while (doc.sheetCount < 4) {
      doc.addSheet();
    }
    final tools = ToolState()..zoom = 1;
    final changes = <int>[];
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      locale: const Locale('es'),
      home: Scaffold(body: PageEditor(doc: doc, tools: tools, store: store, onChanged: () => changes.add(1), onPrefsChanged: () {})),
    ));
    await t.pump(const Duration(milliseconds: 300));
    return (ed: t.state<PageEditorState>(find.byType(PageEditor)), doc: doc, tools: tools, changes: changes);
  }

  Future<void> rotate(WidgetTester t, Size to) async {
    t.view.physicalSize = to;
    await t.pump(const Duration(milliseconds: 16));
  }

  void sano(WidgetTester t, PageEditorState ed, NotebookDoc doc, String reason) {
    expect(t.takeException(), isNull, reason: reason);
    expect(ed.scale.isFinite && ed.scale > 0, isTrue, reason: '$reason: escala ${ed.scale}');
    expect(ed.scroll.offset.isFinite, isTrue, reason: '$reason: scroll ${ed.scroll.offset}');
    expect(ed.scroll.offset, inInclusiveRange(ed.scroll.position.minScrollExtent - 1, ed.scroll.position.maxScrollExtent + 1), reason: reason);
    for (final s in doc.strokes.values) {
      expect(s.pts.every((v) => v.isFinite), isTrue, reason: '$reason: trazo ${s.id} con valores no finitos');
      expect(s.pts.length % 3, 0, reason: '$reason: trazo ${s.id} con puntos a medias');
    }
  }

  testWidgets('trazo con el lápiz: la pantalla rota entre el down y el up', (t) async {
    final h = await open(t);
    final g = await t.startGesture(const Offset(300, 300), kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(Offset(300.0 + i * 20, 300.0 + i * 10));
      await t.pump(const Duration(milliseconds: 8));
    }
    await rotate(t, const Size(1000, 1600)); // vertical, en medio del gesto
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(Offset(460.0 + i * 15, 380.0 + i * 12));
      await t.pump(const Duration(milliseconds: 8));
    }
    await rotate(t, const Size(1600, 1000)); // y vuelve
    await g.moveTo(const Offset(700, 600));
    await g.up();
    await t.pump(const Duration(milliseconds: 400));
    sano(t, h.ed, h.doc, 'después de soltar');
    expect(h.doc.strokes.length, 1, reason: 'el trazo se perdió o se partió en pedazos por la rotación');
    final s = h.doc.strokes.values.single;
    expect(s.n, greaterThanOrEqualTo(10), reason: 'se descartaron puntos del gesto');
    expect(h.changes, isNotEmpty);
    // y el editor sigue vivo: un segundo trazo normal
    final g2 = await t.startGesture(const Offset(600, 700), kind: PointerDeviceKind.stylus);
    await g2.moveTo(const Offset(700, 750));
    await g2.moveTo(const Offset(800, 700));
    await g2.up();
    await t.pump(const Duration(milliseconds: 400));
    expect(h.doc.strokes.length, 2);
    sano(t, h.ed, h.doc, 'segundo trazo');
  });

  testWidgets('la rotación cancela el gesto (pointer cancel): no queda un trazo fantasma ni un gesto trabado', (t) async {
    final h = await open(t);
    final g = await t.startGesture(const Offset(300, 300), kind: PointerDeviceKind.stylus);
    await g.moveTo(const Offset(400, 350));
    await g.moveTo(const Offset(500, 380));
    await rotate(t, const Size(1000, 1600));
    await g.cancel(); // Android manda ACTION_CANCEL al cambiar la configuración
    await t.pump(const Duration(milliseconds: 400));
    sano(t, h.ed, h.doc, 'después de cancelar');
    // lo que haya quedado de ese trazo tiene que ser un trazo VÁLIDO (con puntos) o nada
    for (final s in h.doc.strokes.values) {
      expect(s.n, greaterThanOrEqualTo(2));
    }
    // el siguiente gesto anda
    final antes = h.doc.strokes.length;
    final g2 = await t.startGesture(const Offset(600, 600), kind: PointerDeviceKind.stylus);
    await g2.moveTo(const Offset(700, 650));
    await g2.moveTo(const Offset(800, 600));
    await g2.up();
    await t.pump(const Duration(milliseconds: 400));
    expect(h.doc.strokes.length, antes + 1, reason: 'después de la rotación el editor quedó con un gesto trabado');
  });

  testWidgets('pellizco con dos dedos mientras la pantalla cambia de tamaño en cada cuadro', (t) async {
    final h = await open(t);
    const c = Offset(700, 500);
    final a = await t.startGesture(c - const Offset(100, 0), kind: PointerDeviceKind.touch);
    final b = await t.startGesture(c + const Offset(100, 0), kind: PointerDeviceKind.touch);
    final sizes = [const Size(1600, 1000), const Size(1000, 1600), const Size(1200, 1200), const Size(900, 700), const Size(2000, 1000)];
    for (var i = 1; i <= 40; i++) {
      await a.moveTo(c - Offset(100.0 + i * 3, 0));
      await b.moveTo(c + Offset(100.0 + i * 3, 0));
      await rotate(t, sizes[i % sizes.length]);
      sano(t, h.ed, h.doc, 'cuadro $i');
    }
    await a.up();
    await b.up();
    await t.pump(const Duration(milliseconds: 600));
    sano(t, h.ed, h.doc, 'después del pellizco');
    expect(h.tools.zoom.isFinite && h.tools.zoom > 0, isTrue, reason: 'zoom ${h.tools.zoom}');
  });

  testWidgets('scroll con el dedo con inercia y rotación a mitad: la posición queda dentro del cuaderno', (t) async {
    final h = await open(t);
    h.ed.scroll.jumpTo(2500);
    await t.pump(const Duration(milliseconds: 50));
    await t.fling(find.byType(PageEditor), const Offset(0, -400), 2500);
    await rotate(t, const Size(1000, 1600));
    await t.pump(const Duration(milliseconds: 100));
    await rotate(t, const Size(1600, 1000));
    await t.pumpAndSettle(const Duration(milliseconds: 100));
    sano(t, h.ed, h.doc, 'fling + rotación');
  });

  testWidgets('selección: arrastrar un trazo mientras la pantalla rota no lo deja a medias ni lo pierde', (t) async {
    final h = await open(t);
    // un trazo para seleccionar
    final s = Stroke('s', 'pen', '#000000', 2.6, [300, 300, .5, 400, 320, .5, 500, 300, .5])..z = 0;
    h.doc.strokes['s'] = s;
    h.tools.tool = Tool.select;
    t.element(find.byType(PageEditor)).markNeedsBuild();
    await t.pump(const Duration(milliseconds: 100));
    // el lápiz rodea y suelta; con otro gesto se arrastra
    final antes = h.doc.strokes.length;
    final g = await t.startGesture(const Offset(100, 100), kind: PointerDeviceKind.stylus);
    for (final p in [const Offset(900, 100), const Offset(900, 700), const Offset(100, 700), const Offset(100, 120)]) {
      await g.moveTo(p);
      await t.pump(const Duration(milliseconds: 8));
    }
    await rotate(t, const Size(1000, 1600));
    await g.up();
    await t.pump(const Duration(milliseconds: 300));
    sano(t, h.ed, h.doc, 'lazo con rotación');
    expect(h.doc.strokes.length, antes, reason: 'el lazo perdió o duplicó trazos');
    expect(h.doc.strokes['s']!.n, 3);
  });

  group('valores no finitos desde el hardware', () {
    test('pressureOf nunca devuelve NaN aunque el driver mande presión NaN', () {
      final e = PointerDownEvent(kind: PointerDeviceKind.stylus, pressure: double.nan, pressureMin: 0, pressureMax: 1);
      expect(pressureOf(e).isFinite, isTrue, reason: 'NaN.clamp(0, 1) es NaN: el trazo entero queda con presión NaN y no se puede guardar');
    });

    test('appendInkPoint ignora puntos NaN / infinitos (un punto malo no puede arruinar el trazo ni el guardado)', () {
      final s = Stroke('s', 'pen', '#000000', 2, []);
      appendInkPoint(s, const Offset(1, 1), .5);
      appendInkPoint(s, const Offset(double.nan, 5), .5);
      appendInkPoint(s, const Offset(5, double.infinity), .5);
      appendInkPoint(s, const Offset(20, 20), double.nan);
      appendInkPoint(s, const Offset(40, 40), .5);
      expect(s.pts.every((v) => v.isFinite), isTrue, reason: 'quedaron valores no finitos: ${s.pts}');
    });
  });
}
