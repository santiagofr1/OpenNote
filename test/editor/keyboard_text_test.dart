import 'dart:io';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:apuntes/editor/rich_editing.dart';
import 'package:apuntes/l10n/l10n.dart';
import 'package:apuntes/rendering/text_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('apuntes_kb'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<PageEditorState> open(WidgetTester t, {NotebookDoc? doc}) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final d = doc ?? NotebookDoc(Notebook.create('T'));
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      locale: const Locale('es'),
      
      home: Scaffold(
        body: PageEditor(
            doc: d,
            tools: ToolState()..tool = Tool.text,
            store: Storage(root: root),
            onChanged: () {},
            onPrefsChanged: () {}),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
    return t.state<PageEditorState>(find.byType(PageEditor));
  }

  Future<void> settle(WidgetTester t) async {
    await t.pump(const Duration(milliseconds: 100));
    await t.pump(const Duration(milliseconds: 100));
  }

  NotebookDoc twoSheets() {
    final nb = Notebook.create('T');
    nb.sheets.add(nb.newSheet());
    return NotebookDoc(nb);
  }

  group('el texto va donde se toca', () {
    testWidgets('en el margen de arriba de una hoja rayada: el bloque queda arriba de la primera línea', (t) async {
      final ed = await open(t);
      ed.tapTextAt(const Offset(200, 20));
      await settle(t);
      final b = ed.doc.texts.values.single;
      expect(b.y, lessThan(mmToUnits(ruleYsFirstMm(ed.doc))));
      expect(b.x, 200);
    });

    testWidgets('cerca del borde de abajo con lugar para un renglón no salta a la hoja siguiente', (t) async {
      final ed = await open(t, doc: twoSheets());
      final line = ed.doc.lineAt(10);
      final fit = ed.doc.snapTextY(kSheetH - line - 1, floor: true); // el último renglón que entra
      ed.tapTextAt(Offset(200, fit + 1));
      await settle(t);
      expect(ed.doc.texts.values.single.y, lessThan(kSheetH));
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(t);
      // sin lugar: a la hoja de abajo
      ed.tapTextAt(const Offset(200, kSheetH - 0.1));
      await settle(t);
      expect(ed.doc.texts.values.single.y, greaterThanOrEqualTo(kSheetStep));
    });
  });

  group('tocar debajo de un bloque lo sigue', () {
    Future<(PageEditorState, TextBlock, double)> withBlock(WidgetTester t) async {
      final doc = NotebookDoc(Notebook.create('T'));
      doc.texts['a'] = TextBlock('a', 130, doc.snapTextY(300), 700, 'uno');
      final ed = await open(t, doc: doc);
      final a = ed.doc.texts['a']!, line = ed.doc.lineAt(a.y);
      return (ed, a, line);
    }

    testWidgets('el renglón justo debajo: un párrafo más, con el foco ahí', (t) async {
      final (ed, a, line) = await withBlock(t);
      ed.tapTextAt(Offset(200, textRect(a, line).bottom + 3));
      await settle(t);
      expect(ed.doc.texts.length, 1);
      expect(a.body.paras.length, 2);
      final be = ed.texts.editor('a')!;
      expect(be.hasFocus, isTrue);
      expect(be.active, 1);
    });

    testWidgets('a 3 renglones: 3 párrafos más', (t) async {
      final (ed, a, line) = await withBlock(t);
      ed.tapTextAt(Offset(200, textRect(a, line).bottom + 2 * line + 3));
      await settle(t);
      expect(ed.doc.texts.length, 1);
      expect(a.body.paras.length, 4);
      expect(ed.texts.editor('a')!.active, 3);
    });

    testWidgets('lejos en x o más de 3 renglones: bloque nuevo', (t) async {
      final (ed, a, line) = await withBlock(t);
      ed.tapTextAt(Offset(900, textRect(a, line).bottom + 3));
      await settle(t);
      expect(ed.doc.texts.length, 2);
      expect(a.body.paras.length, 1);
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(t);
      ed.tapTextAt(Offset(200, textRect(a, line).bottom + 4 * line));
      await settle(t);
      expect(a.body.paras.length, 1);
    });

    testWidgets('tocar adentro del bloque pone el cursor ahí y no crea otro', (t) async {
      final (ed, _, _) = await withBlock(t);
      await t.tap(find.byKey(const Key('para-a-0')));
      await settle(t);
      expect(ed.doc.texts.length, 1);
      expect(ed.texts.editor('a')!.hasFocus, isTrue);
    });
  });

  group('atajos dentro del texto', () {
    Future<(PageEditorState, TextBlock, BlockEditor)> write(WidgetTester t, String s) async {
      final ed = await open(t);
      ed.tapTextAt(const Offset(200, 300));
      await settle(t);
      final b = ed.doc.texts.values.single;
      await t.enterText(find.byKey(Key('para-${b.id}-0')), s);
      await t.pump();
      final be = ed.texts.editor(b.id)!;
      be.fields[0].ctl.selection = TextSelection(baseOffset: 1, extentOffset: 1 + s.length);
      await t.pump();
      return (ed, b, be);
    }

    Future<void> combo(WidgetTester t, List<LogicalKeyboardKey> mods, LogicalKeyboardKey k) async {
      for (final m in mods) {
        await t.sendKeyDownEvent(m);
      }
      await t.sendKeyEvent(k);
      for (final m in mods.reversed) {
        await t.sendKeyUpEvent(m);
      }
      await t.pump();
    }

    const ctrl = LogicalKeyboardKey.controlLeft, shift = LogicalKeyboardKey.shiftLeft, alt = LogicalKeyboardKey.altLeft;

    testWidgets('Ctrl+Shift+H pone y saca el resaltado con el último color', (t) async {
      final (_, b, be) = await write(t, 'abc');
      lastHighlight = 0xFF5EE08A;
      await combo(t, [ctrl, shift], LogicalKeyboardKey.keyH);
      expect(b.body.paras[0].runs.single.style.highlight, 0xFF5EE08A);
      await combo(t, [ctrl, shift], LogicalKeyboardKey.keyH);
      expect(b.body.paras[0].runs.single.style.highlight, isNull);
      expect(be.currentHighlight, isNull);
      lastHighlight = 0xFFF7D22C;
    });

    testWidgets('Alt+Shift+5 tacha', (t) async {
      final (_, b, _) = await write(t, 'abc');
      await combo(t, [alt, shift], LogicalKeyboardKey.digit5);
      expect(b.body.paras[0].runs.single.style.strike, isTrue);
    });

    testWidgets('Ctrl+Shift+8 pone viñetas y otra vez las saca', (t) async {
      final (_, b, _) = await write(t, 'abc');
      await combo(t, [ctrl, shift], LogicalKeyboardKey.digit8);
      expect(b.body.paras[0].list, ListKind.bullet);
      await combo(t, [ctrl, shift], LogicalKeyboardKey.digit8);
      expect(b.body.paras[0].list, ListKind.none);
      await combo(t, [ctrl, shift], LogicalKeyboardKey.digit7);
      expect(b.body.paras[0].list, ListKind.numbered);
      await combo(t, [ctrl, shift], LogicalKeyboardKey.digit9);
      expect(b.body.paras[0].list, ListKind.checklist);
    });

    testWidgets('Ctrl+E centra, Ctrl+R derecha, Ctrl+J justifica, Ctrl+L izquierda', (t) async {
      final (_, b, _) = await write(t, 'abc');
      await combo(t, [ctrl], LogicalKeyboardKey.keyE);
      expect(b.body.paras[0].align, ParaAlign.center);
      await combo(t, [ctrl], LogicalKeyboardKey.keyR);
      expect(b.body.paras[0].align, ParaAlign.right);
      await combo(t, [ctrl], LogicalKeyboardKey.keyJ);
      expect(b.body.paras[0].align, ParaAlign.justify);
      await combo(t, [ctrl], LogicalKeyboardKey.keyL);
      expect(b.body.paras[0].align, ParaAlign.left);
    });
  });
}

/// Altura (mm) de la primera línea del rayado de la hoja 0.
double ruleYsFirstMm(NotebookDoc d) => ruleYs(d.sheets[0].spacing).first / mmToUnits(1);
