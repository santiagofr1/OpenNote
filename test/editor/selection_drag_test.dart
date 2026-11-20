import 'dart:io';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Selección tipo AutoCAD con un arrastre real de lápiz sobre el editor:
/// izquierda a derecha = ventana (solo lo que queda adentro), derecha a izquierda = captura (todo lo que toca).
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('apuntes_seldrag'));
  tearDown(() => root.deleteSync(recursive: true));

  // zona del recuadro, en coordenadas del documento
  const zone = Rect.fromLTRB(100, 300, 400, 600);

  Stroke line(String id, List<Offset> pts) =>
      Stroke(id, 'pen', '#000000', 2, [for (final p in pts) ...[p.dx, p.dy, .5]]);

  List<Offset> seg(Offset a, Offset b, int n) => [for (var i = 0; i < n; i++) Offset.lerp(a, b, i / (n - 1))!];

  Future<({PageEditorState ed, Offset Function(Offset) toGlobal})> open(WidgetTester t, NotebookDoc doc) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final tools = ToolState()..tool = Tool.select;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PageEditor(doc: doc, tools: tools, store: Storage(root: root), onChanged: () {}, onPrefsChanged: () {}),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
    final ed = t.state<PageEditorState>(find.byType(PageEditor));
    // el Listener de las capas es el que mide exactamente la hoja (ancho kW * escala)
    final layers = find
        .descendant(of: find.byType(PageEditor), matching: find.byType(Listener))
        .evaluate()
        .map((e) => e.renderObject as RenderBox)
        .firstWhere((b) => b.hasSize && (b.size.width - kW * ed.scale).abs() < .5);
    // documento -> pantalla (considera escala y scroll, porque se pregunta al render)
    return (ed: ed, toGlobal: (Offset p) => layers.localToGlobal(p * ed.scale));
  }

  NotebookDoc armado() {
    final doc = NotebookDoc(Notebook.create('T'));
    // A: entero dentro del recuadro
    doc.strokes['A'] = line('A', seg(const Offset(150, 350), const Offset(350, 550), 20));
    // B: cruza el recuadro, casi todo afuera (de x=300 a 900)
    doc.strokes['B'] = line('B', seg(const Offset(300, 450), const Offset(900, 450), 31));
    // C: lejos
    doc.strokes['C'] = line('C', seg(const Offset(600, 900), const Offset(900, 900), 20));
    return doc;
  }

  // arrastra con lápiz; [during] se evalúa con el puntero todavía apoyado
  Future<void> drag(WidgetTester t, Offset from, Offset to, {void Function()? during}) async {
    final g = await t.startGesture(from, kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(Offset.lerp(from, to, i / 8)!);
      await t.pump();
    }
    during?.call();
    await g.up();
    await t.pump();
  }

  Offset at(dynamic h, double x, double y) => h.toGlobal(Offset(x, y)) as Offset;

  testWidgets('ventana (izquierda a derecha): solo lo que queda adentro; durante el arrastre capture == false', (t) async {
    final h = await open(t, armado());
    var duringCapture = true;
    var duringBand = false;
    await drag(t, at(h, zone.left, zone.top), at(h, zone.right, zone.bottom), during: () {
      duringCapture = h.ed.sel.capture;
      duringBand = h.ed.sel.band != null;
    });
    expect(duringBand, isTrue);
    expect(duringCapture, isFalse);
    expect(h.ed.sel.strokes, {'A'});
    expect(h.ed.sel.texts, isEmpty);
    expect(h.ed.sel.band, isNull, reason: 'al soltar el recuadro desaparece');
  });

  testWidgets('captura (derecha a izquierda): todo lo que toca; durante el arrastre capture == true', (t) async {
    final h = await open(t, armado());
    var duringCapture = false;
    await drag(t, at(h, zone.right, zone.bottom), at(h, zone.left, zone.top), during: () => duringCapture = h.ed.sel.capture);
    expect(duringCapture, isTrue);
    expect(h.ed.sel.strokes, {'A', 'B'});
    expect(h.ed.sel.strokes, isNot(contains('C')));
  });

  testWidgets('arrastre de abajo hacia arriba sin cambiar de lado sigue siendo ventana', (t) async {
    final h = await open(t, armado());
    await drag(t, at(h, zone.left, zone.bottom), at(h, zone.right, zone.top));
    expect(h.ed.sel.strokes, {'A'});
  });

  testWidgets('un texto que el recuadro toca solo en parte: ventana no, captura sí', (t) async {
    final doc = armado();
    // el texto arranca dentro de la zona y se extiende mucho más allá: su centro queda afuera
    final y = doc.snapTextY(420);
    doc.texts['T'] = TextBlock('T', 350, y, 500, 'un texto largo que sale del recuadro');
    final h = await open(t, doc);

    await drag(t, at(h, zone.left, zone.top), at(h, zone.right, zone.bottom));
    expect(h.ed.sel.texts, isEmpty);
    expect(h.ed.sel.strokes, {'A'});

    await drag(t, at(h, zone.right, zone.bottom), at(h, zone.left, zone.top));
    expect(h.ed.sel.texts, {'T'});
    expect(h.ed.sel.strokes, {'A', 'B'});
  });

  testWidgets('un toque sin arrastre no selecciona nada', (t) async {
    final h = await open(t, armado());
    final g = await t.startGesture(at(h, 250, 450), kind: PointerDeviceKind.stylus);
    await g.up();
    await t.pump();
    expect(h.ed.sel.isEmpty, isTrue);
    expect(h.ed.sel.band, isNull);
  });

  testWidgets('el dedo no arma el recuadro (solo scrollea)', (t) async {
    final h = await open(t, armado());
    final from = at(h, zone.left, zone.top), to = at(h, zone.right, zone.bottom);
    final g = await t.startGesture(from, kind: PointerDeviceKind.touch);
    await g.moveTo(to);
    await t.pump();
    expect(h.ed.sel.band, isNull);
    await g.up();
    await t.pump();
    expect(h.ed.sel.isEmpty, isTrue);
  });
}
