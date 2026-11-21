import 'dart:typed_data';

import 'dart:io';

import 'package:apuntes/app.dart';
import 'package:apuntes/data/sheet_codec.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Panel de hojas con la UI de verdad: mover arrastrando el asa, borrar y deshacer (también hojas sin cargar).
void main() {
  late Directory root;

  setUp(() async {
    Storage.useIsolates = false;
    root = await Directory.systemTemp.createTemp('apuntes_sheetops_ui');
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

  List<String> titles(NotebookDoc d) => d.sheets.map((m) => m.title).toList();

  /// Arrastra el asa de la miniatura [from] hasta la miniatura [to] (números de hoja, desde 1).
  Future<void> dragHandle(WidgetTester t, int from, int to, {PointerDeviceKind kind = PointerDeviceKind.touch}) async {
    final start = t.getCenter(find.byKey(Key('thumbHandle-$from')));
    final end = t.getCenter(find.byKey(Key('thumbDrop-$to')));
    final g = await t.startGesture(start, kind: kind);
    await t.pump(const Duration(milliseconds: 50));
    final steps = 8;
    for (var i = 1; i <= steps; i++) {
      await g.moveTo(Offset.lerp(start, end, i / steps)!);
      await t.pump(const Duration(milliseconds: 30));
    }
    await g.up();
    await settle(t, 300);
  }

  Map<String, List<int>> sheetFiles() => {
        for (final f in Directory('${root.path}/notebooks').listSync(recursive: true).whereType<File>())
          if (f.path.endsWith('.sheet')) f.uri.pathSegments.last: f.readAsBytesSync()
      };

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.stylus]) {
    testWidgets('arrastrar el asa de una miniatura mueve la hoja y se deshace ($kind)', (t) async {
      final ed = await open(t, 4);
      final doc = ed.doc;
      expect(find.byKey(const Key('thumbHandle-3')), findsOneWidget, reason: 'asa visible en cada miniatura');
      expect(titles(doc), ['H0', 'H1', 'H2', 'H3']);
      await dragHandle(t, 3, 1, kind: kind);
      expect(titles(doc), ['H2', 'H0', 'H1', 'H3']);
      expect(doc.strokes['s2']!.bounds.top, lessThan(kSheetStep), reason: 'el trazo de la hoja 3 ahora está en la 1');
      await settle(t, 1200); // guardado automático
      expect(titles(await _fromDisk(t, root)), ['H2', 'H0', 'H1', 'H3']);

      await t.tap(find.byTooltip('Deshacer'));
      await settle(t, 800);
      expect(titles(doc), ['H0', 'H1', 'H2', 'H3']);
      expect(doc.strokes['s2']!.bounds.top, greaterThan(2 * kSheetStep));
      await t.tap(find.byTooltip('Rehacer'));
      await settle(t, 800);
      expect(titles(doc), ['H2', 'H0', 'H1', 'H3']);
      await t.tap(find.byTooltip('Deshacer'));
      await settle(t, 1500);
      expect(titles(await _fromDisk(t, root)), ['H0', 'H1', 'H2', 'H3'], reason: 'el deshacer también se guardó');
    });
  }

  testWidgets('el long-press de la miniatura sigue abriendo el menú (y "Mover después" también se deshace)', (t) async {
    final ed = await open(t, 3);
    await t.longPress(find.byKey(const Key('thumb-1')));
    await settle(t, 600);
    await t.tap(find.byKey(const Key('sheetAction-moveDown')));
    await settle(t, 800);
    expect(titles(ed.doc), ['H1', 'H0', 'H2']);
    await t.tap(find.byTooltip('Deshacer'));
    await settle(t, 600);
    expect(titles(ed.doc), ['H0', 'H1', 'H2']);
  });

  testWidgets('borrar la hoja 2, deshacer: vuelve con su trazo, y rehacer la borra otra vez', (t) async {
    final ed = await open(t, 3);
    final doc = ed.doc;
    await t.longPress(find.byKey(const Key('thumb-2')));
    await settle(t, 600);
    await t.tap(find.byKey(const Key('sheetAction-delete')));
    await settle(t, 400);
    await t.tap(find.byKey(const Key('confirmDelete')));
    await settle(t, 1500);
    expect(titles(doc), ['H0', 'H2']);
    expect(doc.strokes.containsKey('s1'), isFalse);
    expect(sheetFiles().length, 2);

    await t.tap(find.byTooltip('Deshacer'));
    await settle(t, 1500);
    expect(titles(doc), ['H0', 'H1', 'H2']);
    expect(doc.strokes.containsKey('s1'), isTrue);
    expect(doc.strokes['s1']!.bounds.top, greaterThan(kSheetStep));
    expect(sheetFiles().length, 3, reason: 'el archivo de la hoja restaurada se escribió');

    await t.tap(find.byTooltip('Rehacer'));
    await settle(t, 1500);
    expect(titles(doc), ['H0', 'H2']);
  });

  testWidgets('borrar una hoja que no estaba cargada y deshacer: vuelve con el contenido de su archivo', (t) async {
    final ed = await open(t, 30);
    final doc = ed.doc;
    expect(doc.isLoadedAt(20), isFalse);
    final id = doc.sheets[20].id;
    final before = sheetFiles()['$id.sheet']!;
    // el panel es una grilla: se baja hasta la miniatura 21
    await t.scrollUntilVisible(find.byKey(const Key('thumb-21')), 300, scrollable: find.descendant(of: find.byKey(const Key('pagesPanel')), matching: find.byType(Scrollable)));
    await t.longPress(find.byKey(const Key('thumb-21')));
    await settle(t, 600);
    await t.tap(find.byKey(const Key('sheetAction-delete')));
    await settle(t, 400);
    await t.tap(find.byKey(const Key('confirmDelete')));
    await until(t, () => doc.sheetCount == 29);
    await until(t, () => !sheetFiles().containsKey('$id.sheet'), max: 60);
    expect(sheetFiles().containsKey('$id.sheet'), isFalse);

    await t.tap(find.byTooltip('Deshacer'));
    await until(t, () => sheetFiles().containsKey('$id.sheet'), max: 60);
    expect(doc.sheetCount, 30);
    expect(doc.sheets[20].id, id);
    expect(doc.strokes.containsKey('s20'), isTrue);
    expect(sheetDigest(decodeSheet(Uint8List.fromList(sheetFiles()['$id.sheet']!))), sheetDigest(decodeSheet(Uint8List.fromList(before))));
  });
}

Future<NotebookDoc> _fromDisk(WidgetTester t, Directory root) async => (await t.runAsync(() async {
      final s = Storage(root: root);
      await s.init();
      final nb = (await s.loadIndex()).notebooks.single;
      return s.loadNotebook(nb);
    }))!;
