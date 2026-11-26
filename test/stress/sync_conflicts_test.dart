import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:apuntes/data/sheet_codec.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/sync/fake_remote_store.dart';
import 'package:apuntes/sync/remote_store.dart';
import 'package:apuntes/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stress.dart';

/// Sincronización con dos dispositivos contra un remoto en memoria, a la mala: ediciones concurrentes de las mismas hojas,
/// cortes de red en cualquier punto, archivos rotos en la nube, JSON de la nube con forma rara.
/// Invariantes: (1) lo escrito en CUALQUIER dispositivo no se pierde (conflicto = se conservan las dos versiones);
/// (2) después de sincronizar hasta que no haya nada que hacer, los dos dispositivos tienen los mismos archivos;
/// (3) un archivo malo de la nube no toca lo local ni impide sincronizar el resto.
void main() {
  setUpAll(() => Storage.useIsolates = false);
  tearDownAll(() => Storage.useIsolates = true);

  final dirs = <Directory>[];
  tearDown(() async {
    await Storage.settleWrites();
    for (final d in dirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    dirs.clear();
  });

  Future<Storage> device() async {
    final d = await Directory.systemTemp.createTemp('apuntes_sync_stress');
    dirs.add(d);
    final s = Storage(root: d);
    await s.init();
    return s;
  }

  Future<SyncReport> sync(Storage s, FakeRemoteStore r, {Set<String> busy = const {}}) =>
      SyncEngine(s, r, busy: () => busy, account: 'a@b.c').sync();

  /// Cuaderno nuevo de [n] hojas con el texto "base k" (id t0..) en cada una.
  Future<Notebook> create(Storage s, String name, {int n = 1}) async {
    final nb = Notebook.create(name);
    while (nb.sheets.length < n) {
      nb.sheets.add(nb.newSheet());
    }
    final d = NotebookDoc(nb);
    for (var k = 0; k < n; k++) {
      d.texts['t$k'] = TextBlock('t$k', 90, k * kSheetStep + 44, 800, 'base $k');
    }
    nb.touch();
    await s.saveNotebook(d);
    final idx = await s.indexFile.exists() ? await s.loadIndex() : NotesIndex();
    idx.notebooks.add(nb);
    await s.saveIndex(idx);
    return nb;
  }

  /// Como el editor: abre el cuaderno, agrega un texto NUEVO a la hoja [k] y guarda.
  Future<void> addText(Storage s, String nbId, int k, String id, String text) async {
    final idx = await s.loadIndex();
    final nb = idx.notebooks.firstWhere((n) => n.id == nbId);
    final d = await s.loadNotebook(nb);
    d.texts[id] = TextBlock(id, 90, k * kSheetStep + 120, 800, text);
    nb.touch();
    await s.saveNotebook(d);
    await s.saveIndex(idx);
  }

  Future<List<String>> allTexts(Storage s) async {
    final idx = await s.loadIndex();
    return [
      for (final nb in idx.notebooks)
        for (final m in nb.allSheets) ...[for (final t in await s.readSheetTexts(nb, m)) t.text]
    ];
  }

  /// Todos los archivos de cuadernos y media (lo que se sincroniza, menos el índice, que tiene datos propios de cada lado).
  Map<String, String> files(Storage s) => {
        for (final e in s.dir.listSync(recursive: true).whereType<File>())
          if (e.path.substring(s.dir.path.length + 1).startsWith('notebooks/') || e.path.substring(s.dir.path.length + 1).startsWith('media/'))
            e.path.substring(s.dir.path.length + 1): base64.encode(e.readAsBytesSync())
      };

  /// Sincroniza A y B alternando hasta que los dos digan que no hay nada que hacer (máximo [max] vueltas).
  Future<int> converge(Storage a, Storage b, FakeRemoteStore r, {int max = 8}) async {
    for (var i = 1; i <= max; i++) {
      final ra = await sync(a, r), rb = await sync(b, r);
      if (ra.nothingToDo && rb.nothingToDo) return i;
    }
    return -1;
  }

  group('conflictos de la misma hoja', () {
    test('dos hojas "(conflicto)" no pueden compartir ids de elementos: el editor las carga en un mapa por id y perdería datos', () async {
      final a = await device(), b = await device();
      final r = FakeRemoteStore();
      final nb = await create(a, 'N');
      await sync(a, r);
      await sync(b, r);
      await addText(a, nb.id, 0, 'deA', 'solo de A');
      await addText(b, nb.id, 0, 'deB', 'solo de B');
      expect(await converge(a, b, r), greaterThan(0));

      final idx = await a.loadIndex();
      final n = idx.notebooks.single;
      expect(n.sheets.length, 2, reason: 'la hoja original y la "(conflicto)"');
      var enArchivos = 0;
      for (final m in n.sheets) {
        enArchivos += (await a.readSheetTexts(n, m)).length;
      }
      final doc = await a.loadNotebook(n);
      expect(doc.texts.length, enArchivos,
          reason: 'la hoja de conflicto es una copia de la remota con los MISMOS ids: al abrir el cuaderno las dos hojas se pisan en doc.texts '
              'y al guardar se pierde contenido');
    });

    for (final seed in kSeeds) {
      test('rondas de ediciones concurrentes al azar (semilla $seed): no se pierde ningún texto y los dos lados convergen', () async {
        final r = Random(seed);
        final a = await device(), b = await device();
        final remote = FakeRemoteStore();
        final nb = await create(a, 'N', n: 3);
        await sync(a, remote);
        await sync(b, remote);
        final devs = [a, b];
        final expected = <String>{for (var k = 0; k < 3; k++) 'base $k'};
        var next = 0;
        for (var round = 0; round < 5; round++) {
          for (var d = 0; d < 2; d++) {
            for (var e = 0; e < r.nextInt(3); e++) {
              final k = r.nextInt(3), text = 'r$round-d$d-${next++}';
              // en la hoja k de ESE dispositivo (si hubo conflictos, las hojas se corrieron; se busca por índice válido)
              final idx = await devs[d].loadIndex();
              final sheets = idx.notebooks.firstWhere((x) => x.id == nb.id).sheets.length;
              await addText(devs[d], nb.id, min(k, sheets - 1), 'x${next}_$d', text);
              expected.add(text);
            }
          }
          final order = r.nextBool() ? [a, b, a, b] : [b, a, b, a];
          for (final s in order) {
            await sync(s, remote);
          }
        }
        final vueltas = await converge(a, b, remote, max: 10);
        expect(vueltas, greaterThan(0), reason: 'semilla $seed: no converge: la sync sigue encontrando trabajo');
        expect(files(a), files(b), reason: 'semilla $seed: los dispositivos quedaron con archivos distintos');
        final textos = (await allTexts(a)).toSet();
        expect(textos.containsAll(expected), isTrue, reason: 'semilla $seed: se perdieron ${expected.difference(textos)}');
      });
    }

    for (final seed in kSeeds) {
      test('cortes de red en puntos al azar (semilla $seed): reintentar converge y no pierde nada', () async {
        final r = Random(seed * 7);
        final a = await device(), b = await device();
        final remote = FakeRemoteStore();
        final nb = await create(a, 'N', n: 4);
        await sync(a, remote);
        await sync(b, remote);
        final expected = <String>{for (var k = 0; k < 4; k++) 'base $k'};
        for (var k = 0; k < 4; k++) {
          if (r.nextBool()) {
            await addText(a, nb.id, k, 'a$k', 'A$k');
            expected.add('A$k');
          }
          if (r.nextBool()) {
            await addText(b, nb.id, k, 'b$k', 'B$k');
            expected.add('B$k');
          }
        }
        for (final s in [a, b, a, b]) {
          remote
            ..resetOps()
            ..failAfter = r.nextInt(40);
          try {
            await sync(s, remote);
          } on RemoteOfflineException {
            // se cortó: la próxima pasada sigue
          }
        }
        remote.failAfter = null;
        expect(await converge(a, b, remote, max: 12), greaterThan(0), reason: 'semilla $seed');
        expect(files(a), files(b), reason: 'semilla $seed');
        final textos = (await allTexts(a)).toSet();
        expect(textos.containsAll(expected), isTrue, reason: 'semilla $seed: se perdieron ${expected.difference(textos)}');
      });
    }
  });

  group('la nube manda cosas rotas', () {
    test('una hoja basura, un notebook.json con hojas sin id y un índice ilegible: lo local no se toca y el resto sigue sincronizando', () async {
      final a = await device();
      final remote = FakeRemoteStore();
      final nb = await create(a, 'N', n: 2);
      await sync(a, remote);
      final antes = files(a);
      final idxAntes = a.indexFile.readAsStringSync();

      // se rompe lo de la nube
      final sheet0 = 'notebooks/${nb.id}/sheets/${nb.sheets[0].id}.sheet';
      remote.put(sheet0, [1, 2, 3, 4]);
      remote.put('notebooks/${nb.id}/notebook.json', utf8.encode(jsonEncode({'format': 3, 'sheets': [{'sin': 'id'}, 5]})));
      remote.put('index.json', utf8.encode('{"format":3,"notebooks":[{"id":'));
      // y a la vez hay algo bueno para subir
      final otro = await create(a, 'Otro');

      SyncReport? rep;
      await expectLater(sync(a, remote).then((v) => rep = v), completes, reason: 'una sola pasada con archivos malos no puede tirar');
      expect(rep!.errors, isNotEmpty);
      // lo local que estaba bien sigue entero
      final despues = files(a);
      for (final e in antes.entries) {
        expect(despues[e.key], e.value, reason: '${e.key} cambió por culpa de la nube');
      }
      expect(a.indexFile.readAsStringSync(), contains(nb.id), reason: 'el índice local ya no tiene el cuaderno');
      expect(a.indexFile.readAsStringSync().length, greaterThanOrEqualTo(idxAntes.length));
      // el cuaderno bueno nuevo SÍ llegó a la nube
      expect(remote.has('notebooks/${otro.id}/notebook.json'), isTrue, reason: 'un archivo malo bloqueó subir el resto');
      expect(() => decodeSheet(a.sheetFile(nb.id, nb.sheets[0].id).readAsBytesSync()), returnsNormally);
    });

    test('device nuevo que baja una nube con una hoja rota: baja lo demás y la hoja rota queda vacía (sin tirar)', () async {
      final a = await device(), b = await device();
      final remote = FakeRemoteStore();
      final nb = await create(a, 'N', n: 3);
      await sync(a, remote);
      remote.put('notebooks/${nb.id}/sheets/${nb.sheets[1].id}.sheet', List.filled(50, 7));
      final rep = await sync(b, remote);
      expect(rep.errors.length, 1);
      final idx = await b.loadIndex();
      final doc = await b.loadNotebook(idx.notebooks.single);
      expect(doc.sheetCount, 3);
      expect(doc.texts.length, 2, reason: 'las hojas 0 y 2 tienen su texto; la rota, vacía');
    });
  });

  test('guardar y sincronizar a la vez: lo que se guarda mientras sube no se pierde ni se sube a medias', () async {
    final a = await device(), b = await device();
    final remote = FakeRemoteStore();
    final nb = await create(a, 'N', n: 2);
    var tocadas = 0;
    // mientras se sube cada archivo, la app sigue guardando ediciones
    remote.onUpload = (path) async {
      if (tocadas < 6) {
        tocadas++;
        await addText(a, nb.id, tocadas % 2, 'mid$tocadas', 'mientras $tocadas');
      }
    };
    await sync(a, remote);
    remote.onUpload = null;
    expect(await converge(a, b, remote, max: 10), greaterThan(0));
    final textos = (await allTexts(b)).toSet();
    for (var i = 1; i <= tocadas; i++) {
      expect(textos, contains('mientras $i'), reason: 'el guardado #$i hecho durante la subida no llegó al otro lado');
    }
    expect(files(a), files(b));
  });
}
