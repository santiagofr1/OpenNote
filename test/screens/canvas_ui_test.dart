import 'dart:io';

import 'package:apuntes/app.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Crear un cuaderno de lienzo infinito desde la biblioteca: no tiene botón de hojas; el de hojas sí.
void main() {
  late Directory root;

  setUp(() async {
    Storage.useIsolates = false;
    root = await Directory.systemTemp.createTemp('apuntes_canvas_ui');
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

  Future<void> create(WidgetTester t, String name, {bool canvas = false}) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(() async {
      final s = Storage(root: root);
      await s.init();
      await s.saveIndex(NotesIndex());
    });
    await t.pumpWidget(ApuntesApp(root: root));
    await settle(t, 1200);
    await t.tap(find.byKey(const Key('new')));
    await settle(t);
    await t.tap(find.byKey(const Key('newNotebook')));
    await settle(t);
    await t.enterText(find.byKey(const Key('askText')), name);
    if (canvas) await t.tap(find.byKey(const Key('nbKindCanvas')));
    await t.pump();
    await t.tap(find.byKey(const Key('askOk')));
    await settle(t, 5000);
  }

  testWidgets('lienzo: sin botón de hojas ni contador', (t) async {
    await create(t, 'Mapa', canvas: true);
    expect(find.byKey(const Key('nbTitle')), findsOneWidget);
    expect(find.byKey(const Key('pagesBtn')), findsNothing);
    expect(find.byKey(const Key('sheetCounter')), findsNothing);
    expect(find.byKey(const Key('sectionsBtn')), findsOneWidget);
  });

  testWidgets('hojas (tipo por defecto): sigue el botón de hojas', (t) async {
    await create(t, 'Comun');
    expect(find.byKey(const Key('pagesBtn')), findsOneWidget);
    expect(find.byKey(const Key('sheetCounter')), findsOneWidget);
  });
}
