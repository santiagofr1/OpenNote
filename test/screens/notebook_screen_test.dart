import 'dart:io';

import 'package:apuntes/app.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// El cuaderno abierto con un Storage real en una carpeta temporal (sin tablet).
/// El guardado y la lectura usan isolates, que necesitan tiempo real: de ahí runAsync.
void main() {
  late Directory root;

  setUp(() async {
    Storage.useIsolates = false;
    root = await Directory.systemTemp.createTemp('apuntes_widget');
  });
  tearDown(() async {
    Storage.useIsolates = true;
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> settle(WidgetTester t, [int ms = 600]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  /// Espera (en tiempo real) a que aparezca algo: cada paso de disco necesita su vuelta del reloj.
  Future<void> until(WidgetTester t, Finder f) async {
    for (var i = 0; i < 100 && f.evaluate().isEmpty; i++) {
      await settle(t, 100);
    }
  }

  /// Un cuaderno de 3 hojas guardado en disco, con un texto en cada una.
  Future<void> seed() async {
    final nb = Notebook.create('Prueba');
    nb.sheets.addAll([nb.newSheet(), nb.newSheet()]);
    nb.sheets[1].title = 'Ohm';
    final d = NotebookDoc(nb);
    for (var k = 0; k < 3; k++) {
      d.texts['t$k'] = TextBlock('t$k', 90, k * kSheetStep + 44, 800, 'hoja $k');
    }
    await Future(() async {
      final s = Storage(root: root);
      await s.init();
      await s.saveNotebook(d);
      await s.saveIndex(NotesIndex(notebooks: [nb]));
    });
  }

  PageEditorState editor(WidgetTester t) => t.state<PageEditorState>(find.byType(PageEditor));
  String counter(WidgetTester t, String key) {
    final w = t.widget(find.byKey(Key(key)));
    return w is Text ? (w.data ?? w.textSpan!.toPlainText()) : '';
  }

  testWidgets('abre toda la tira: contador, panel con una miniatura por hoja y operaciones', (t) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    // la fuente de prueba es más ancha que la real: los menús "se pasan" de ancho solo acá
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.exceptionAsString().contains('overflowed')) prev?.call(d);
    };
    addTearDown(() => FlutterError.onError = prev);
    await t.runAsync(seed);
    await t.pumpWidget(ApuntesApp(root: root));
    await until(t, find.byKey(const Key('nb-Prueba')));
    expect(find.byKey(const Key('nb-Prueba')), findsOneWidget);
    await t.tap(find.byKey(const Key('nb-Prueba')));
    await until(t, find.byType(PageEditor));

    expect(editor(t).doc.sheetCount, 3);
    expect(editor(t).doc.texts.length, 3);
    expect(counter(t, 'sheetCounter'), '1 / 3');

    // el contador sigue al scroll
    final ed = editor(t);
    ed.scroll.jumpTo(kSheetStep * ed.scale);
    await settle(t);
    expect(counter(t, 'sheetCounter'), 'Ohm · 2 / 3', reason: 'con el título de la hoja');
    expect(ed.visibleSheet, 1);

    // panel: una miniatura por hoja; tocar lleva a esa hoja
    await t.tap(find.byKey(const Key('pagesBtn')));
    await settle(t);
    for (var n = 1; n <= 3; n++) {
      expect(find.byKey(Key('thumb-$n')), findsOneWidget);
    }
    expect(find.text('2 · Ohm'), findsOneWidget, reason: 'el título se ve en la miniatura');
    await t.tap(find.byKey(const Key('thumb-3')));
    await settle(t, 800);
    expect(counter(t, 'sheetCounter'), '3 / 3');
    expect(counter(t, 'pageCounter'), '3 / 3');

    // mover la hoja 3 antes: su texto sube una hoja
    await t.longPress(find.byKey(const Key('thumb-3')));
    await settle(t, 400);
    await t.tap(find.text('Mover antes'));
    await settle(t, 600);
    expect(ed.doc.texts['t2']!.y, kSheetStep + 44);
    expect(ed.doc.texts['t1']!.y, 2 * kSheetStep + 44);
    expect(ed.doc.sheets[1].title, '');
    expect(ed.doc.sheets[2].title, 'Ohm');

    // agregar después de la actual
    await t.tap(find.byKey(const Key('addPage')));
    await settle(t, 800);
    expect(ed.doc.sheetCount, 4);

    // borrar una hoja con su contenido (con confirmación)
    await t.longPress(find.byKey(const Key('thumb-1')));
    await settle(t, 400);
    await t.tap(find.text('Borrar'));
    await settle(t, 400);
    await t.tap(find.byKey(const Key('confirmDelete')));
    await settle(t, 600);
    expect(ed.doc.sheetCount, 3);
    expect(ed.doc.texts.containsKey('t0'), isFalse);
    expect(ed.doc.texts['t2']!.y, 44);

    // duplicar
    await t.longPress(find.byKey(const Key('thumb-1')));
    await settle(t, 400);
    await t.tap(find.text('Duplicar'));
    await settle(t, 600);
    expect(ed.doc.sheetCount, 4);
    expect(ed.doc.texts.values.where((x) => x.text == 'hoja 2').length, 2);

    // todo se guarda al volver: notebook.json y un .sheet por hoja
    await t.tap(find.byKey(const Key('back')));
    await until(t, find.text('Cuadernos'));
    final s = Storage(root: root);
    await t.runAsync(s.init);
    // el guardado va por pasos de disco que avanzan con el reloj: se bombea hasta que termine
    var sheets = 0;
    for (var i = 0; i < 100 && sheets != 4; i++) {
      await settle(t, 100);
      sheets = await t.runAsync(() async => (await s.loadIndex()).notebooks.single.sheets.length) ?? 0;
    }
    await t.runAsync(() async {
      final nb = (await s.loadIndex()).notebooks.single;
      expect(nb.sheets.length, 4);
      final doc = await s.loadNotebook(nb);
      expect(doc.texts.length, 3);
      expect(Directory('${root.path}/notebooks/${nb.id}/sheets').listSync().where((e) => e.path.endsWith('.sheet')).length, 4);
    });
  });
}
