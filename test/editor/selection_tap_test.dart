import 'dart:io';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Seleccionar con un toque: elige UN elemento (el de más arriba que se ve) y alterna al tocar de nuevo;
/// tocar afuera solo cancela (no elige lo que hay abajo); el resaltador se selecciona con las mismas reglas que la tinta.
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('apuntes_seltap'));
  tearDown(() => root.deleteSync(recursive: true));

  Stroke line(String id, Offset a, Offset b, {String k = 'pen', double w = 2}) =>
      Stroke(id, k, '#000000', w, [for (var i = 0; i < 20; i++) ...[Offset.lerp(a, b, i / 19)!.dx, Offset.lerp(a, b, i / 19)!.dy, .5]]);

  Future<({PageEditorState ed, Offset Function(double, double) at})> open(WidgetTester t, NotebookDoc doc) async {
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
    final layers = find
        .descendant(of: find.byType(PageEditor), matching: find.byType(Listener))
        .evaluate()
        .map((e) => e.renderObject as RenderBox)
        .firstWhere((b) => b.hasSize && (b.size.width - kW * ed.scale).abs() < .5);
    return (ed: ed, at: (double x, double y) => layers.localToGlobal(Offset(x, y) * ed.scale));
  }

  Future<void> tap(WidgetTester t, Offset p) async {
    final g = await t.startGesture(p, kind: PointerDeviceKind.stylus);
    await g.up();
    await t.pump();
  }

  // una palabra: el resaltador (hl) se escribió DESPUÉS pero se ve debajo de la tinta de la misma tanda
  NotebookDoc palabra() {
    final doc = NotebookDoc(Notebook.create('T'));
    doc.strokes['ink'] = line('ink', const Offset(200, 400), const Offset(400, 400))..z = 0;
    doc.strokes['hl'] = line('hl', const Offset(200, 400), const Offset(400, 400), k: 'hl', w: 22)..z = 1;
    doc.strokes['lejos'] = line('lejos', const Offset(600, 800), const Offset(800, 800))..z = 2;
    return doc;
  }

  testWidgets('tocar una palabra resaltada elige la tinta (arriba); de nuevo, el resaltador; de nuevo, la tinta', (t) async {
    final h = await open(t, palabra());
    await tap(t, h.at(300, 400));
    expect(h.ed.sel.strokes, {'ink'});
    await tap(t, h.at(302, 401));
    expect(h.ed.sel.strokes, {'hl'});
    await tap(t, h.at(300, 400));
    expect(h.ed.sel.strokes, {'ink'});
  });

  testWidgets('tocar donde solo hay resaltador elige el resaltador', (t) async {
    final h = await open(t, palabra());
    await tap(t, h.at(300, 408)); // fuera de la tinta (grosor 2), dentro del resaltador (22)
    expect(h.ed.sel.strokes, {'hl'});
  });

  testWidgets('tocar afuera solo deselecciona: no elige lo que haya abajo; un segundo toque sí', (t) async {
    final h = await open(t, palabra());
    await tap(t, h.at(300, 400));
    expect(h.ed.sel.isEmpty, isFalse);
    await tap(t, h.at(500, 600));
    expect(h.ed.sel.isEmpty, isTrue);
    expect(find.text('Copiar'), findsNothing);
    // con algo seleccionado, tocar justo sobre OTRO trazo (afuera del recuadro) solo cancela
    await tap(t, h.at(300, 400));
    await tap(t, h.at(700, 800));
    expect(h.ed.sel.isEmpty, isTrue, reason: 'no elige "lejos": solo cancela');
    expect(find.text('Copiar'), findsNothing);
    expect(h.ed.history.canUndo, isFalse);
    // ya sin selección, el toque elige como siempre
    await tap(t, h.at(700, 800));
    expect(h.ed.sel.strokes, {'lejos'});
  });

  testWidgets('estirar un rectángulo afuera con algo seleccionado hace una selección nueva', (t) async {
    final h = await open(t, palabra());
    await tap(t, h.at(300, 400));
    await tester(t, h, const Offset(550, 750), const Offset(850, 850)); // ventana sobre "lejos"
    expect(h.ed.sel.strokes, {'lejos'});
  });

  testWidgets('tocar en vacío sin selección no hace nada', (t) async {
    final h = await open(t, palabra());
    await tap(t, h.at(500, 600));
    expect(h.ed.sel.isEmpty, isTrue);
    expect(h.ed.sel.band, isNull);
    expect(h.ed.history.canUndo, isFalse);
  });

  testWidgets('cambiar la selección con toques no entra al historial', (t) async {
    final h = await open(t, palabra());
    await tap(t, h.at(300, 400));
    await tap(t, h.at(300, 400));
    expect(h.ed.history.canUndo, isFalse);
  });

  testWidgets('el resaltador adentro del recuadro se selecciona igual que la tinta (ventana y captura)', (t) async {
    final h = await open(t, palabra());
    await tester(t, h, const Offset(100, 300), const Offset(500, 500)); // ventana: los dos quedan enteros adentro
    expect(h.ed.sel.strokes, {'ink', 'hl'});
    expect(find.text('Solo resaltador'), findsNothing);
    expect(find.text('Sin resaltador'), findsNothing);
    await t.tap(find.byTooltip('Deseleccionar'));
    await t.pump();
    // ventana que deja afuera casi todo: ni la tinta ni el resaltador
    await tester(t, h, const Offset(100, 300), const Offset(260, 500));
    expect(h.ed.sel.strokes, isEmpty);
    // captura (derecha a izquierda) que solo roza el borde: los dos
    await tester(t, h, const Offset(260, 500), const Offset(100, 300));
    expect(h.ed.sel.strokes, {'ink', 'hl'});
  });
}

Future<void> tester(WidgetTester t, dynamic h, Offset a, Offset b) async {
  final from = h.at(a.dx, a.dy) as Offset, to = h.at(b.dx, b.dy) as Offset;
  final g = await t.startGesture(from, kind: PointerDeviceKind.stylus);
  for (var i = 1; i <= 8; i++) {
    await g.moveTo(Offset.lerp(from, to, i / 8)!);
    await t.pump();
  }
  await g.up();
  await t.pump();
}
