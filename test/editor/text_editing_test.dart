import 'dart:io';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:apuntes/editor/rich_editing.dart';
import 'package:flutter/gestures.dart';
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
    await t.pump(const Duration(milliseconds: 600));
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

  group('selección entre párrafos', () {
    // un bloque con tres párrafos y el campo del primero enfocado
    Future<(PageEditorState, TextBlock, BlockEditor)> tres(WidgetTester t) async {
      final ed = await open(t);
      await tapKeyboardTool(t);
      final b = only(ed);
      b.body = RichBody.plain('uno\ndos\ntres');
      final be = ed.texts.editor(b.id)!..replaceModel(b);
      await t.pump(const Duration(milliseconds: 100));
      be.focusAt(0, 0); // al rearmar los campos se perdió el foco
      await t.pump(const Duration(milliseconds: 100));
      return (ed, b, be);
    }

    Offset at(WidgetTester t, TextBlock b, int i, double fx) {
      final r = t.getRect(find.byKey(Key('para-${b.id}-$i')));
      return Offset(r.left + r.width * fx, r.center.dy);
    }

    Future<void> arrastrar(WidgetTester t, TextBlock b, PointerDeviceKind kind) async {
      final g = await t.startGesture(at(t, b, 0, .0) + const Offset(1, 0), kind: kind);
      if (kind != PointerDeviceKind.mouse) await t.pump(const Duration(milliseconds: 600));
      await g.moveTo(at(t, b, 1, .0));
      await g.moveTo(at(t, b, 2, .0) + const Offset(40, 0));
      await t.pump();
      await g.up();
      await t.pump(const Duration(milliseconds: 100));
    }

    testWidgets('mouse: arrastrar de un párrafo a otro selecciona todo lo del medio', (t) async {
      final (_, b, be) = await tres(t);
      await arrastrar(t, b, PointerDeviceKind.mouse);
      expect(be.across, isNotNull);
      expect(be.acrossText, startsWith('uno\ndos\n'));
      expect(be.acrossText!.length, greaterThan(8));
      expect(find.byKey(const Key('across-copy')), findsOneWidget);
    });

    testWidgets('dedo: hace falta mantener apretado; si se mueve enseguida no selecciona', (t) async {
      final (_, b, be) = await tres(t);
      final g = await t.startGesture(at(t, b, 0, .0) + const Offset(1, 0));
      await g.moveTo(at(t, b, 2, .0));
      await t.pump();
      await g.up();
      await t.pump(const Duration(milliseconds: 100));
      expect(be.across, isNull, reason: 'sin mantener apretado no es selección');
      await arrastrar(t, b, PointerDeviceKind.touch);
      expect(be.across, isNotNull);
    });

    testWidgets('negrita y color sobre la selección que cruza párrafos', (t) async {
      final (_, b, be) = await tres(t);
      be.selectAcross(2, 10); // "o\ndos\ntr"
      await t.pump();
      await t.tap(find.byKey(const Key('fmt-bold')));
      await t.pump();
      expect(b.body.paras[0].runs.map((r) => (r.text, r.style.bold)), [('un', false), ('o', true)]);
      expect(b.body.paras[1].runs.single.style.bold, isTrue);
      expect(b.body.paras[2].runs.map((r) => (r.text, r.style.bold)), [('tr', true), ('es', false)]);
      expect(be.across, isNotNull, reason: 'la selección sigue para poder seguir formateando');
      await t.tap(find.byKey(const Key('fmt-color')));
      await t.pump();
      await t.tap(find.byKey(Key('color-${0xFFB91C1C.toRadixString(16)}')));
      await t.pump();
      expect(b.body.paras[1].runs.single.style.color, 0xFFB91C1C);
    });

    testWidgets('copiar y cortar llevan el texto al portapapeles; borrar une las puntas', (t) async {
      String? clip;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (c) async {
        if (c.method == 'Clipboard.setData') clip = (c.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final (_, b, be) = await tres(t);
      be.selectAcross(2, 10);
      await t.pump();
      await t.tap(find.byKey(const Key('across-copy')));
      await t.pump();
      expect(clip, 'o\ndos\ntr');
      expect(b.text, 'uno\ndos\ntres', reason: 'copiar no toca el texto');
      await t.tap(find.byKey(const Key('across-cut')));
      await t.pump(const Duration(milliseconds: 100));
      expect(b.text, 'unes');
      expect(be.fields.length, 1);
      expect(be.across, isNull);
      expect(find.byKey(const Key('across-copy')), findsNothing);
    });

    testWidgets('Backspace borra la selección y tocar un campo la suelta', (t) async {
      final (_, b, be) = await tres(t);
      be.selectAcross(0, 5); // "uno\nd"
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.backspace);
      await t.pump(const Duration(milliseconds: 100));
      expect(b.text, 'os\ntres');
      be.selectAcross(0, 4);
      await t.pump();
      await t.tap(find.byKey(Key('para-${b.id}-1')));
      await t.pump(const Duration(milliseconds: 100));
      expect(be.across, isNull);
    });

    testWidgets('el modelo acepta deshacer: selección entre párrafos con replaceModel la suelta', (t) async {
      final (_, b, be) = await tres(t);
      be.selectAcross(0, 6);
      be.replaceModel(b);
      expect(be.across, isNull);
    });
  });
}
