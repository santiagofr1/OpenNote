import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/sync/fake_remote_store.dart';
import 'package:apuntes/sync/remote_store.dart';
import 'package:apuntes/sync/sync_engine.dart';
import 'package:apuntes/sync/sync_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// Dos "dispositivos" (dos Storage en carpetas temporales) contra el mismo remoto en memoria.
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
    final d = await Directory.systemTemp.createTemp('apuntes_sync');
    dirs.add(d);
    final s = Storage(root: d);
    await s.init();
    return s;
  }

  Future<SyncReport> sync(Storage s, FakeRemoteStore r, {Set<String> busy = const {}}) =>
      SyncEngine(s, r, busy: () => busy, account: 'a@b.c').sync();

  Future<NotesIndex> index(Storage s) async => NotesIndex.fromJson(jsonDecode(await s.syncFile('index.json').readAsString()) as Map);

  /// Cuaderno nuevo con [n] hojas; la hoja k tiene el texto "<name> k".
  Future<Notebook> create(Storage s, String name, {int n = 1}) async {
    final nb = Notebook.create(name);
    while (nb.sheets.length < n) {
      nb.sheets.add(nb.newSheet());
    }
    final d = NotebookDoc(nb);
    for (var k = 0; k < n; k++) {
      d.texts['t$k'] = TextBlock('t$k', 90, k * kSheetStep + 44, 800, '$name $k');
    }
    nb.touch();
    await s.saveNotebook(d);
    final idx = await s.indexFile.exists() ? await s.loadIndex() : NotesIndex();
    idx.notebooks.add(nb);
    await s.saveIndex(idx);
    return nb;
  }

  Future<Notebook> nbOf(Storage s, String id) async => (await s.loadIndex()).notebooks.firstWhere((n) => n.id == id);

  /// Cambia el texto de la hoja [k] y lo guarda (como haría el editor al cerrar).
  Future<void> edit(Storage s, String nbId, int k, String text) async {
    final idx = await s.loadIndex();
    final nb = idx.notebooks.firstWhere((n) => n.id == nbId);
    final d = await s.loadNotebook(nb);
    d.texts['t$k'] = TextBlock('t$k', 90, k * kSheetStep + 44, 800, text);
    d.markDirtyAt(k * kSheetStep + 44);
    nb.touch();
    await s.saveNotebook(d);
    await s.saveIndex(idx);
  }

  Future<List<String>> texts(Storage s, String nbId, int k) async {
    final nb = await nbOf(s, nbId);
    return [for (final t in await s.readSheetTexts(nb, nb.sheets[k])) t.text];
  }

  Future<Map<String, String>> snapshot(Storage s) async {
    final out = <String, String>{};
    for (final e in s.dir.listSync(recursive: true).whereType<File>()) {
      final rel = e.path.substring(s.dir.path.length + 1);
      if (rel.startsWith('notebooks/') || rel.startsWith('media/')) out[rel] = base64.encode(e.readAsBytesSync());
    }
    return out;
  }

  test('crear en A aparece en B, y una segunda pasada no sube ni baja nada', () async {
    final a = await device(), b = await device(), r = FakeRemoteStore();
    final nb = await create(a, 'Física', n: 3);
    final r1 = await sync(a, r);
    expect(r1.errors, isEmpty);
    expect(r.has('index.json'), isTrue);
    expect(r.has('notebooks/${nb.id}/notebook.json'), isTrue);
    expect(r.paths.where((p) => p.endsWith('.sheet')), hasLength(3));

    await sync(b, r);
    final idx = await index(b);
    expect(idx.notebooks.single.name, 'Física');
    final nbB = await nbOf(b, nb.id);
    expect(nbB.sheets.map((m) => m.id), nb.sheets.map((m) => m.id));
    expect(await texts(b, nb.id, 2), ['Física 2']);

    // nada cambió: ni una subida ni una bajada
    r.clearCounters();
    for (final s in [a, b, a]) {
      final rep = await sync(s, r);
      expect(rep.nothingToDo, isTrue, reason: rep.toString());
    }
    expect(r.uploads, 0);
    expect(r.downloads, 0);
    expect(r.deletes, 0);
  });

  test('editar en B baja a A, y solo se sube la hoja que cambió', () async {
    final a = await device(), b = await device(), r = FakeRemoteStore();
    final nb = await create(a, 'Mate', n: 3);
    await sync(a, r);
    await sync(b, r);
    await edit(b, nb.id, 1, 'cambiada en B');
    r.clearCounters();
    await sync(b, r);
    expect(r.uploaded.where((p) => p.endsWith('.sheet')), [contains(nb.sheets[1].id)]);
    await sync(a, r);
    expect(await texts(a, nb.id, 1), ['cambiada en B']);
    expect(await texts(a, nb.id, 0), ['Mate 0']);
    expect((await nbOf(a, nb.id)).sheets[1].rev, greaterThan(0));
  });

  test('la misma hoja editada en los dos lados: quedan las dos versiones (hoja "(conflicto)") en los dos', () async {
    final a = await device(), b = await device(), r = FakeRemoteStore();
    final nb = await create(a, 'Quimica', n: 2);
    await sync(a, r);
    await sync(b, r);
    await edit(a, nb.id, 0, 'version A');
    await edit(b, nb.id, 0, 'version B');
    await sync(b, r); // B llega primero
    final repA = await sync(a, r); // A ve el conflicto: se queda con la suya
    expect(repA.conflicts, 1);
    await sync(b, r);
    await sync(a, r);

    for (final s in [a, b]) {
      final n = await nbOf(s, nb.id);
      expect(n.sheets, hasLength(3), reason: 'la original, la de conflicto y la segunda');
      expect(n.sheets[0].id, nb.sheets[0].id);
      expect(n.sheets[1].title, '(conflicto)');
      expect(n.sheets[2].id, nb.sheets[1].id);
      expect(await texts(s, nb.id, 0), ['version A']);
      expect(await texts(s, nb.id, 1), ['version B']);
      expect(await texts(s, nb.id, 2), ['Quimica 1']);
    }
    expect(await snapshot(a), await snapshot(b));
    // y se estabiliza: nada más para subir ni bajar
    r.clearCounters();
    await sync(a, r);
    await sync(b, r);
    expect(r.uploads, 0);
    expect(r.downloads, 0);
  });

  test('borrar un cuaderno en A lo borra en B; borrar una hoja también', () async {
    final a = await device(), b = await device(), r = FakeRemoteStore();
    final keep = await create(a, 'Queda', n: 3);
    final gone = await create(a, 'Se va');
    await sync(a, r);
    await sync(b, r);
    expect(await b.nbDir(gone.id).exists(), isTrue);

    // A borra el cuaderno entero y una hoja del otro
    final idx = await a.loadIndex();
    await a.deleteNotebook(idx, idx.notebooks.firstWhere((n) => n.id == gone.id));
    final nbA = idx.notebooks.firstWhere((n) => n.id == keep.id);
    final d = await a.loadNotebook(nbA);
    final removed = nbA.sheets[1].id;
    d.deleteSheet(1);
    await a.saveNotebook(d);
    await a.saveIndex(idx);
    await sync(a, r);
    expect(r.paths.any((p) => p.contains(gone.id)), isFalse);
    expect(r.has('notebooks/${keep.id}/sheets/$removed.sheet'), isFalse);

    await sync(b, r);
    expect((await index(b)).notebooks.map((n) => n.id), [keep.id]);
    expect(await b.nbDir(gone.id).exists(), isFalse);
    expect((await nbOf(b, keep.id)).sheets, hasLength(2));
    expect(b.sheetFile(keep.id, removed).existsSync(), isFalse);
    expect(await snapshot(a), await snapshot(b));
  });

  test('editar una hoja que el otro lado borró: gana la edición', () async {
    final a = await device(), b = await device(), r = FakeRemoteStore();
    final nb = await create(a, 'Disputa', n: 2);
    await sync(a, r);
    await sync(b, r);
    final sid = nb.sheets[1].id;
    // A borra la hoja 1; B la edita
    final idx = await a.loadIndex();
    final d = await a.loadNotebook(idx.notebooks.single);
    d.deleteSheet(1);
    await a.saveNotebook(d);
    await edit(b, nb.id, 1, 'editada en B');
    await sync(a, r);
    await sync(b, r);
    await sync(a, r);
    for (final s in [a, b]) {
      expect((await nbOf(s, nb.id)).sheets.map((m) => m.id), contains(sid));
      expect(await texts(s, nb.id, 1), ['editada en B']);
    }
  });

  group('cortes a mitad de una pasada', () {
    // se corta la red después de [n] operaciones; la próxima pasada tiene que converger sin duplicar ni perder
    for (var n = 0; n <= 14; n++) {
      test('subiendo desde A, corte tras $n operaciones', () async {
        final a = await device(), b = await device(), r = FakeRemoteStore();
        final nb = await create(a, 'Corte', n: 4);
        r.failAfter = n;
        try {
          await sync(a, r);
        } on RemoteOfflineException {
          // esperado
        }
        r.failAfter = null;
        final rep = await sync(a, r);
        expect(rep.errors, isEmpty);
        expect(r.paths.where((p) => p.endsWith('.sheet')), hasLength(4));
        await sync(b, r);
        expect(await snapshot(b), await snapshot(a));
        expect((await index(b)).notebooks.single.id, nb.id);
      });

      test('bajando en B, corte tras $n operaciones', () async {
        final a = await device(), b = await device(), r = FakeRemoteStore();
        final nb = await create(a, 'Corte', n: 4);
        await sync(a, r);
        // B tiene algo propio, para que haya de las dos cosas
        final mine = await create(b, 'Mio', n: 2);
        r.resetOps();
        r.failAfter = n;
        try {
          await sync(b, r);
        } on RemoteOfflineException {
          // esperado
        }
        r.failAfter = null;
        final rep = await sync(b, r);
        expect(rep.errors, isEmpty);
        await sync(a, r);
        await sync(b, r);
        expect(await snapshot(b), await snapshot(a));
        expect((await index(a)).notebooks.map((x) => x.id).toSet(), {nb.id, mine.id});
        expect((await index(b)).notebooks.map((x) => x.id).toSet(), {nb.id, mine.id});
        expect(r.paths.where((p) => p.endsWith('.sheet')), hasLength(6));
      });
    }
  });

  test('un cuaderno abierto en el editor (busy) no se toca; al cerrarlo se sincroniza (y se conservan las dos versiones)', () async {
    final a = await device(), b = await device(), r = FakeRemoteStore();
    final nb = await create(a, 'Abierto', n: 2);
    final other = await create(a, 'Otro');
    await sync(a, r);
    await sync(b, r);
    // A tiene abierto 'Abierto' y guarda su edición en disco; B edita lo mismo y sube
    await edit(a, nb.id, 0, 'version A');
    await edit(b, nb.id, 0, 'version B');
    await edit(b, other.id, 0, 'otro editado en B');
    await sync(b, r);
    final before = await snapshot(a);
    final idxBefore = await a.syncFile('index.json').readAsString();

    final rep = await sync(a, r, busy: {nb.id});
    expect(rep.skippedBusy, [nb.id]);
    final after = await snapshot(a);
    for (final e in before.entries.where((e) => e.key.startsWith('notebooks/${nb.id}/'))) {
      expect(after[e.key], e.value, reason: '${e.key}: el cuaderno abierto no se toca');
    }
    expect(await a.syncFile('index.json').readAsString(), idxBefore, reason: 'con un cuaderno abierto tampoco se toca el índice');
    expect(rep.indexChanged, isFalse);
    expect(await texts(a, other.id, 0), ['otro editado en B'], reason: 'los otros cuadernos sí se sincronizan');

    // lo cierra: se resuelve sin perder ninguna de las dos versiones
    await sync(a, r);
    await sync(b, r);
    await sync(a, r);
    for (final s in [a, b]) {
      expect(await texts(s, nb.id, 0), ['version A']);
      expect(await texts(s, nb.id, 1), ['version B']);
    }
  });

  test('la media se copia al otro lado (solo se agrega)', () async {
    final a = await device(), b = await device(), r = FakeRemoteStore();
    await create(a, 'Con foto');
    final name = await a.addMedia([1, 2, 3, 4], 'png');
    await sync(a, r);
    expect(r.has('media/$name'), isTrue);
    await sync(b, r);
    expect(b.media(name).readAsBytesSync(), [1, 2, 3, 4]);
    r.clearCounters();
    await sync(b, r);
    await sync(a, r);
    expect(r.uploads + r.downloads, 0);
  });

  test('si la nube aparece vacía no se borra nada de acá: se vuelve a subir', () async {
    final a = await device(), r = FakeRemoteStore();
    final nb = await create(a, 'Importante', n: 2);
    await sync(a, r);
    final before = await snapshot(a);
    r.wipe(); // carpeta borrada en la nube
    final rep = await sync(a, r);
    expect(rep.deletedLocal, 0);
    expect(await snapshot(a), before);
    expect(r.has('notebooks/${nb.id}/notebook.json'), isTrue);
    expect(r.paths.where((p) => p.endsWith('.sheet')), hasLength(2));
  });

  test('índices: renombrar en A y crear una carpeta en B se fusionan; cada uno conserva su "última hoja vista"', () async {
    final a = await device(), b = await device(), r = FakeRemoteStore();
    final nb = await create(a, 'Original', n: 2);
    await sync(a, r);
    await sync(b, r);
    final ia = await a.loadIndex();
    ia.notebooks.single
      ..name = 'Renombrado'
      ..touch();
    await a.saveIndex(ia);
    final ib = await b.loadIndex();
    ib.folders.add(Folder.create('Facultad'));
    ib.notebooks.single.last = 1; // dato propio de B: no se sincroniza
    await b.saveIndex(ib);
    await sync(a, r);
    await sync(b, r);
    await sync(a, r);
    for (final s in [a, b]) {
      final i = await index(s);
      expect(i.notebooks.single.name, 'Renombrado');
      expect(i.folders.map((f) => f.name), ['Facultad']);
    }
    expect((await index(b)).notebooks.single.last, 1);
    expect((await index(a)).notebooks.single.last, 0);
    expect(nb.id, (await index(a)).notebooks.single.id);
  });

  test('sin red: la pasada falla con RemoteOfflineException y los datos locales no cambian', () async {
    final a = await device(), r = FakeRemoteStore();
    await create(a, 'Sin red', n: 2);
    final before = await snapshot(a);
    r.offline = true;
    await expectLater(sync(a, r), throwsA(isA<RemoteOfflineException>()));
    expect(await snapshot(a), before);
    final st = await SyncState.load(a);
    expect(st.lastError, isNotNull);
    r.offline = false;
    await sync(a, r);
    expect((await SyncState.load(a)).lastError, isNull);
  });

  test('cambiar de cuenta empieza de cero (no borra nada acá)', () async {
    final a = await device(), r = FakeRemoteStore(), r2 = FakeRemoteStore();
    await create(a, 'Mio', n: 1);
    await SyncEngine(a, r, account: 'uno@x.com').sync();
    final rep = await SyncEngine(a, r2, account: 'otro@x.com').sync();
    expect(rep.deletedLocal, 0);
    expect(r2.paths.where((p) => p.endsWith('.sheet')), hasLength(1));
  });

  test('una ruta rara que viene de la nube se ignora', () async {
    final a = await device(), r = FakeRemoteStore();
    await create(a, 'Mio', n: 1);
    r.put('../../etc/passwd', Uint8List.fromList([1]));
    r.put('notebooks/../x.sheet', Uint8List.fromList([1]));
    r.put('prefs.json', Uint8List.fromList([1]));
    final rep = await sync(a, r);
    expect(rep.errors, isEmpty);
    expect(File('${a.dir.path}/x.sheet').existsSync(), isFalse);
    expect(File('${a.dir.path}/prefs.json').existsSync(), isFalse);
  });
}
