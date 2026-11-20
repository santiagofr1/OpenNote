import 'dart:io';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('apuntes_text'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<PageEditorState> open(WidgetTester t, {NotebookDoc? doc}) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final d = doc ?? NotebookDoc(Notebook.create('T'));
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PageEditor(
            doc: d, tools: ToolState(), store: Storage(root: root), onChanged: () {}, onPrefsChanged: () {}),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
    return t.state<PageEditorState>(find.byType(PageEditor));
  }

  Future<void> tapKeyboardTool(WidgetTester t) async {
    await t.tap(find.byTooltip('Texto con teclado'));
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 100));
  }

  TextBlock only(PageEditorState ed) => ed.doc.texts.values.single;

  testWidgets('la herramienta crea un bloque en el primer renglón y lo enfoca', (t) async {
    final ed = await open(t);
    await tapKeyboardTool(t);
    expect(ed.doc.texts.length, 1);
    final b = only(ed);
    expect(ed.texts.editor(b.id)!.hasFocus, isTrue);
    expect(find.byKey(const Key('fmt-bold')), findsOneWidget, reason: 'barra de formato visible');
    // el renglón es de la grilla de la hoja y cae cerca del tope de la parte visible
    expect(ed.doc.snapTextY(b.y), closeTo(b.y, .01));
    expect(b.y, lessThan(250));
  });

  testWidgets('con contenido visible, el bloque nuevo queda debajo de lo último', (t) async {
    final doc = NotebookDoc(Notebook.create('T'));
    doc.texts['a'] = TextBlock('a', 130, doc.snapTextY(300), 700, 'uno\ndos');
    final ed = await open(t, doc: doc);
    await tapKeyboardTool(t);
    final nuevo = ed.doc.texts.values.firstWhere((x) => x.id != 'a');
    final a = ed.doc.texts['a']!;
    expect(nuevo.y, greaterThanOrEqualTo(a.y + 2 * ed.doc.lineAt(a.y) - 1));
    expect(nuevo.y, lessThan(a.y + 3 * ed.doc.lineAt(a.y)));
  });

  testWidgets('tocar de nuevo en modo texto reabre el teclado en el último bloque', (t) async {
    final ed = await open(t);
    await tapKeyboardTool(t);
    final id = only(ed).id;
    await t.enterText(find.byKey(Key('para-$id-0')), 'hola');
    await t.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await t.pump(const Duration(milliseconds: 100));
    expect(ed.texts.editor(id)!.hasFocus, isFalse);
    await tapKeyboardTool(t);
    expect(ed.doc.texts.length, 1, reason: 'no crea otro: vuelve al último');
    expect(ed.texts.editor(id)!.hasFocus, isTrue);

  });

  testWidgets('un bloque vacío se borra al perder el foco; con texto se queda', (t) async {
    final ed = await open(t);
    await tapKeyboardTool(t);
    await t.tap(find.byTooltip('Lápiz · tocá de nuevo para opciones'));
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 100));
    expect(ed.doc.texts, isEmpty);

    await tapKeyboardTool(t);
    await t.enterText(find.byKey(Key('para-${only(ed).id}-0')), 'queda');
    await t.pump();
    await t.tap(find.byTooltip('Lápiz · tocá de nuevo para opciones'));
    await t.pump(const Duration(milliseconds: 200));
    expect(ed.doc.texts.length, 1);
  });

  testWidgets('negrita sobre una selección desde la barra', (t) async {
    final ed = await open(t);
    await tapKeyboardTool(t);
    final b = only(ed);
    final ctl = ed.texts.editor(b.id)!.fields[0].ctl;
    await t.enterText(find.byKey(Key('para-${b.id}-0')), 'hola mundo');
    await t.pump();
    expect(b.text, 'hola mundo');
    ctl.selection = const TextSelection(baseOffset: 1, extentOffset: 5); // "hola"
    await t.pump();
    await t.tap(find.byKey(const Key('fmt-bold')));
    await t.pump();
    expect(b.body.paras[0].runs.map((r) => (r.text, r.style.bold)), [('hola', true), (' mundo', false)]);
    expect(ed.texts.editor(b.id)!.hasFocus, isTrue, reason: 'la barra no roba el foco');
    // y el span que se ve lleva la negrita
    final span = ctl.buildTextSpan(context: t.element(find.byType(PageEditor)), withComposing: false);
    expect(span.toPlainText(), '​hola mundo');
    final bold = (span.children!.whereType<TextSpan>()).where((s) => s.style?.fontWeight == FontWeight.bold);
    expect(bold.single.text, 'hola');
  });

  testWidgets('negrita pendiente sin selección vale para lo que se escribe', (t) async {
    final ed = await open(t);
    await tapKeyboardTool(t);
    final b = only(ed);
    await t.tap(find.byKey(const Key('fmt-bold')));
    await t.pump();
    await t.enterText(find.byKey(Key('para-${b.id}-0')), 'x');
    await t.pump();
    expect(b.body.paras[0].runs.single.style.bold, isTrue);
  });

  testWidgets('Enter parte el párrafo; lista numerada numera; Tab sangra', (t) async {
    final ed = await open(t);
    await tapKeyboardTool(t);
    final b = only(ed);
    await t.tap(find.byKey(const Key('fmt-numbered')));
    await t.pump();
    await t.enterText(find.byKey(Key('para-${b.id}-0')), 'uno');
    await t.pump();
    await t.enterText(find.byKey(Key('para-${b.id}-0')), 'uno\n');
    await t.pump(const Duration(milliseconds: 100));
    expect(b.body.paras.length, 2);
    expect(b.body.paras[1].list, ListKind.numbered, reason: 'el renglón nuevo sigue la lista');
    await t.pump(const Duration(milliseconds: 100));
    await t.enterText(find.byKey(Key('para-${b.id}-1')), 'dos');
    await t.pump();
    expect(b.body.numbering(), [1, 2]);
    expect(find.text('2.'), findsOneWidget);

    // Tab sangra el párrafo con foco (el segundo)
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    expect(b.body.paras[1].indent, 1);
    expect(b.body.numbering(), [1, 1]);
    await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await t.pump();
    expect(b.body.paras[1].indent, 0);

    // Enter en un renglón de lista vacío termina la lista
    await t.enterText(find.byKey(Key('para-${b.id}-1')), '');
    await t.pump();
    await t.enterText(find.byKey(Key('para-${b.id}-1')), '\n');
    await t.pump(const Duration(milliseconds: 100));
    expect(b.body.paras.length, 2);
    expect(b.body.paras[1].list, ListKind.none);
  });

  testWidgets('Ctrl+B pone negrita en la selección', (t) async {
    final ed = await open(t);
    await tapKeyboardTool(t);
    final b = only(ed);
    await t.enterText(find.byKey(Key('para-${b.id}-0')), 'abc');
    await t.pump();
    ed.texts.editor(b.id)!.fields[0].ctl.selection = const TextSelection(baseOffset: 1, extentOffset: 4);
    await t.pump();
    await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await t.sendKeyEvent(LogicalKeyboardKey.keyB);
    await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await t.pump();
    expect(b.body.paras[0].runs.single.style.bold, isTrue);
  });

  testWidgets('casilla de tareas: tocarla la marca', (t) async {
    final ed = await open(t);
    await tapKeyboardTool(t);
    final b = only(ed);
    await t.tap(find.byKey(const Key('fmt-check')));
    await t.pump();
    await t.tap(find.byKey(Key('check-${b.id}-0')));
    await t.pump();
    expect(b.body.paras[0].checked, isTrue);
  });
}
