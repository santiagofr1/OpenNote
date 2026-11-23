import 'dart:convert';
import 'dart:io';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/sync/fake_remote_store.dart';
import 'package:apuntes/sync/sync_engine.dart';
import 'package:apuntes/sync/sync_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// El índice no se queda trabado si la biblioteca lo guarda mientras se está subiendo.
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
    final d = await Directory.systemTemp.createTemp('apuntes_trabado');
    dirs.add(d);
    final s = Storage(root: d);
    await s.init();
    return s;
  }

  Future<void> sync(Storage s, FakeRemoteStore r) async {
    final rep = await SyncEngine(s, r, busy: () => const {}, account: 'a@b.c').sync();
    expect(rep.errors, isEmpty, reason: rep.toString());
  }

  Future<Notebook> create(Storage s, String name) async {
    final nb = Notebook.create(name);
    final d = NotebookDoc(nb);
    d.texts['t0'] = TextBlock('t0', 90, 44, 800, name);
    nb.touch();
    await s.saveNotebook(d);
    final idx = await s.indexFile.exists() ? await s.loadIndex() : NotesIndex();
    idx.notebooks.add(nb);
    await s.saveIndex(idx);
    return nb;
  }

  Future<void> borrar(Storage s, String id) async {
    final idx = await s.loadIndex();
    await s.deleteNotebook(idx, idx.notebooks.firstWhere((n) => n.id == id));
  }

  List<String> idsEnNube(FakeRemoteStore r) =>
      [for (final n in (jsonDecode(utf8.decode(r.bytesOf('index.json')!)) as Map)['notebooks'] as List) (n as Map)['id'] as String];

  /// Hace que la primera subida de index.json corra [alSubir] antes de completarse.
  void alSubirIndice(FakeRemoteStore r, Future<void> Function() alSubir) {
    var hecho = false;
    r.onUpload = (p) async {
      if (p != 'index.json' || hecho) return;
      hecho = true;
      await alSubir();
    };
  }

  test('la biblioteca guarda el índice durante la subida: la próxima pasada sube el cambio', () async {
    final r = FakeRemoteStore();
    final a = await device();
    final x = await create(a, 'X');
    final y = await create(a, 'Y');
    await sync(a, r);
    expect(idsEnNube(r), unorderedEquals([x.id, y.id]));

    // Cambio local para que se suba el índice, y mientras sube la biblioteca lo guarda de nuevo sin Y.
    final idx = await a.loadIndex();
    idx.notebooks.firstWhere((n) => n.id == x.id).name = 'X2';
    await a.saveIndex(idx);
    alSubirIndice(r, () async {
      final i = await a.loadIndex();
      i.notebooks.removeWhere((n) => n.id == y.id);
      await a.saveIndex(i);
    });
    await sync(a, r);
    r.onUpload = null;
    await sync(a, r);

    expect(idsEnNube(r), [x.id]);
  });

  test('estado ya trabado: base con el hash viejo y el tamaño/fecha del archivo actual', () async {
    final r = FakeRemoteStore();
    final a = await device();
    final x = await create(a, 'X');
    final y = await create(a, 'Y');
    await sync(a, r);

    await borrar(a, y.id);
    final st = await SyncState.load(a);
    final viejo = st.base['index.json']!;
    final s = await a.syncFile('index.json').stat();
    expect(s.size == viejo.size && s.modified.millisecondsSinceEpoch == viejo.mtime, isFalse);
    st.base['index.json'] = FileBase(viejo.md5, s.size, s.modified.millisecondsSinceEpoch);
    await st.save(a);

    await sync(a, r);
    expect(idsEnNube(r), [x.id]);
  });

  test('dos dispositivos: A borra un cuaderno durante la subida del índice, B termina sin el cuaderno', () async {
    final r = FakeRemoteStore();
    final a = await device(), b = await device();
    final x = await create(a, 'X');
    final y = await create(a, 'Y');
    await sync(a, r);
    await sync(b, r);
    expect((await b.loadIndex()).notebooks.length, 2);

    // Un cambio cualquiera en el índice de A (renombrar X) dispara la subida; durante ella se borra Y.
    final idx = await a.loadIndex();
    idx.notebooks.firstWhere((n) => n.id == x.id).name = 'X2';
    await a.saveIndex(idx);
    alSubirIndice(r, () => borrar(a, y.id));
    await sync(a, r);
    r.onUpload = null;
    await sync(a, r);
    await sync(b, r);

    expect(idsEnNube(r), [x.id]);
    expect((await b.loadIndex()).notebooks.map((n) => n.id), [x.id]);
    expect(b.nbDir(y.id).existsSync(), isFalse);
    expect(r.paths.where((p) => p.contains(y.id)), isEmpty);
    expect(Directory('${b.dir.path}/${y.id}').existsSync(), isFalse);
  });
}
