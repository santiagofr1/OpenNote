import 'dart:io';

import 'package:apuntes/app.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/sync/fake_backend.dart';
import 'package:apuntes/sync/fake_remote_store.dart';
import 'package:apuntes/sync/sync_engine.dart';
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

  testWidgets('indicador de estado en la biblioteca: aparece al conectar y abre la hoja de Sincronización', (t) async {
    final b = FakeBackend(FakeRemoteStore());
    await b.signIn();
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ApuntesApp(root: root, backend: b));
    await until(t, () => find.byKey(const Key('syncIndicator')).evaluate().isNotEmpty);
    expect(find.byKey(const Key('syncIndicator')), findsOneWidget);
    await until(t, () => find.byTooltip('Sincronizado').evaluate().isNotEmpty);
    await t.tap(find.byKey(const Key('syncIndicator')));
    await settle(t);
    expect(find.byKey(const Key('syncStatus')), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('cuaderno abierto: un cambio de otro dispositivo avisa y "Actualizar" lo baja', (t) async {
    final r = FakeRemoteStore();
    final b = FakeBackend(r);
    await b.signIn();
    final mine = Storage(root: root);
    final other = (await t.runAsync(() => Directory.systemTemp.createTemp('apuntes_sync_ui_otro')))!;
    addTearDown(() => other.delete(recursive: true));
    final s2 = Storage(root: other);
    // (archivos de verdad: dentro del reloj falso hace falta runAsync)
    await t.runAsync(() async {
      await mine.init();
      await SyncEngine(mine, r, account: b.account).sync();
      // el otro dispositivo baja el cuaderno, escribe algo y lo sube
      await s2.init();
      await SyncEngine(s2, r, account: 'otro').sync();
      final idx2 = await s2.loadIndex();
      final d2 = await s2.loadNotebook(idx2.notebooks.first);
      d2.texts['t'] = TextBlock('t', 90, 44, 800, 'escrito en la otra tablet');
      d2.markDirtyAt(44);
      await s2.saveNotebook(d2);
      await s2.saveIndex(idx2);
    });

    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ApuntesApp(root: root, backend: b, syncPoll: const Duration(milliseconds: 500), syncDebounce: const Duration(milliseconds: 200)));
    await until(t, () => find.byKey(const Key('nb-Uno')).evaluate().isNotEmpty);
    await settle(t, 800);
    await t.tap(find.byKey(const Key('nb-Uno')));
    await until(t, () => find.byKey(const Key('nbTitle')).evaluate().isNotEmpty);
    expect(find.byKey(const Key('syncIndicator')), findsWidgets, reason: 'también en el editor');
    // la otra tablet sube su cambio DESPUÉS de abrir: no se baja encima; aparece el aviso
    await t.runAsync(() => SyncEngine(s2, r, account: 'otro').sync());
    await until(t, () => find.byKey(const Key('remoteBanner')).evaluate().isNotEmpty);
    expect(find.text('Hay cambios de otro dispositivo'), findsOneWidget);
    final before = await t.runAsync(() async {
      final nbs = (await mine.loadIndex()).notebooks;
      return [for (final x in await mine.readSheetTexts(nbs.first, nbs.first.sheets[0])) x.text];
    });
    expect(before, isEmpty, reason: 'el cuaderno abierto no se tocó');
    await t.tap(find.byKey(const Key('remoteRefresh')));
    await until(t, () => find.byKey(const Key('remoteBanner')).evaluate().isEmpty && find.byKey(const Key('nbTitle')).evaluate().isNotEmpty);
    await settle(t, 800);
    expect(find.byKey(const Key('remoteBanner')), findsNothing);
    final after = await t.runAsync(() async {
      final nb2 = (await mine.loadIndex()).notebooks.first;
      return [for (final x in await mine.readSheetTexts(nb2, nb2.sheets[0])) x.text];
    });
    expect(after, ['escrito en la otra tablet']);
    expect(t.takeException(), isNull);
  });

  testWidgets('Cifrado: aparece con la sesión abierta y el diálogo de frase valida largo y coincidencia', (t) async {
    final r = FakeRemoteStore();
    await open(t, FakeBackend(r));
    expect(find.byKey(const Key('cryptoStatus')), findsNothing, reason: 'sin conectar no hay sección Cifrado');
    await t.tap(find.byKey(const Key('syncConnect')));
    await until(t, () => find.byKey(const Key('cryptoEnable')).evaluate().isNotEmpty);
    await until(t, () => find.byType(LinearProgressIndicator).evaluate().isEmpty);
    expect(find.text('Cifrado'), findsOneWidget);
    expect(find.textContaining('Si olvidás la frase'), findsOneWidget);
    await until(t, () => find.textContaining('Desactivado').evaluate().isNotEmpty);
    expect(find.byKey(const Key('cryptoStatus')), findsOneWidget);

    await t.tap(find.byKey(const Key('cryptoEnable')));
    await settle(t);
    expect(find.byKey(const Key('cryptoPass1')), findsOneWidget);
    expect(find.byKey(const Key('cryptoPass2')), findsOneWidget);
    // corta
    await t.enterText(find.byKey(const Key('cryptoPass1')), 'corta');
    await t.enterText(find.byKey(const Key('cryptoPass2')), 'corta');
    await t.tap(find.byKey(const Key('cryptoDialogOk')));
    await settle(t, 300);
    expect(find.byKey(const Key('cryptoDialogError')), findsOneWidget);
    expect(find.textContaining('al menos'), findsOneWidget);
    // no coinciden
    await t.enterText(find.byKey(const Key('cryptoPass1')), 'una frase larga');
    await t.enterText(find.byKey(const Key('cryptoPass2')), 'una frase larga distinta');
    await t.tap(find.byKey(const Key('cryptoDialogOk')));
    await settle(t, 300);
    expect(find.textContaining('no coinciden'), findsOneWidget);
    expect(find.byKey(const Key('cryptoPass1')), findsOneWidget, reason: 'el diálogo sigue abierto');
    expect(r.has('crypto.json'), isFalse);
    expect(t.takeException(), isNull);
  });
}
