import 'dart:io';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/sync/background_sync.dart';
import 'package:apuntes/sync/fake_backend.dart';
import 'package:apuntes/sync/fake_remote_store.dart';
import 'package:apuntes/sync/sync_controller.dart';
import 'package:apuntes/sync/sync_engine.dart';
import 'package:apuntes/sync/sync_lock.dart';
import 'package:flutter_test/flutter_test.dart';

/// El candado entre la app y la tarea de fondo, y la lógica de la pasada de fondo (sin WorkManager).
void main() {
  setUpAll(() => Storage.useIsolates = false);
  tearDownAll(() => Storage.useIsolates = true);

  final dirs = <Directory>[];
  tearDown(() {
    for (final d in dirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    dirs.clear();
  });

  Future<Storage> device() async {
    final d = await Directory.systemTemp.createTemp('apuntes_bg');
    dirs.add(d);
    final s = Storage(root: d);
    await s.init();
    return s;
  }

  Future<void> create(Storage s, String name) async {
    final nb = Notebook.create(name);
    nb.touch();
    await s.saveNotebook(NotebookDoc(nb));
    final idx = await s.indexFile.exists() ? await s.loadIndex() : NotesIndex();
    idx.notebooks.add(nb);
    await s.saveIndex(idx);
  }

  group('SyncLock', () {
    test('toma, rechaza si está tomado y se puede tomar de nuevo al soltarlo', () async {
      final s = await device();
      final a = SyncLock(s.dir, owner: 'app'), b = SyncLock(s.dir, owner: 'fondo');
      expect(await a.tryAcquire(), isTrue);
      expect(a.held, isTrue);
      expect(await b.tryAcquire(), isFalse);
      await a.release();
      expect(a.held, isFalse);
      expect(await b.tryAcquire(), isTrue);
      await b.release();
    });

    test('vencido: un candado viejo no bloquea para siempre', () async {
      final s = await device();
      var t = DateTime(2026, 11, 21, 10);
      final a = SyncLock(s.dir, now: () => t), b = SyncLock(s.dir, now: () => t);
      expect(await a.tryAcquire(), isTrue);
      t = t.add(const Duration(minutes: 9));
      expect(await b.tryAcquire(), isFalse, reason: 'a los 9 min sigue vigente');
      t = t.add(const Duration(minutes: 2));
      expect(await b.tryAcquire(), isTrue, reason: 'a los 11 min venció');
      await a.release(); // el viejo ya no es el dueño: no tiene que borrar el candado del nuevo
      expect(await SyncLock(s.dir, now: () => t).tryAcquire(), isFalse);
      await b.release();
    });

    test('un archivo roto se trata como candado abandonado cuando es viejo', () async {
      final s = await device();
      final f = File('${s.dir.path}/sync.lock')..writeAsStringSync('basura');
      final fresh = SyncLock(s.dir);
      expect(await fresh.tryAcquire(), isFalse, reason: 'recién creado: puede estar escribiéndose');
      f.setLastModifiedSync(DateTime.now().subtract(const Duration(minutes: 20)));
      expect(await fresh.tryAcquire(), isTrue);
    });
  });

  group('runBackgroundPass', () {
    test('sincroniza: sube lo local y baja lo de la nube dejando la marca para la app', () async {
      final remote = FakeRemoteStore();
      final other = await device();
      await create(other, 'Desde la tablet');
      await SyncEngine(other, remote, account: 'prueba@opennote.test').sync();

      final s = await device();
      await create(s, 'Local');
      final backend = FakeBackend(remote);
      await backend.signIn();
      final r = await runBackgroundPass(s, backend);
      expect(r.outcome, BackgroundOutcome.synced);
      expect(r.report!.uploaded, greaterThan(0));
      expect((await s.loadIndex()).notebooks.map((n) => n.name), containsAll(['Local', 'Desde la tablet']));
      expect(await SyncMarks(s.dir).takeBackgroundChanged(), isTrue, reason: 'bajó cambios: la app tiene que releer');
      expect(await SyncMarks(s.dir).takeBackgroundChanged(), isFalse, reason: 'la marca se consume');
      expect(File('${s.dir.path}/sync.lock').existsSync(), isFalse, reason: 'suelta el candado al terminar');
    });

    test('respeta el candado: si la app (u otra pasada) lo tiene, no hace nada', () async {
      final remote = FakeRemoteStore();
      final s = await device();
      await create(s, 'Local');
      final backend = FakeBackend(remote);
      await backend.signIn();
      final app = SyncLock(s.dir);
      expect(await app.tryAcquire(), isTrue);
      final r = await runBackgroundPass(s, backend);
      expect(r.outcome, BackgroundOutcome.locked);
      expect(remote.paths, isEmpty);
      await app.release();
      expect((await runBackgroundPass(s, backend)).outcome, BackgroundOutcome.synced);
      expect(remote.has('index.json'), isTrue);
    });

    test('con un candado vencido sigue adelante', () async {
      final remote = FakeRemoteStore();
      final s = await device();
      await create(s, 'Local');
      final backend = FakeBackend(remote);
      await backend.signIn();
      var t = DateTime.now();
      await SyncLock(s.dir, now: () => t).tryAcquire(); // lo toma "alguien" que nunca lo suelta
      t = t.add(const Duration(minutes: 30));
      final r = await runBackgroundPass(s, backend, now: () => t);
      expect(r.outcome, BackgroundOutcome.synced);
    });

    test('si la app está en primer plano no hace nada', () async {
      final remote = FakeRemoteStore();
      final s = await device();
      await create(s, 'Local');
      final backend = FakeBackend(remote);
      await backend.signIn();
      final marks = SyncMarks(s.dir);
      await marks.beatForeground();
      expect((await runBackgroundPass(s, backend)).outcome, BackgroundOutcome.appInForeground);
      expect(remote.paths, isEmpty);
      await marks.clearForeground();
      expect((await runBackgroundPass(s, backend)).outcome, BackgroundOutcome.synced);
    });

    test('una marca de primer plano vieja (la app murió) no bloquea', () async {
      final s = await device();
      var t = DateTime(2026, 11, 21, 10);
      final marks = SyncMarks(s.dir, now: () => t);
      await marks.beatForeground();
      expect(await marks.foregroundFresh(), isTrue);
      t = t.add(const Duration(minutes: 5));
      expect(await marks.foregroundFresh(), isFalse);
    });

    test('sin sesión (hay que volver a conectar a mano) termina sin error y sin tocar nada', () async {
      final remote = FakeRemoteStore();
      final s = await device();
      await create(s, 'Local');
      final r = await runBackgroundPass(s, FakeBackend(remote)); // nunca se conectó: restore() da null
      expect(r.outcome, BackgroundOutcome.noSession);
      expect(remote.paths, isEmpty);
      expect(File('${s.dir.path}/sync.lock').existsSync(), isFalse);
    });

    test('con el interruptor apagado o sin configurar no hace nada', () async {
      final remote = FakeRemoteStore();
      final s = await device();
      await create(s, 'Local');
      final backend = FakeBackend(remote);
      await backend.signIn();
      await s.savePrefs({kBgSyncPref: false});
      expect((await runBackgroundPass(s, backend)).outcome, BackgroundOutcome.disabled);
      await s.savePrefs({kBgSyncPref: true});
      expect((await runBackgroundPass(s, FakeBackend(remote, configured: false))).outcome, BackgroundOutcome.notConfigured);
      expect(remote.paths, isEmpty);
    });

    test('un cuaderno que quedó abierto en el editor no se pisa: solo se le sube', () async {
      final remote = FakeRemoteStore();
      final a = await device();
      await create(a, 'Compartido');
      await SyncEngine(a, remote, account: 'prueba@opennote.test').sync();
      final b = await device();
      await SyncEngine(b, remote, account: 'prueba@opennote.test').sync();
      final id = (await b.loadIndex()).notebooks.single.id;

      // la nube cambia el cuaderno; en b está "abierto" (la app pasó a segundo plano con él en el editor)
      final nbA = (await a.loadIndex()).notebooks.single;
      final docA = await a.openNotebook(nbA);
      docA.texts['x'] = TextBlock('x', 90, 44, 800, 'cambio de la nube');
      nbA.touch();
      await a.saveNotebook(docA);
      await SyncEngine(a, remote, account: 'prueba@opennote.test').sync();

      await SyncMarks(b.dir).writeBusy({id});
      final backend = FakeBackend(remote);
      await backend.signIn();
      final before = File('${b.dir.path}/notebooks/$id/notebook.json').readAsStringSync();
      final r = await runBackgroundPass(b, backend);
      expect(r.outcome, BackgroundOutcome.synced);
      expect(r.report!.remoteWaiting, contains(id));
      expect(File('${b.dir.path}/notebooks/$id/notebook.json').readAsStringSync(), before);
    });
  });

  test('SyncController: con el candado tomado por la tarea de fondo espera y reintenta; la marca de la tarea relee el disco', () async {
    final s = await device();
    final backend = FakeBackend(FakeRemoteStore());
    var passes = 0, reloads = 0;
    final c = SyncController(store: s, backend: backend, lockRetry: const Duration(milliseconds: 80))
      ..lock = SyncLock(s.dir)
      ..marks = SyncMarks(s.dir)
      ..onBackgroundChanged = (() => reloads++)
      ..passOverride = ((_) async {
        passes++;
        return SyncReport();
      });
    addTearDown(c.dispose);
    final bg = SyncLock(s.dir, owner: 'fondo');
    expect(await bg.tryAcquire(), isTrue);
    await c.connect();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(passes, 0, reason: 'la de fondo tiene el candado: la app no corre');
    await SyncMarks(s.dir).markBackgroundChanged();
    await bg.release();
    for (var i = 0; i < 40 && passes == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    await c.whenIdle();
    expect(passes, 1);
    expect(reloads, 1, reason: 'la tarea de fondo bajó cambios: se relee');
    expect(File('${s.dir.path}/sync.lock').existsSync(), isFalse, reason: 'la pasada de la app suelta el candado');
  });
}
