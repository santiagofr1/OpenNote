import 'dart:io';

import 'package:apuntes/app.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/sync/fake_backend.dart';
import 'package:apuntes/sync/fake_remote_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Menú ⋮ de la biblioteca → "Sincronización con Google Drive".
void main() {
  late Directory root;
  setUp(() async {
    Storage.useIsolates = false;
    root = await Directory.systemTemp.createTemp('apuntes_sync_ui');
    final nb = Notebook.create('Uno');
    nb.sheets.add(nb.newSheet());
    final s = Storage(root: root);
    await s.init();
    await s.saveNotebook(NotebookDoc(nb));
    await s.saveIndex(NotesIndex(notebooks: [nb]));
  });
  tearDown(() async {
    Storage.useIsolates = true;
    await root.delete(recursive: true);
  });

  Future<void> settle(WidgetTester t, [int ms = 600]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  /// Espera (con tiempo real: hay archivos de por medio) a que se cumpla [cond].
  Future<void> until(WidgetTester t, bool Function() cond) async {
    for (var i = 0; i < 600 && !cond(); i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await t.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> open(WidgetTester t, FakeBackend? b) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ApuntesApp(root: root, backend: b));
    for (var i = 0; i < 50 && find.byKey(const Key('nb-Uno')).evaluate().isEmpty; i++) {
      await settle(t, 100);
    }
    await settle(t, 500);
    await t.tap(find.byKey(const Key('libraryMenu')));
    await settle(t);
    await t.tap(find.byKey(const Key('syncMenu')));
    await settle(t);
  }

  testWidgets('sin configurar: avisa qué falta y no hay botones de conexión', (t) async {
    await open(t, FakeBackend(FakeRemoteStore(), configured: false));
    expect(find.textContaining('falta'), findsOneWidget);
    expect(find.byKey(const Key('syncConnect')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('sin pasar backend (Google sin datos del proyecto): mensaje claro y sin crash', (t) async {
    await open(t, null);
    expect(find.byKey(const Key('syncStatus')), findsOneWidget);
    expect(find.byKey(const Key('syncConnect')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('conectar, sincronizar ahora sube el cuaderno y desconectar vuelve al inicio', (t) async {
    final r = FakeRemoteStore();
    await open(t, FakeBackend(r));
    await t.tap(find.byKey(const Key('syncConnect')));
    await until(t, () => r.has('index.json') && find.byKey(const Key('syncNow')).evaluate().isNotEmpty);
    expect(r.has('index.json'), isTrue);
    await until(t, () => find.byType(LinearProgressIndicator).evaluate().isEmpty);
    await t.tap(find.byKey(const Key('syncNow')));
    await settle(t, 600);
    await until(t, () => find.byType(LinearProgressIndicator).evaluate().isEmpty);
    await t.tap(find.byKey(const Key('syncDisconnect')));
    await until(t, () => find.byKey(const Key('syncConnect')).evaluate().isNotEmpty);
    expect(find.byKey(const Key('syncConnect')), findsOneWidget);
    expect(File('${root.path}/sync_state.json').existsSync(), isFalse);
  });
}
