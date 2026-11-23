import 'dart:io';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// El borde difuminado de las mallas sigue al zoom (en píxeles de pantalla) y no cambia durante el pellizco.
void main() {
  late Directory root;
  final prev = meshFeather;
  setUp(() => root = Directory.systemTemp.createTempSync('apuntes_feather'));
  tearDown(() {
    meshFeather = prev;
    root.deleteSync(recursive: true);
  });

  testWidgets('se fija al abrir, no cambia durante el pellizco y se ajusta al soltar', (t) async {
    meshFeather = 0;
    t.view.physicalSize = const Size(1000, 1600);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    final tools = ToolState()
      ..tool = Tool.select
      ..zoom = 1;
    final doc = NotebookDoc(Notebook.create('T'));
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: PageEditor(doc: doc, tools: tools, store: Storage(root: root), onChanged: () {}, onPrefsChanged: () {})),
    ));
    addTearDown(() => t.pumpWidget(const SizedBox(), duration: const Duration(milliseconds: 1)));
    await t.pump(const Duration(milliseconds: 300));
    final ed = t.state<PageEditorState>(find.byType(PageEditor));

    final f0 = featherForPxPerUnit(ed.scale * 2);
    expect(f0, greaterThan(0));
    expect(meshFeather, f0, reason: 'al abrir');

    // pellizco: dos dedos que se separan hasta ~3x
    final a = await t.startGesture(const Offset(150, 400), kind: PointerDeviceKind.touch);
    final b = await t.startGesture(const Offset(220, 400), kind: PointerDeviceKind.touch);
    await t.pump();
    await b.moveTo(const Offset(400, 400));
    await t.pump();
    expect(ed.touch.pinching, isTrue);
    expect(tools.zoom, greaterThan(1.5));
    expect(meshFeather, f0, reason: 'durante el pellizco no cambia');
    await a.moveTo(const Offset(100, 400));
    await t.pump();
    expect(meshFeather, f0);
    await a.up();
    await b.up();
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));
    final f1 = featherForPxPerUnit(ed.scale * 2);
    expect(f1, lessThan(f0), reason: 'más zoom: borde más angosto en unidades de hoja');
    expect(meshFeather, f1, reason: 'al soltar');
  });
}
