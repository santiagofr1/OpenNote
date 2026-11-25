import 'dart:io';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:apuntes/l10n/l10n.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Con el zoom fijado la hoja se mueve con dos dedos: tirar con dos dedos más allá del final y mantener agrega una hoja
/// (igual que con un dedo sin el zoom fijado).
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('apuntes_pull_locked'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<PageEditorState> open(WidgetTester t, {required bool locked}) async {
    t.view.physicalSize = const Size(2000, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final doc = NotebookDoc(Notebook.create('T'));
    final store = Storage(root: root);
    await t.runAsync(store.init);
    final tools = ToolState()
      ..tool = Tool.pen
      ..zoomLocked = locked;
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      locale: const Locale('es'),
      
      home: Scaffold(body: PageEditor(doc: doc, tools: tools, store: store, onChanged: () {}, onPrefsChanged: () {})),
    ));
    await t.pump(const Duration(milliseconds: 300));
    final ed = t.state<PageEditorState>(find.byType(PageEditor));
    ed.scroll.jumpTo(ed.scroll.position.maxScrollExtent); // al final
    await t.pump();
    return ed;
  }

  // dos dedos que suben [dy] px y se quedan ~1 s
  Future<void> twoFingerPull(WidgetTester t, double dy, {bool release = true}) async {
    const a = Offset(900, 900), b = Offset(1100, 900);
    final g1 = await t.startGesture(a, kind: PointerDeviceKind.touch, pointer: 1);
    await t.pump(const Duration(milliseconds: 16));
    final g2 = await t.startGesture(b, kind: PointerDeviceKind.touch, pointer: 2);
    await t.pump(const Duration(milliseconds: 16));
    for (var i = 1; i <= 10; i++) {
      await g1.moveTo(a - Offset(0, dy * i / 10));
      await g2.moveTo(b - Offset(0, dy * i / 10));
      await t.pump(const Duration(milliseconds: 16));
    }
    for (var i = 0; i < 70; i++) {
      await t.pump(const Duration(milliseconds: 16));
    }
    await g1.up();
    await g2.up();
    await t.pump(const Duration(milliseconds: 1000));
  }

  testWidgets('con el zoom fijado, dos dedos tirando más allá del final agregan una hoja', (t) async {
    final ed = await open(t, locked: true);
    expect(ed.doc.sheetCount, 1);
    await twoFingerPull(t, 300);
    expect(ed.doc.sheetCount, 2);
  });

  testWidgets('con el zoom fijado, dos dedos que no pasan el final no agregan nada', (t) async {
    final ed = await open(t, locked: true);
    ed.scroll.jumpTo(0);
    await t.pump();
    await twoFingerPull(t, 100);
    expect(ed.doc.sheetCount, 1);
  });
}
