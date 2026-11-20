import 'dart:io';

import 'package:apuntes/app.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Mismo escenario que el de integración, pero con reloj real (como en la tablet):
// mantener apretado (puntero apoyado más de 500 ms) y soltar, dos borrados seguidos.
void main() {
  LiveTestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('apuntes_live'));
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<void> settle(WidgetTester t, [int ms = 400]) async {
    final end = DateTime.now().add(Duration(milliseconds: ms));
    while (DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await t.pump();
    }
  }

  Future<void> holdOn(WidgetTester t, Finder f) async {
    final g = await t.startGesture(t.getCenter(f));
    await settle(t, 750);
    await g.up();
    await t.pump();
  }

  PageEditorState editor(WidgetTester t) => t.state<PageEditorState>(find.byType(PageEditor));

  testWidgets('dos borrados seguidos desde el panel, con reloj real', (t) async {
    t.view.physicalSize = const Size(800, 1333);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.exceptionAsString().contains('overflowed')) prev?.call(d);
    };
    addTearDown(() => FlutterError.onError = prev);
    final s = Storage(root: root);
    await s.init();
    final nb = Notebook.create('Hojas');
    await s.saveNotebook(NotebookDoc(nb));
    await s.saveIndex(NotesIndex(notebooks: [nb]));
    await t.pumpWidget(ApuntesApp(root: root));
    await settle(t, 1500);
    await t.tap(find.byKey(const Key('nb-Hojas')));
    await settle(t, 1500);
    await t.tap(find.byKey(const Key('pagesBtn')));
    await settle(t, 600);
    for (var i = 0; i < 2; i++) {
      await t.tap(find.byKey(const Key('addPage')));
      await settle(t, 900);
    }
    expect(editor(t).doc.sheetCount, 3);
    Future<void> act(int n, String item) async {
      await holdOn(t, find.byKey(Key('thumb-$n')));
      await settle(t, 500);
      expect(find.text(item), findsOneWidget, reason: 'thumb-$n sin "$item"');
      await t.tap(find.text(item));
      await settle(t, 900);
    }

    await act(1, 'Mover después');
    await act(2, 'Borrar');
    await t.tap(find.byKey(const Key('confirmDelete')));
    await settle(t, 900);
    expect(editor(t).doc.sheetCount, 2);
    await act(2, 'Borrar');
    await t.tap(find.byKey(const Key('confirmDelete')));
    await settle(t, 900);
    expect(editor(t).doc.sheetCount, 1);
  });
}
