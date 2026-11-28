
import 'dart:io';

import 'package:apuntes/app.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Marcadores de hojas (issue #35): botón de arriba, lista en el panel y salto a la hoja.
void main() {
  late Directory root;

  setUp(() async {
    Storage.useIsolates = false;
    root = await Directory.systemTemp.createTemp('apuntes_bookmarks_ui');
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

  Future<void> until(WidgetTester t, bool Function() ok, {int max = 100}) async {
    for (var i = 0; i < max && !ok(); i++) {
      await settle(t, 100);
    }
  }

  Future<void> seed(int n) async {
    final nb = Notebook.create('Hojas');
    while (nb.sheets.length < n) {
      nb.sheets.add(nb.newSheet());
    }
    final d = NotebookDoc(nb);
    for (var k = 0; k < n; k++) {
      nb.sheets[k].title = 'H$k';
      d.strokes['s$k'] = Stroke('s$k', 'pen', '#22211e', 2.6, [100, k * kSheetStep + 300, .5, 200, k * kSheetStep + 340, .5]);
    }
    final s = Storage(root: root);
    await s.init();
    await s.saveNotebook(d);
    await s.saveIndex(NotesIndex(notebooks: [nb]));
  }

  Future<PageEditorState> open(WidgetTester t, int n) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.exceptionAsString().contains('overflowed')) prev?.call(d);
    };
    addTearDown(() => FlutterError.onError = prev);
    await t.runAsync(() => seed(n));
    await t.pumpWidget(ApuntesApp(root: root));
    await until(t, () => find.byKey(const Key('nb-Hojas')).evaluate().isNotEmpty);
    await t.tap(find.byKey(const Key('nb-Hojas')));
    await until(t, () => find.byType(PageEditor).evaluate().isNotEmpty);
    await settle(t, 400);
    await t.tap(find.byKey(const Key('pagesBtn')));
    await settle(t, 600);
    return t.state<PageEditorState>(find.byType(PageEditor));
  }

  testWidgets('el botón de arriba marca con nombre, la lista del panel lleva a la hoja y desmarca', (t) async {
    final ed = await open(t, 3);
    final doc = ed.doc;
    await t.tap(find.byKey(const Key('thumb-3')));
    await settle(t, 800);
    await t.tap(find.byKey(const Key('bookmarkSheet')));
    await settle(t, 400);
    // cancelar no marca
    await t.tapAt(const Offset(5, 5));
    await settle(t, 400);
    expect(doc.sheets[2].bookmark, isFalse);
    await t.tap(find.byKey(const Key('bookmarkSheet')));
    await settle(t, 400);
    await t.enterText(find.byKey(const Key('bookmarkName')), ' Parcial ');
    await t.tap(find.byKey(const Key('bookmarkSave')));
    await settle(t, 600);
    expect([doc.sheets[2].bookmark, doc.sheets[2].title], [true, 'Parcial']);

    await t.tap(find.byTooltip('Solo marcadas'));
    await settle(t, 400);
    final item = find.byKey(Key('bookmarkItem-${doc.sheets[2].id}'));
    expect(find.descendant(of: item, matching: find.text('Parcial')), findsOneWidget);
    expect(find.descendant(of: item, matching: find.text('Hoja 3')), findsOneWidget);
    await t.tap(find.byTooltip('Ver todas'));
    await settle(t, 400);
    await t.tap(find.byKey(const Key('thumb-1')));
    await settle(t, 800);
    expect(t.widget<Text>(find.byKey(const Key('sheetCounter'))).data, '1 / 3');
    await t.tap(find.byTooltip('Solo marcadas'));
    await settle(t, 400);
    await t.tap(item);
    await settle(t, 800);
    expect(t.widget<Text>(find.byKey(const Key('sheetCounter'))).data, '3 / 3');

    // "Sin nombre" marca sin tocar el título; el botón desmarca
    await t.tap(find.byKey(const Key('bookmarkSheet')));
    await settle(t, 400);
    expect(doc.sheets[2].bookmark, isFalse);
    expect(find.byKey(const Key('noBookmarks')), findsOneWidget);
    await t.tap(find.byKey(const Key('bookmarkSheet')));
    await settle(t, 400);
    await t.tap(find.text('Sin nombre'));
    await settle(t, 400);
    expect([doc.sheets[2].bookmark, doc.sheets[2].title], [true, 'Parcial']);
    await settle(t, 1500); // guardado automático
  });
}
