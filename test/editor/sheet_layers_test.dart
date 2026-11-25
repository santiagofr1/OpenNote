import 'dart:io';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:apuntes/l10n/l10n.dart';
import 'package:apuntes/rendering/ink_layers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Capas por hoja: solo se arman las hojas que se ven (más un margen) y cada hoja repinta por su cuenta.
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('apuntes_layers'));
  tearDown(() => root.deleteSync(recursive: true));

  const sheets = 30;

  Stroke line(String id, double x0, double y0, double x1, double y1) =>
      Stroke(id, 'pen', '#000000', 2, [x0, y0, .5, (x0 + x1) / 2, (y0 + y1) / 2, .5, x1, y1, .5]);

  /// 30 hojas, cada una con un trazo adentro (más lo que agregue [extra]).
  NotebookDoc big({void Function(NotebookDoc)? extra}) {
    final doc = NotebookDoc(Notebook.create('T'));
    while (doc.sheetCount < sheets) {
      doc.addSheet();
    }
    for (var k = 0; k < sheets; k++) {
      doc.strokes['s$k'] = line('s$k', 100, k * kSheetStep + 200, 600, k * kSheetStep + 400);
    }
    extra?.call(doc);
    return doc;
  }

  Future<PageEditorState> open(WidgetTester t, NotebookDoc doc, {Tool tool = Tool.pen}) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      locale: const Locale('es'),
      
      home: Scaffold(
        body: PageEditor(
            doc: doc, tools: ToolState()..tool = tool, store: Storage(root: root), onChanged: () {}, onPrefsChanged: () {}),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
    return t.state<PageEditorState>(find.byType(PageEditor));
  }

  /// Hojas (por id) que tienen alguna capa de tinta armada.
  Set<String> built(WidgetTester t, NotebookDoc doc) {
    final ids = <String>{};
    for (final w in t.widgetList(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key as ValueKey<String>).value.startsWith('ink-')))) {
      final v = (w.key as ValueKey<String>).value; // ink-<id>-<i>
      ids.add(v.substring(4, v.lastIndexOf('-')));
    }
    return ids;
  }

  List<InkPainter> painters(WidgetTester t) => [
        for (final w in t.widgetList<CustomPaint>(find.byType(CustomPaint)))
          if (w.painter is InkPainter) w.painter as InkPainter
      ];

  testWidgets('solo se arman las hojas visibles y un margen', (t) async {
    final doc = big();
    await open(t, doc);
    final ids = built(t, doc);
    expect(ids, isNotEmpty);
    expect(ids.length, lessThanOrEqualTo(4), reason: '30 hojas, pero se arman pocas');
    expect(ids, contains(doc.sheets[0].id));
    expect(ids, isNot(contains(doc.sheets[10].id)));
    expect(ids, isNot(contains(doc.sheets[29].id)));
  });

  testWidgets('al scrollear hasta el final se arman las del final y se sueltan las del principio', (t) async {
    final doc = big();
    final ed = await open(t, doc);
    ed.scroll.jumpTo(ed.scroll.position.maxScrollExtent);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    final ids = built(t, doc);
    expect(ids, contains(doc.sheets[29].id));
    expect(ids, isNot(contains(doc.sheets[0].id)));
    expect(ids.length, lessThanOrEqualTo(4));
  });

  testWidgets('un cambio en la hoja visible sube solo la versión de esa hoja', (t) async {
    final doc = big();
    final ed = await open(t, doc);
    final ids = built(t, doc).toList();
    expect(ids.length, greaterThan(1));
    final before = {for (final id in ids) id: ed.inkVersionOf(id).value};
    final target = doc.sheets[0].id;
    doc.strokes['nuevo'] = line('nuevo', 300, 700, 500, 800); // adentro de la hoja 0
    for (final id in ids) {
      final change = ed.inkVersionOf(id).value - before[id]!;
      expect(change, id == target ? greaterThan(0) : 0, reason: 'hoja $id');
    }
    // sacarlo (la goma) también avisa solo a su hoja
    final mid = {for (final id in ids) id: ed.inkVersionOf(id).value};
    doc.strokes.remove('nuevo');
    for (final id in ids) {
      expect(ed.inkVersionOf(id).value - mid[id]!, id == target ? greaterThan(0) : 0);
    }
    await t.pump();
  });

  testWidgets('un trazo que cruza de una hoja a la otra está en las capas de las dos', (t) async {
    final doc = big(extra: (d) => d.strokes['cruza'] = line('cruza', 300, kSheetH - 100, 300, kSheetStep + 100));
    await open(t, doc);
    final withIt = [for (final p in painters(t)) if (p.strokes.any((s) => s.id == 'cruza')) p];
    expect(withIt.length, 2);
    expect({for (final p in withIt) p.sheet.top}, {0.0, kSheetStep});
  });

  testWidgets('el texto con foco sigue armado aunque se scrollee lejos', (t) async {
    final doc = big(extra: (d) {
      d.texts['a'] = TextBlock('a', 130, d.snapTextY(300), 700, 'con foco');
      d.texts['b'] = TextBlock('b', 130, d.snapTextY(600), 700, 'sin foco');
    });
    final ed = await open(t, doc, tool: Tool.text);
    expect(find.byKey(const ValueKey('text-a')), findsOneWidget);
    await t.tap(find.byKey(const Key('para-a-0'))); // como el usuario: toca el texto y abre el teclado
    await t.pump(const Duration(milliseconds: 100));
    expect(ed.texts.editor('a')!.hasFocus, isTrue);
    ed.scroll.jumpTo(ed.scroll.position.maxScrollExtent);
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(built(t, doc), isNot(contains(doc.sheets[0].id)));
    expect(find.byKey(const ValueKey('text-a')), findsOneWidget, reason: 'tiene el foco: no se suelta');
    expect(find.byKey(const ValueKey('text-b')), findsNothing, reason: 'sin foco y lejos: no se arma');
    expect(ed.texts.editor('a')!.hasFocus, isTrue);
  });
}
