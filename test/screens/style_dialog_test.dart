import 'dart:io';

import 'package:apuntes/app.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:apuntes/screens/notebook/style_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() async {
    Storage.useIsolates = false;
    root = await Directory.systemTemp.createTemp('apuntes_style');
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

  Future<void> until(WidgetTester t, Finder f) async {
    for (var i = 0; i < 100 && f.evaluate().isEmpty; i++) {
      await settle(t, 100);
    }
  }

  bool tester(WidgetTester t, String key) => find.byKey(Key(key)).evaluate().isNotEmpty;

  group('diálogo suelto', () {
    Future<StyleChoice?> open(WidgetTester t, NotebookDoc doc, Future<void> Function() body) async {
      t.view.physicalSize = const Size(1200, 2200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      StyleChoice? result;
      var done = false;
      final store = Storage(root: root);
      await t.runAsync(store.init);
      await t.pumpWidget(MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              result = await showStyleDialog(ctx, doc, store: store, sheet: 0);
              done = true;
            },
            child: const Text('abrir'),
          ),
        ),
      ));
      await t.tap(find.text('abrir'));
      await until(t, find.byType(AlertDialog)); // el diálogo lee las plantillas de disco antes de abrirse
      await t.pumpAndSettle();
      await body();
      expect(done, isTrue);
      return result;
    }

    testWidgets('las opciones de espaciado dependen del fondo', (t) async {
      final doc = NotebookDoc(Notebook.create('x'));
      await open(t, doc, () async {
        expect(find.text('Estilo de hoja'), findsOneWidget);
        for (final k in ['7', '8', '10']) {
          expect(find.byKey(Key('spacing-$k')), findsOneWidget);
        }
        expect(find.byKey(const Key('spacing-5')), findsNothing);
        await t.tap(find.text('Cuadriculado'));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('spacing-5')), findsOneWidget);
        expect(find.byKey(const Key('spacing-7')), findsOneWidget);
        expect(find.byKey(const Key('spacing-10')), findsNothing);
        await t.tap(find.text('Liso'));
        await t.pumpAndSettle();
        expect(find.textContaining(' mm'), findsNothing, reason: 'liso no tiene espaciado');
        expect(find.byKey(const Key('stylePreview')), findsOneWidget);
        await t.tap(find.byKey(const Key('styleOk')));
        await t.pumpAndSettle();
      });
    });

    testWidgets('por defecto aplica a todo el cuaderno y devuelve lo elegido', (t) async {
      final doc = NotebookDoc(Notebook.create('x'));
      final r = await open(t, doc, () async {
        await t.tap(find.text('Cuadriculado'));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('spacing-5')), findsOneWidget);
        await t.tap(find.byKey(const Key('spacing-7')));
        await t.tap(find.byTooltip('Crema'));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('styleOk')));
        await t.pumpAndSettle();
      });
      expect((r!.bg, r.paper, r.spacing, r.all), ('grid', '#fbf3e0', 7.0, true));
    });

    testWidgets('elegir el tamaño A3 lo devuelve', (t) async {
      final doc = NotebookDoc(Notebook.create('x'));
      final r = await open(t, doc, () async {
        expect(tester(t, 'size-a4'), isTrue);
        await t.tap(find.byKey(const Key('size-a3')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('styleOk')));
        await t.pumpAndSettle();
      });
      expect(r!.size, 'a3');
    });

    testWidgets('esta hoja, y cancelar devuelve null', (t) async {
      final doc = NotebookDoc(Notebook.create('x'));
      final r = await open(t, doc, () async {
        await t.tap(find.byKey(const Key('applySheet')));
        await t.tap(find.byKey(const Key('spacing-10')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('styleOk')));
        await t.pumpAndSettle();
      });
      expect((r!.bg, r.spacing, r.all), ('lined', 10.0, false));
      final c = await open(t, doc, () async {
        await t.tap(find.text('Cancelar'));
        await t.pumpAndSettle();
      });
      expect(c, isNull);
    });
  });

  testWidgets('en el cuaderno: esta hoja y todo el cuaderno, sin romper el deshacer', (t) async {
    t.view.physicalSize = const Size(1600, 2200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.exceptionAsString().contains('overflowed')) prev?.call(d);
    };
    addTearDown(() => FlutterError.onError = prev);
    await t.runAsync(() async {
      final nb = Notebook.create('Estilo');
      nb.sheets.add(nb.newSheet());
      final s = Storage(root: root);
      await s.init();
      await s.saveNotebook(NotebookDoc(nb));
      await s.saveIndex(NotesIndex(notebooks: [nb]));
    });
    await t.pumpWidget(ApuntesApp(root: root));
    await until(t, find.byKey(const Key('nb-Estilo')));
    await t.tap(find.byKey(const Key('nb-Estilo')));
    await until(t, find.byType(PageEditor));
    final ed = t.state<PageEditorState>(find.byType(PageEditor));
    ed.scroll.jumpTo(kSheetStep * ed.scale);
    await settle(t);
    expect(ed.visibleSheet, 1);

    Future<void> openDialog() async {
      await t.tap(find.byKey(const Key('more')));
      await settle(t);
      await t.tap(find.text('Estilo de hoja'));
      await until(t, find.byType(AlertDialog)); // lee las plantillas de disco antes de abrirse
      await settle(t);
    }

    await openDialog();
    await t.tap(find.text('Cuadriculado'));
    await t.tap(find.byKey(const Key('spacing-7')));
    await t.tap(find.byKey(const Key('applySheet')));
    await t.tap(find.byKey(const Key('styleOk')));
    await settle(t, 800);
    final doc = ed.doc;
    expect([doc.sheets[0].bg, doc.sheets[0].spacing], ['lined', 8.0], reason: 'la otra hoja no cambia');
    expect([doc.sheets[1].bg, doc.sheets[1].spacing], ['grid', 7.0]);
    expect([doc.nb.bg, doc.nb.spacing], ['lined', 8.0], reason: 'el estilo de las hojas nuevas tampoco');

    await openDialog();
    await t.tap(find.text('Rayado')); // el diálogo parte de la hoja visible (cuadriculada)
    await settle(t, 300);
    await t.tap(find.byKey(const Key('spacing-10')));
    await t.tap(find.byKey(const Key('applyAll')));
    await t.tap(find.byKey(const Key('styleOk')));
    await settle(t, 800);
    expect(doc.sheets.map((s) => (s.bg, s.spacing)), [('lined', 10.0), ('lined', 10.0)]);
    expect([doc.nb.bg, doc.nb.spacing], ['lined', 10.0]);
    await t.tap(find.byTooltip('Deshacer')); // sin nada que deshacer: no pasa nada
    await settle(t, 300);
    expect(doc.sheets[1].spacing, 10.0);
  });
}
