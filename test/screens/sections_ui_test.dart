import 'dart:convert';
import 'dart:io';

import 'package:apuntes/app.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Secciones con la UI de verdad: el botón del panel, la lista, crear / cambiar / renombrar / subir / bajar / borrar,
/// y que escribir en una no toque la otra.
void main() {
  late Directory root;

  setUp(() async {
    Storage.useIsolates = false;
    root = await Directory.systemTemp.createTemp('apuntes_sections_ui');
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

  Future<void> seed() async {
    final nb = Notebook.create('Hojas');
    final d = NotebookDoc(nb);
    d.strokes['g0'] = Stroke('g0', 'pen', '#22211e', 2.6, [100, 300, .5, 200, 340, .5]);
    final s = Storage(root: root);
    await s.init();
    await s.saveNotebook(d);
    await s.saveIndex(NotesIndex(notebooks: [nb]));
  }

  Future<PageEditorState> open(WidgetTester t) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.exceptionAsString().contains('overflowed')) prev?.call(d);
    };
    addTearDown(() => FlutterError.onError = prev);
    await t.runAsync(seed);
    await t.pumpWidget(ApuntesApp(root: root));
    await until(t, () => find.byKey(const Key('nb-Hojas')).evaluate().isNotEmpty);
    await t.tap(find.byKey(const Key('nb-Hojas')));
    await until(t, () => find.byType(PageEditor).evaluate().isNotEmpty);
    await settle(t, 400);
    await t.tap(find.byKey(const Key('pagesBtn')));
    await settle(t, 600);
    return t.state<PageEditorState>(find.byType(PageEditor));
  }

  PageEditorState editor(WidgetTester t) => t.state<PageEditorState>(find.byType(PageEditor));
  // (mientras se cambia de sección el panel está vacío un momento)
  String sectionName(WidgetTester t) =>
      find.byKey(const Key('sectionName')).evaluate().isEmpty ? '' : (t.widget(find.byKey(const Key('sectionName'))) as Text).data!;

  Future<void> openList(WidgetTester t) async {
    await t.tap(find.byKey(const Key('sectionsButton')));
    await settle(t, 400);
  }

  Future<void> typeName(WidgetTester t, String name) async {
    await t.enterText(find.byKey(const Key('askText')), name);
    await t.tap(find.byKey(const Key('askOk')));
    await settle(t, 600);
  }

  Future<void> newSection(WidgetTester t, String name) async {
    await openList(t);
    await t.tap(find.byKey(const Key('newSection')));
    await settle(t, 400);
    await typeName(t, name);
    await until(t, () => sectionName(t) == name);
    await settle(t, 600);
  }

  Notebook diskNotebook(WidgetTester t) {
    final j = jsonDecode(File('${root.path}/notebooks/${Directory('${root.path}/notebooks').listSync().single.uri.pathSegments.where((e) => e.isNotEmpty).last}/notebook.json').readAsStringSync()) as Map;
    return Notebook('x', 'x')..loadSheetsJson(j);
  }

  Set<String> sheetFiles() => {
        for (final f in Directory('${root.path}/notebooks').listSync(recursive: true).whereType<File>())
          if (f.path.endsWith('.sheet')) f.uri.pathSegments.last
      };

  testWidgets('el botón siempre está, muestra la sección activa y abre la lista', (t) async {
    await open(t);
    expect(find.byKey(const Key('sectionsButton')), findsOneWidget);
    expect(sectionName(t), 'General');
    await openList(t);
    expect(find.byKey(const Key('section-$kGeneralSection')), findsOneWidget);
    expect(find.text('1 hoja'), findsOneWidget);
    expect(find.byKey(const Key('newSection')), findsOneWidget);
    // con una sola sección no se puede borrar
    await t.tap(find.byKey(const Key('sectionMenu-$kGeneralSection')));
    await settle(t, 300);
    final del = t.widget<PopupMenuItem<dynamic>>(find.byKey(const Key('sectionDelete')));
    expect(del.enabled, isFalse);
  });

  testWidgets('crear una sección, escribir en ella, volver y ver que cada una tiene lo suyo (y persiste)', (t) async {
    final ed0 = await open(t);
    expect(ed0.doc.strokes.keys, ['g0']);
    final gSheet = ed0.doc.sheets.single.id;

    await newSection(t, 'Práctica');
    var ed = editor(t);
    expect(sectionName(t), 'Práctica');
    expect(ed.doc.sheetCount, 1);
    expect(ed.doc.strokes, isEmpty, reason: 'la otra sección no se ve');
    expect(ed.doc.sheets.single.id, isNot(gSheet));
    final pSheet = ed.doc.sheets.single.id;
    // se escribe en ella
    ed.doc.strokes['p0'] = Stroke('p0', 'pen', '#cc0000', 3, [120, 320, .5, 220, 360, .5]);
    ed.doc.markDirtyElement(ed.doc.strokes['p0']!);
    ed.widget.onChanged();
    await settle(t, 1500);
    expect(sheetFiles(), {'$gSheet.sheet', '$pSheet.sheet'});

    // volver a General: está su trazo y no el de la otra
    await openList(t);
    await t.tap(find.byKey(const Key('section-$kGeneralSection')));
    await until(t, () => sectionName(t) == 'General');
    await settle(t, 600);
    ed = editor(t);
    expect(ed.doc.strokes.keys, ['g0']);
    expect(sheetFiles().length, 2, reason: 'cambiar de sección no borra nada');
    // en disco: la activa quedó guardada
    expect(diskNotebook(t).active, kGeneralSection);

    // cerrar y reabrir el cuaderno: sigue en General; la otra sección conserva su trazo
    await t.tap(find.byKey(const Key('back')));
    await until(t, () => find.byKey(const Key('nb-Hojas')).evaluate().isNotEmpty);
    await settle(t, 400);
    await t.tap(find.byKey(const Key('nb-Hojas')));
    await until(t, () => find.byType(PageEditor).evaluate().isNotEmpty);
    await settle(t, 400);
    await t.tap(find.byKey(const Key('pagesBtn')));
    await settle(t, 600);
    expect(sectionName(t), 'General');
    expect(editor(t).doc.strokes.keys, ['g0']);
    await openList(t);
    final pId = diskNotebook(t).sections.last.id;
    await t.tap(find.byKey(Key('section-$pId')));
    await until(t, () => sectionName(t) == 'Práctica');
    await settle(t, 600);
    expect(editor(t).doc.strokes.keys, ['p0']);
  });

  testWidgets('renombrar, subir y bajar', (t) async {
    await open(t);
    await newSection(t, 'Práctica');
    final pId = editor(t).doc.nb.activeSection.id;

    await openList(t);
    await t.tap(find.byKey(Key('sectionMenu-$pId')));
    await settle(t, 300);
    await t.tap(find.byKey(const Key('sectionRename')));
    await settle(t, 400);
    await typeName(t, 'Teoría');
    expect(sectionName(t), 'Teoría');
    expect(diskNotebook(t).sections.map((s) => s.name), ['General', 'Teoría']);

    await openList(t);
    await t.tap(find.byKey(Key('sectionMenu-$pId')));
    await settle(t, 300);
    await t.tap(find.byKey(const Key('sectionUp')));
    await settle(t, 800);
    expect(diskNotebook(t).sections.map((s) => s.name), ['Teoría', 'General']);

    await openList(t);
    await t.tap(find.byKey(Key('sectionMenu-$pId')));
    await settle(t, 300);
    await t.tap(find.byKey(const Key('sectionDown')));
    await settle(t, 800);
    expect(diskNotebook(t).sections.map((s) => s.name), ['General', 'Teoría']);
  });

  testWidgets('borrar: confirma diciendo cuántas hojas, borra solo sus archivos, y si era la activa abre otra', (t) async {
    final ed0 = await open(t);
    final gSheet = ed0.doc.sheets.single.id;
    await newSection(t, 'Práctica');
    final ed = editor(t);
    final pId = ed.doc.nb.activeSection.id, pSheet = ed.doc.sheets.single.id;
    expect(sheetFiles(), {'$gSheet.sheet', '$pSheet.sheet'});

    await openList(t);
    await t.tap(find.byKey(Key('sectionMenu-$pId')));
    await settle(t, 300);
    await t.tap(find.byKey(const Key('sectionDelete')));
    await settle(t, 400);
    expect(find.textContaining('Se borra 1 hoja'), findsOneWidget);
    // cancelar no borra
    await t.tap(find.text('Cancelar'));
    await settle(t, 400);
    expect(sectionName(t), 'Práctica');

    await openList(t);
    await t.tap(find.byKey(Key('sectionMenu-$pId')));
    await settle(t, 300);
    await t.tap(find.byKey(const Key('sectionDelete')));
    await settle(t, 400);
    await t.tap(find.byKey(const Key('confirmDelete')));
    await until(t, () => sectionName(t) == 'General');
    await until(t, () => sheetFiles().length == 1, max: 60); // el guardado borra los archivos
    expect(editor(t).doc.strokes.keys, ['g0']);
    expect(sheetFiles(), {'$gSheet.sheet'}, reason: 'solo se borró lo de la sección');
    expect(diskNotebook(t).sections.map((s) => s.name), ['General']);
  });

  testWidgets('exportar con varias secciones pregunta cuáles: "Todas" o marcar a mano', (t) async {
    await open(t);
    await newSection(t, 'Práctica');
    await t.tap(find.byKey(const Key('more')));
    await settle(t, 300);
    await t.tap(find.text('Exportar'));
    await settle(t, 400);
    await t.tap(find.byKey(const Key('export-pdf')));
    await settle(t, 400);
    expect(find.byKey(const Key('exportSectionsAll')), findsOneWidget);
    FilledButton ok() => t.widget<FilledButton>(find.byKey(const Key('exportSectionsOk')));
    expect(ok().onPressed, isNotNull);
    // desmarcar "Todas" deja ninguna: no se puede exportar
    await t.tap(find.byKey(const Key('exportSectionsAll')));
    await settle(t, 200);
    expect(ok().onPressed, isNull);
    // marcar a mano una
    await t.tap(find.byKey(const Key('exportSection-$kGeneralSection')));
    await settle(t, 200);
    expect(ok().onPressed, isNotNull);
    expect(t.widget<CheckboxListTile>(find.byKey(const Key('exportSectionsAll'))).value, isFalse);
    await t.tap(find.text('Cancelar'));
    await settle(t, 300);
    expect(find.byKey(const Key('exportSectionsAll')), findsNothing);
  });
}
