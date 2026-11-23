import 'dart:io';

import 'package:apuntes/app.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Atajos de teclado de la hoja (fuera de los textos) y el diálogo de atajos.
void main() {
  late Directory root;

  setUp(() async {
    Storage.useIsolates = false;
    root = await Directory.systemTemp.createTemp('apuntes_shortcuts');
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

  Future<PageEditorState> openNotebook(WidgetTester t) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final nb = Notebook.create('Prueba');
    await t.runAsync(() async {
      final s = Storage(root: root);
      await s.init();
      await s.saveNotebook(NotebookDoc(nb));
      await s.saveIndex(NotesIndex(notebooks: [nb]));
    });
    await t.pumpWidget(ApuntesApp(root: root));
    await until(t, find.byKey(const Key('nb-Prueba')));
    await t.tap(find.byKey(const Key('nb-Prueba')));
    await until(t, find.byType(PageEditor));
    await settle(t);
    return t.state<PageEditorState>(find.byType(PageEditor));
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

  testWidgets('Ctrl+Z / Ctrl+Y deshacen y rehacen un trazo; P/H/T/S eligen herramienta; Ctrl+/ abre los atajos',
      (t) async {
    final ed = await openNotebook(t);
    // un trazo con el mouse (el dedo no dibuja)
    final g = await t.startGesture(const Offset(600, 400), kind: PointerDeviceKind.mouse, buttons: kPrimaryMouseButton);
    await g.moveBy(const Offset(60, 0));
    await g.moveBy(const Offset(60, 30));
    await g.up();
    await t.pump(const Duration(milliseconds: 100));
    expect(ed.doc.strokes.length, 1);

    const ctrl = LogicalKeyboardKey.controlLeft, shift = LogicalKeyboardKey.shiftLeft;
    await combo(t, [ctrl], LogicalKeyboardKey.keyZ);
    expect(ed.doc.strokes, isEmpty);
    await combo(t, [ctrl], LogicalKeyboardKey.keyY);
    expect(ed.doc.strokes.length, 1);
    await combo(t, [ctrl], LogicalKeyboardKey.keyZ);
    expect(ed.doc.strokes, isEmpty);
    await combo(t, [ctrl, shift], LogicalKeyboardKey.keyZ);
    expect(ed.doc.strokes.length, 1);

    await t.sendKeyEvent(LogicalKeyboardKey.keyS);
    await t.pump();
    expect(ed.ts.tool, Tool.select);
    await t.sendKeyEvent(LogicalKeyboardKey.keyH);
    await t.pump();
    expect(ed.ts.tool, Tool.hl);
    await t.sendKeyEvent(LogicalKeyboardKey.keyP);
    await t.pump();
    expect(ed.ts.tool, Tool.pen);
    await t.sendKeyEvent(LogicalKeyboardKey.keyT);
    await t.pump(const Duration(milliseconds: 600));
    expect(ed.ts.tool, Tool.text);
    expect(ed.textFocused, isTrue, reason: 'T abre un bloque con el teclado');

    // con un texto con foco, las letras son para escribir: no cambian de herramienta
    await t.sendKeyEvent(LogicalKeyboardKey.keyP);
    await t.pump();
    expect(ed.ts.tool, Tool.text);

    FocusManager.instance.primaryFocus?.unfocus();
    await t.pump();
    await combo(t, [ctrl], LogicalKeyboardKey.slash);
    await settle(t);
    expect(find.byKey(const Key('shortcutsDialog')), findsOneWidget);
    await t.tap(find.text('Cerrar'));
    await settle(t);
    expect(find.byKey(const Key('shortcutsDialog')), findsNothing);
  });

  testWidgets('el menú de tres puntitos tiene "Atajos de teclado"', (t) async {
    // la fuente de prueba es más ancha que la real: los menús "se pasan" de ancho solo acá
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.exceptionAsString().contains('overflowed')) prev?.call(d);
    };
    addTearDown(() => FlutterError.onError = prev);
    await openNotebook(t);
    await t.tap(find.byKey(const Key('more')));
    await settle(t);
    await t.tap(find.text('Atajos de teclado'));
    await settle(t);
    expect(find.byKey(const Key('shortcutsDialog')), findsOneWidget);
  });
}
