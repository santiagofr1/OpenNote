import 'dart:io';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:apuntes/editor/viewport.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Al abrir o cerrar un panel lateral el ancho del visor cambia y con él la escala: la vista tiene que quedarse en el
/// mismo lugar del cuaderno (no en los mismos píxeles), también con un scroll animado en curso.
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('apuntes_resize'));
  tearDown(() => root.deleteSync(recursive: true));

  late ValueNotifier<double> width;

  Future<PageEditorState> open(WidgetTester t) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final store = Storage(root: root);
    await t.runAsync(store.init);
    final doc = NotebookDoc(Notebook.create('T'));
    while (doc.sheetCount < 8) {
      doc.addSheet();
    }
    width = ValueNotifier(1000);
    final tools = ToolState()..zoom = 1;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<double>(
          valueListenable: width,
          builder: (_, w, _) => Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
                width: w, child: PageEditor(doc: doc, tools: tools, store: store, onChanged: () {}, onPrefsChanged: () {})),
          ),
        ),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
    return t.state<PageEditorState>(find.byType(PageEditor));
  }

  double docTop(PageEditorState ed) => (ed.scroll.offset - kTopPad) / ed.scale;

  testWidgets('cambia el ancho del visor: la posición en el cuaderno se conserva', (t) async {
    final ed = await open(t);
    ed.scroll.jumpTo(3000);
    await t.pump(const Duration(milliseconds: 100));
    final before = docTop(ed), scale0 = ed.scale;
    // el ancho cambia cuadro a cuadro, como en la animación del panel
    for (var w = 1000.0; w >= 600; w -= 50) {
      width.value = w;
      await t.pump(const Duration(milliseconds: 16));
      expect(docTop(ed), closeTo(before, .5), reason: 'ancho $w');
    }
    expect(ed.scale, isNot(closeTo(scale0, 1e-3)), reason: 'la escala tiene que haber cambiado');
    for (var w = 600.0; w <= 1000; w += 50) {
      width.value = w;
      await t.pump(const Duration(milliseconds: 16));
    }
    await t.pump(const Duration(milliseconds: 100));
    expect(docTop(ed), closeTo(before, .5));
  });

  testWidgets('con un scroll animado en curso el destino se recalcula con la escala nueva', (t) async {
    final ed = await open(t);
    ed.scrollToSheetY(5, 300);
    await t.pump(const Duration(milliseconds: 100)); // a mitad de camino
    width.value = 600; // el panel se abre en un solo salto
    await t.pump(const Duration(milliseconds: 16));
    await t.pump(const Duration(milliseconds: 16));
    await t.pump(const Duration(seconds: 1));
    final want = (5 * kSheetStep + 300) * ed.scale + kTopPad - 120;
    expect(ed.scroll.offset, closeTo(want.clamp(0.0, ed.scroll.position.maxScrollExtent), 1));
    expect(ed.visibleSheet, 5);
  });
}
