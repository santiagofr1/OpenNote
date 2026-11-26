import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/sync/fake_remote_store.dart';
import 'package:apuntes/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stress.dart';

/// Issue #23: index.json ilegible. La biblioteca se recupera de `index.json.bak` y, si tampoco sirve, de los datos que cada
/// notebook.json guarda del cuaderno (`meta`: nombre, carpeta y su camino, PIN y ajustes). Nada se borra; el cuaderno de
/// ejemplo solo aparece si no hay ningún cuaderno en disco; los cuadernos borrados no resucitan.
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
    final d = await Directory.systemTemp.createTemp('apuntes_indice');
    dirs.add(d);
    final s = Storage(root: d);
    await s.init();
    return s;
  }

  /// Un Storage nuevo sobre la misma carpeta: lo que ve la app al reiniciar.
  Future<Storage> restart(Storage s) async {
    await Storage.settleWrites();
    final n = Storage(root: s.dir);
    await n.init();
    return n;
  }

  /// Cuaderno nuevo con un texto con su nombre en cada hoja, guardado en disco y puesto en el índice (sin guardarlo).
  Future<Notebook> make(Storage s, NotesIndex idx, String name, {int sheets = 2, String? folder}) async {
    final nb = Notebook.create(name)..folder = folder;
    while (nb.sheets.length < sheets) {
      nb.sheets.add(nb.newSheet());
    }
    final d = NotebookDoc(nb);
    for (var k = 0; k < sheets; k++) {
      d.texts['t$k'] = TextBlock('t$k', 90, k * kSheetStep + 44, 800, '$name $k');
    }
    nb.touch();
    await s.saveNotebook(d);
    idx.notebooks.add(nb);
    return nb;
  }

  /// Todo lo que el índice sabe de los cuadernos (sin `last`, que es de cada dispositivo) y el camino de carpetas.
  Map<String, Object?> snap(NotesIndex idx) => {
        for (final n in idx.notebooks)
          n.id: {
            ...(n.toJson()..remove('last')..remove('folder')),
            'path': [for (final f in idx.pathOf(n.folder)) '${f.id}:${f.name}'],
          },
      };

  Future<void> breakIndex(Storage s, {bool backup = true}) async {
    await Storage.settleWrites();
    s.indexFile.writeAsStringSync('{"format":3,"notebooks":[{"id":"n_cor');
    if (backup && s.indexBackup.existsSync()) s.indexBackup.writeAsStringSync('basura');
  }

  List<FileSystemEntity> aside(Storage s, String part) => s.dir.listSync().where((e) => e.path.contains(part)).toList();

  Map metaDe(Storage s, String id) => (jsonDecode(File('${s.nbDir(id).path}/notebook.json').readAsStringSync()) as Map)['meta'] as Map;

  void sinMeta(Storage s, Iterable<Notebook> nbs) {
    for (final n in nbs) {
      final f = File('${s.nbDir(n.id).path}/notebook.json');
      f.writeAsStringSync(jsonEncode((jsonDecode(f.readAsStringSync()) as Map)..remove('meta')));
    }
  }

  group('copia de respaldo index.json.bak', () {
    test('cada guardado deja en .bak la versión buena anterior (y nunca un .tmp suelto)', () async {
      final s = await device();
      final idx = NotesIndex();
      await make(s, idx, 'Uno');
      await s.saveIndex(idx);
      await Storage.settleWrites();
      expect(s.indexBackup.existsSync(), isFalse, reason: 'el primer guardado no tiene versión anterior');
      final v1 = s.indexFile.readAsStringSync();
      idx.notebooks.single.name = 'Dos';
      await s.saveIndex(idx);
      await Storage.settleWrites();
      expect(s.indexBackup.readAsStringSync(), v1);
      expect(jsonDecode(s.indexFile.readAsStringSync())['notebooks'][0]['name'], 'Dos');
      expect(s.dir.listSync().where((e) => e.path.endsWith('.tmp')), isEmpty);
    });

    test('un index.json roto NO pisa el respaldo bueno', () async {
      final s = await device();
      final idx = NotesIndex();
      await make(s, idx, 'Uno');
      await s.saveIndex(idx);
      await s.saveIndex(idx);
      await Storage.settleWrites();
      final bueno = s.indexBackup.readAsStringSync();
      s.indexFile.writeAsStringSync('{"for'); // se rompió con la app andando
      await s.saveIndex(idx);
      await Storage.settleWrites();
      expect(s.indexBackup.readAsStringSync(), bueno);
    });

    test('index.json ilegible: se restaura del .bak (con la carpeta vacía que solo el índice conocía) y el roto queda aparte', () async {
      final s = await device();
      final idx = NotesIndex();
      final vacia = Folder.create('Vacía'), f = Folder.create('Mate');
      idx.folders.addAll([vacia, f]);
      final a = await make(s, idx, 'A', folder: f.id);
      await make(s, idx, 'B');
      await s.saveIndex(idx);
      a.name = 'A renombrado';
      await s.saveIndex(idx);
      await Storage.settleWrites();
      final antes = snap(idx);
      await breakIndex(s, backup: false);

      final s2 = await restart(s);
      final r = await s2.loadIndex();
      expect(snap(r), antes, reason: 'el nombre más nuevo sale del notebook.json: es más fresco que el .bak');
      expect(r.folders.map((x) => x.name).toSet(), {'Vacía', 'Mate'});
      expect(aside(s2, 'index.json.corrupto-'), hasLength(1));
      expect(r.notebooks.map((n) => n.name), isNot(contains('Mi cuaderno')));
      await Storage.settleWrites();
      expect(jsonDecode(s2.indexFile.readAsStringSync())['notebooks'], hasLength(2), reason: 'el índice rearmado se guarda');
    });

    test('un cuaderno del .bak que se borró después no resucita; uno nuevo que el .bak no conoce aparece', () async {
      final s = await device();
      final idx = NotesIndex();
      final viejo = await make(s, idx, 'Viejo');
      await make(s, idx, 'Queda');
      await s.saveIndex(idx);
      final nuevo = await make(s, idx, 'Nuevo');
      await s.deleteNotebook(idx, viejo); // el .bak (índice anterior) todavía lo lista
      await Storage.settleWrites();
      expect(jsonDecode(s.indexBackup.readAsStringSync())['notebooks'].map((n) => n['name']), contains('Viejo'));
      await breakIndex(s, backup: false);
      final r = await (await restart(s)).loadIndex();
      expect(r.notebooks.map((n) => n.name).toSet(), {'Queda', 'Nuevo'});
      expect(r.notebooks.any((n) => n.id == nuevo.id), isTrue);
    });
  });

  group('reconstrucción desde notebook.json (sin índice ni respaldo)', () {
    test('.bak también roto: nombre, carpeta, PIN, ajustes y contenido vuelven; los dos archivos rotos quedan aparte', () async {
      final s = await device();
      final idx = NotesIndex();
      final f = Folder.create('Facultad');
      idx.folders.add(f);
      final a = await make(s, idx, 'Álgebra', folder: f.id);
      a
        ..pin = hashPin('9876')
        ..bg = 'dots'
        ..paper = '#222222'
        ..spacing = 6
        ..size = 'a5'
        ..favorite = true;
      final c = await make(s, idx, 'Lienzo');
      c
        ..canvas = true
        ..canvasW = 2500
        ..image = 'm_1.png';
      await make(s, idx, 'Suelto', sheets: 3);
      await s.saveIndex(idx);
      await s.saveIndex(idx);
      await Storage.settleWrites();
      final antes = snap(idx);
      await breakIndex(s);

      final s2 = await restart(s);
      final r = await s2.loadIndex();
      expect(snap(r), antes);
      expect(aside(s2, 'index.json.corrupto-'), hasLength(1));
      expect(aside(s2, 'index.json.bak.corrupto-'), hasLength(1));
      for (final n in r.notebooks) {
        final d = await s2.loadNotebook(n);
        expect(d.texts.length, n.name == 'Suelto' ? 3 : 2);
        expect(d.texts['t0']!.text, '${n.name} 0');
      }
    });

    test('carpetas anidadas: se recrean con sus ids, nombres y padres; la carpeta que no se puede reconstruir deja al cuaderno en el inicio', () async {
      final s = await device();
      final idx = NotesIndex();
      final a = Folder.create('A'), b = Folder.create('B', parent: a.id), c = Folder.create('C', parent: b.id), d = Folder.create('D');
      idx.folders.addAll([a, b, c, d]);
      await make(s, idx, 'enC', folder: c.id);
      await make(s, idx, 'enA', folder: a.id);
      final enD = await make(s, idx, 'enD', folder: d.id);
      await make(s, idx, 'raiz');
      await s.saveIndex(idx);
      await Storage.settleWrites();
      final antes = snap(idx);
      await breakIndex(s);
      final r = await (await restart(s)).loadIndex();
      expect(snap(r), antes);
      expect({for (final f in r.folders) f.id: f.parent}, {a.id: null, b.id: a.id, c.id: b.id, d.id: null});
      expect(r.pathLabel(r.notebooks.firstWhere((n) => n.name == 'enC').folder), 'Inicio / A / B / C');

      // un notebook.json cuyo camino de carpetas viene roto: el cuaderno se recupera igual, en el inicio
      await Storage.settleWrites();
      final nj = File('${s.nbDir(enD.id).path}/notebook.json');
      final j = jsonDecode(nj.readAsStringSync()) as Map;
      j['meta']['folderPath'] = 'no es una lista';
      j['meta'].remove('folder');
      nj.writeAsStringSync(jsonEncode(j));
      await breakIndex(await restart(s), backup: true);
      final r2 = await (await restart(s)).loadIndex();
      expect(r2.notebooks.firstWhere((n) => n.name == 'enD').folder, isNull);
      expect(r2.notebooks, hasLength(4));
    });

    test('notebook.json viejo (sin los datos nuevos): se lee igual y, sin índice, queda como "Cuaderno recuperado N" traducido', () async {
      final s = await device();
      final idx = NotesIndex();
      for (final n in ['a', 'b', 'c']) {
        await make(s, idx, n);
      }
      await s.saveIndex(idx);
      await Storage.settleWrites();
      sinMeta(s, idx.notebooks); // como los dejaba la versión anterior
      // con el índice sano se lee igual y se completa
      final s1 = await restart(s);
      final ok = await s1.loadIndex();
      expect(snap(ok), snap(idx));
      await Storage.settleWrites();
      for (final n in ok.notebooks) {
        expect(metaDe(s1, n.id)['name'], n.name);
      }
      // sin índice ni meta
      sinMeta(s1, idx.notebooks);
      await breakIndex(s1);
      final s2 = await restart(s);
      final r = await s2.loadIndex(recoveredName: (n) => 'Caderno recuperado $n');
      expect(r.notebooks.map((n) => n.name).toSet(), {'Caderno recuperado 1', 'Caderno recuperado 2', 'Caderno recuperado 3'});
      expect(r.notebooks.map((n) => n.id).toSet(), idx.notebooks.map((n) => n.id).toSet());
      for (final n in r.notebooks) {
        expect((await s2.loadNotebook(n)).texts.length, 2, reason: 'el contenido está');
      }
    });

    test('sin traducción el nombre es "Cuaderno recuperado N"', () async {
      final s = await device();
      final idx = NotesIndex();
      final nb = await make(s, idx, 'x');
      await s.saveIndex(idx);
      await Storage.settleWrites();
      sinMeta(s, [nb]);
      await breakIndex(s);
      final r = await (await restart(s)).loadIndex();
      expect(r.notebooks.single.name, 'Cuaderno recuperado 1');
    });

    test('notebook.json roto pero con hojas: el cuaderno se recupera (sin nombre) y no se pierde ninguna hoja', () async {
      final s = await device();
      final idx = NotesIndex();
      final nb = await make(s, idx, 'x', sheets: 3);
      await s.saveIndex(idx);
      await Storage.settleWrites();
      File('${s.nbDir(nb.id).path}/notebook.json').writeAsStringSync('{"for');
      await breakIndex(s);
      final s2 = await restart(s);
      final r = await s2.loadIndex();
      expect(r.notebooks.single.id, nb.id);
      expect(r.notebooks.single.name, 'Cuaderno recuperado 1');
      expect((await s2.loadNotebook(r.notebooks.single)).texts.length, 3);
    });

    test('sin cuadernos en disco: cuaderno de ejemplo, como siempre; carpetas vacías de notebooks/ se ignoran', () async {
      final s = await device();
      Directory('${s.dir.path}/notebooks/n_vacio').createSync(recursive: true);
      Directory('${s.dir.path}/notebooks/..raro').createSync(recursive: true);
      final r = await s.loadIndex(sampleName: 'Mi cuaderno');
      expect(r.notebooks.map((n) => n.name), ['Mi cuaderno']);
    });

    test('un índice legible NO recupera cuadernos que le faltan (podrían ser borrados cuyos archivos todavía no se limpiaron)', () async {
      final s = await device();
      final idx = NotesIndex();
      await make(s, idx, 'Queda');
      final borrado = await make(s, idx, 'Borrado en otro lado');
      await s.saveIndex(idx);
      await Storage.settleWrites();
      final j = jsonDecode(s.indexFile.readAsStringSync()) as Map;
      (j['notebooks'] as List).removeWhere((n) => n['id'] == borrado.id);
      s.indexFile.writeAsStringSync(jsonEncode(j));
      final s2 = await restart(s);
      final r = await s2.loadIndex();
      expect(r.notebooks.map((n) => n.name), ['Queda']);
      expect(s2.nbDir(borrado.id).existsSync(), isTrue, reason: 'y sus archivos no se tocan');
    });
  });

  group('bibliotecas al azar', () {
    for (final seed in kSeeds) {
      test('operaciones al azar (semilla $seed), índice y .bak rotos: la biblioteca reconstruida equivale a la original', () async {
        final r = Random(seed);
        final s = await device();
        final idx = NotesIndex();
        final names = ['Mate', 'Física', 'Ñandú', 'Química', 'Historia', 'Dibujo', 'Notas', 'Ideas'];
        var contador = 0;
        for (var paso = 0; paso < 60; paso++) {
          final nbs = idx.notebooks;
          switch (r.nextInt(9)) {
            case 0 || 1: // crear
              final nb = await make(s, idx, '${names[r.nextInt(names.length)]} ${contador++}',
                  sheets: 1 + r.nextInt(3), folder: idx.folders.isEmpty || r.nextBool() ? null : idx.folders[r.nextInt(idx.folders.length)].id);
              nb
                ..bg = ['lined', 'grid', 'dots', 'blank'][r.nextInt(4)]
                ..paper = ['#fffefb', '#101010', '#f5e6c8'][r.nextInt(3)]
                ..spacing = [5.0, 6.5, 8.0][r.nextInt(3)]
                ..size = ['a4', 'a5', 'a3'][r.nextInt(3)]
                ..favorite = r.nextInt(4) == 0
                ..canvas = r.nextInt(6) == 0;
              if (nb.canvas) nb.canvasW = kCanvasW0 + r.nextInt(5) * 100;
            case 2: // renombrar
              if (nbs.isNotEmpty) nbs[r.nextInt(nbs.length)].name = 'ren ${contador++} ${names[r.nextInt(names.length)]}';
            case 3: // mover
              if (nbs.isNotEmpty) {
                idx.moveNotebook(nbs[r.nextInt(nbs.length)], idx.folders.isEmpty || r.nextInt(3) == 0 ? null : idx.folders[r.nextInt(idx.folders.length)].id);
              }
            case 4: // PIN
              if (nbs.isNotEmpty) {
                final nb = nbs[r.nextInt(nbs.length)];
                nb.pin = nb.pin == null ? hashPin('${r.nextInt(10000)}') : null;
              }
            case 5: // borrar cuaderno
              if (nbs.isNotEmpty) await s.deleteNotebook(idx, nbs[r.nextInt(nbs.length)]);
            case 6: // carpeta nueva
              idx.folders.add(Folder.create('${names[r.nextInt(names.length)]} f${contador++}',
                  parent: idx.folders.isEmpty || r.nextBool() ? null : idx.folders[r.nextInt(idx.folders.length)].id));
            case 7: // renombrar / mover carpeta
              if (idx.folders.isNotEmpty) {
                final f = idx.folders[r.nextInt(idx.folders.length)];
                if (r.nextBool()) {
                  f.name = 'carp ${contador++}';
                } else {
                  idx.moveFolder(f, r.nextInt(3) == 0 ? null : idx.folders[r.nextInt(idx.folders.length)].id);
                }
              }
            case 8: // borrar carpeta
              if (idx.folders.isNotEmpty) {
                final gone = idx.deleteFolder(idx.folders[r.nextInt(idx.folders.length)],
                    r.nextBool() ? FolderDelete.moveContentsToParent : FolderDelete.deleteContents);
                for (final nb in gone) {
                  await s.removeNotebookFiles(nb.id);
                }
              }
          }
          if (r.nextInt(3) == 0) await s.saveIndex(idx); // la app guarda cada tanto, no a cada paso
        }
        await s.saveIndex(idx);
        await Storage.settleWrites();
        final antes = snap(idx);
        await breakIndex(s);

        final s2 = await restart(s);
        final rec = await s2.loadIndex();
        if (antes.isEmpty) {
          expect(rec.notebooks.map((n) => n.name), ['Mi cuaderno']);
          return;
        }
        expect(snap(rec), antes, reason: 'semilla $seed');
        for (final n in rec.notebooks) {
          final d = await s2.loadNotebook(n);
          expect(d.texts['t0']!.text, endsWith(' 0'));
          expect(d.texts.length, n.allSheets.length);
        }
        // y lo recuperado se guardó: reiniciar otra vez da lo mismo
        await Storage.settleWrites();
        final rec2 = await (await restart(s2)).loadIndex();
        expect(snap(rec2), antes);
      });
    }
  });

  group('sincronización de los datos del cuaderno', () {
    Future<SyncReport> sync(Storage s, FakeRemoteStore r) => SyncEngine(s, r, busy: () => {}, account: 'a@b.c').sync();

    Future<int> converge(Storage a, Storage b, FakeRemoteStore r, {int max = 8}) async {
      for (var i = 1; i <= max; i++) {
        final ra = await sync(a, r), rb = await sync(b, r);
        if (ra.nothingToDo && rb.nothingToDo) return i;
      }
      return -1;
    }

    test('nombre, carpeta y PIN viajan en notebook.json entre dispositivos, convergen y no rebotan', () async {
      final a = await device(), b = await device();
      final remote = FakeRemoteStore();
      final idx = NotesIndex();
      final f1 = Folder.create('Uno'), f2 = Folder.create('Dos', parent: f1.id);
      idx.folders.addAll([f1, f2]);
      final nb = await make(a, idx, 'Original', folder: f2.id);
      nb.pin = hashPin('1111');
      await a.saveIndex(idx);
      expect(await converge(a, b, remote), greaterThan(0));

      final ib = await b.loadIndex();
      expect(ib.notebooks.single.name, 'Original');
      expect(metaDe(b, nb.id)['name'], 'Original');
      expect((metaDe(b, nb.id)['folderPath'] as List).map((e) => e['name']), ['Uno', 'Dos']);
      expect(metaDe(b, nb.id)['pin'], hashPin('1111'));

      // B cambia nombre, carpeta y PIN
      final n = ib.notebooks.single;
      n
        ..name = 'Renombrado en B'
        ..pin = null;
      final f3 = Folder.create('Tres');
      ib.folders.add(f3);
      ib.moveNotebook(n, f3.id);
      await b.saveIndex(ib);
      expect(await converge(a, b, remote), greaterThan(0));

      final ia = await a.loadIndex();
      expect(ia.notebooks.single.name, 'Renombrado en B');
      expect(ia.notebooks.single.pin, isNull);
      expect(ia.pathOf(ia.notebooks.single.folder).map((f) => f.name), ['Tres']);
      await Storage.settleWrites();
      expect(metaDe(a, nb.id), metaDe(b, nb.id), reason: 'los dos notebook.json coinciden');
      expect(metaDe(a, nb.id)['name'], 'Renombrado en B');
      expect(metaDe(a, nb.id).containsKey('pin'), isFalse);

      // sin ping-pong: otra vuelta no sube ni baja nada
      final ups = remote.uploads;
      for (var i = 0; i < 3; i++) {
        final ra = await sync(a, remote), rb = await sync(b, remote);
        expect(ra.nothingToDo && rb.nothingToDo, isTrue, reason: 'vuelta $i');
      }
      expect(remote.uploads, ups);

      // y si A pierde todo el índice, recupera lo último de B
      await breakIndex(a);
      final r = await (await restart(a)).loadIndex();
      expect(r.notebooks.single.name, 'Renombrado en B');
      expect(r.notebooks.single.pin, isNull);
      expect(r.pathOf(r.notebooks.single.folder).map((f) => f.name), ['Tres']);
    });

    test('renombrar en los dos lados a la vez: queda un solo ganador igual en el índice y en notebook.json', () async {
      final a = await device(), b = await device();
      final remote = FakeRemoteStore();
      final idx = NotesIndex();
      final nb = await make(a, idx, 'Base');
      await a.saveIndex(idx);
      await converge(a, b, remote);
      idx.notebooks.single.name = 'De A';
      await a.saveIndex(idx);
      final ib = await b.loadIndex();
      ib.notebooks.single.name = 'De B';
      await b.saveIndex(ib);
      expect(await converge(a, b, remote), greaterThan(0));
      final na = (await a.loadIndex()).notebooks.single.name, nbb = (await b.loadIndex()).notebooks.single.name;
      expect(na, nbb);
      await Storage.settleWrites();
      expect(metaDe(a, nb.id)['name'], na);
      expect(metaDe(b, nb.id)['name'], na);
    });

    test('un notebook.json de una app vieja (sin datos) no borra los del otro dispositivo', () async {
      final a = await device(), b = await device();
      final remote = FakeRemoteStore();
      final idx = NotesIndex();
      final nb = await make(a, idx, 'Con datos');
      await a.saveIndex(idx);
      await converge(a, b, remote);
      sinMeta(b, [nb]); // B es una app vieja: reescribe su notebook.json sin `meta`
      await converge(a, b, remote);
      expect((await a.loadIndex()).notebooks.single.name, 'Con datos'); // al leer el índice A completa su notebook.json
      await Storage.settleWrites();
      expect(metaDe(a, nb.id)['name'], 'Con datos');
      expect(await converge(a, b, remote), greaterThan(0));
      expect(metaDe(a, nb.id)['name'], 'Con datos');
    });

    test('un cuaderno borrado en un dispositivo no resucita en el otro, ni aunque después se rompa su índice', () async {
      final a = await device(), b = await device();
      final remote = FakeRemoteStore();
      final idx = NotesIndex();
      final queda = await make(a, idx, 'Queda');
      final borrado = await make(a, idx, 'Se borra');
      await a.saveIndex(idx);
      expect(await converge(a, b, remote), greaterThan(0));
      expect((await b.loadIndex()).notebooks, hasLength(2));

      await a.deleteNotebook(idx, borrado);
      expect(await converge(a, b, remote), greaterThan(0));
      final ib = await b.loadIndex();
      expect(ib.notebooks.map((n) => n.id), [queda.id]);
      expect(File('${b.nbDir(borrado.id).path}/notebook.json').existsSync(), isFalse);

      await breakIndex(b);
      final r = await (await restart(b)).loadIndex();
      expect(r.notebooks.map((n) => n.id), [queda.id], reason: 'rearmar la biblioteca no trae de vuelta lo borrado');
      expect(await converge(a, b, remote), greaterThan(0));
      expect((await a.loadIndex()).notebooks.map((n) => n.id), [queda.id]);
    });
  });
}
