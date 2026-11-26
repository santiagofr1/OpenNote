import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:apuntes/data/sheet_codec.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stress.dart';

/// La app muere (o el disco se llena) a mitad de guardar; los archivos quedan truncados, con restos `.tmp`, de una
/// versión que no conocemos; dos guardados se cruzan; se guarda mientras se borra.
/// Invariante central: NUNCA se pierden hojas que estaban bien en disco por culpa de un archivo vecino roto.
void main() {
  late Directory root;
  late Storage store;

  setUpAll(() => Storage.useIsolates = false);
  tearDownAll(() => Storage.useIsolates = true);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('apuntes_crash');
    store = Storage(root: root);
    await store.init();
  });
  tearDown(() async {
    await Storage.settleWrites();
    await root.delete(recursive: true);
  });

  /// Un Storage nuevo sobre la misma carpeta: lo que ve la app al reiniciar.
  Future<Storage> restart() async {
    await Storage.settleWrites();
    final s = Storage(root: root);
    await s.init();
    return s;
  }

  NotebookDoc sample(int n, {String name = 'Física'}) {
    final nb = Notebook.create(name);
    while (nb.sheets.length < n) {
      nb.sheets.add(nb.newSheet());
    }
    final d = NotebookDoc(nb);
    for (var k = 0; k < n; k++) {
      d.strokes['s$k'] = Stroke('s$k', 'pen', '#22211e', 2.6, [10, k * kSheetStep + 100, 128 / 255, 50, k * kSheetStep + 130, 1]);
      d.texts['t$k'] = TextBlock('t$k', 90, k * kSheetStep + 44, 800, 'hoja $k');
    }
    return d;
  }

  File nbJson(Storage s, Notebook nb) => File('${s.nbDir(nb.id).path}/notebook.json');
  Set<String> sheetFiles(Storage s, Notebook nb) => {
        for (final f in Directory('${s.nbDir(nb.id).path}/sheets').listSync().whereType<File>()) f.uri.pathSegments.last,
      };

  Future<NotebookDoc> persisted(int n) async {
    final d = sample(n);
    await store.saveNotebook(d);
    await store.saveIndex(NotesIndex(last: d.id, notebooks: [d.nb]));
    await Storage.settleWrites();
    return d;
  }

  group('notebook.json dañado: las hojas de disco NO se borran', () {
    // Escritura atómica (tmp + rename) hace raro un notebook.json truncado, pero pasa (disco lleno, restore de un backup
    // a medias, sync con un cliente viejo). Hoy `_readSheetList` lo toma por vacío, el documento se inventa UNA hoja
    // nueva y `_sweep` borra como "sobrantes" todos los .sheet que no son esa: el usuario pierde todo el cuaderno al abrirlo.
    final variantes = <String, List<int> Function(List<int> good)>{
      'vacío (0 bytes)': (g) => [],
      'cortado a la mitad': (g) => g.sublist(0, g.length ~/ 2),
      'cortado a un byte': (g) => g.sublist(0, 1),
      'sin la clave sheets': (g) => utf8.encode('{"format":3}'),
      'sheets no es lista': (g) => utf8.encode('{"format":3,"sheets":7}'),
      'basura binaria': (g) => List.generate(200, (i) => (i * 37) & 0xFF),
      'JSON null': (g) => utf8.encode('null'),
      'una lista': (g) => utf8.encode('[]'),
    };
    variantes.forEach((nombre, rompe) {
      test('notebook.json $nombre', () async {
        final d = await persisted(3);
        final antes = sheetFiles(store, d.nb);
        expect(antes.length, 3);
        final nj = nbJson(store, d.nb);
        nj.writeAsBytesSync(rompe(nj.readAsBytesSync()));

        final s2 = await restart();
        final idx = await s2.loadIndex();
        final nb = idx.notebooks.single;
        await s2.loadNotebook(nb); // lo que hace la app al tocar el cuaderno
        await Storage.settleWrites();

        expect(sheetFiles(s2, d.nb), containsAll(antes), reason: 'se borraron hojas buenas por un notebook.json roto');
      });
    });
  });

  group('index.json dañado o de otra versión', () {
    test('de un formato FUTURO (format: 4) no se toca ningún cuaderno', () async {
      // `loadIndex` manda a migrar todo lo que no sea `format == 3`: un índice más nuevo (otra versión instalada en
      // paralelo, backup de una app más nueva) se trata como "formato viejo" y `migrateLegacy` hace removeNotebookFiles.
      final d = await persisted(2);
      final before = sheetFiles(store, d.nb);
      final j = jsonDecode(store.indexFile.readAsStringSync()) as Map;
      j['format'] = 4;
      store.indexFile.writeAsStringSync(jsonEncode(j));

      final s2 = await restart();
      try {
        await s2.loadIndex();
      } catch (_) {
        // rechazarlo con un error está bien: lo que no puede pasar es perder datos
      }
      await Storage.settleWrites();
      expect(Directory('${root.path}/notebooks/${d.nb.id}').existsSync(), isTrue, reason: 'la carpeta del cuaderno desapareció');
      expect(sheetFiles(s2, d.nb), before, reason: 'se borraron o reescribieron hojas');
    });

    test('JSON válido pero con tipos que no son: loadIndex no tira (la app tiene que poder arrancar)', () async {
      for (final texto in [
        '{"format":3,"notebooks":[1,2]}',
        '{"format":3,"notebooks":[{"id":5,"name":"x"}]}',
        '{"format":3,"notebooks":[{"id":"a"}]}', // sin nombre
        '{"format":3,"notebooks":"nada"}',
        '{"format":3,"notebooks":[],"folders":[7]}',
        '{"format":3,"rev":"uno","notebooks":[]}',
        '[]',
        '"hola"',
      ]) {
        store.indexFile.writeAsStringSync(texto);
        final s2 = await restart();
        NotesIndex? idx;
        await expectLater(s2.loadIndex().then((v) => idx = v), completes, reason: 'índice: $texto');
        expect(idx, isNotNull);
      }
    });

    test('index.json ilegible: se guarda aparte Y los cuadernos que hay en disco reaparecen con todos sus datos', () async {
      final d = await persisted(2);
      final fac = Folder.create('Facultad'), an = Folder.create('Análisis', parent: fac.id);
      d.nb
        ..name = 'Física II'
        ..folder = an.id
        ..pin = hashPin('1234')
        ..bg = 'grid'
        ..paper = '#101010'
        ..spacing = 7.5
        ..size = 'a5'
        ..favorite = true
        ..touch();
      final antes = d.nb.toJson()..remove('last');
      await store.saveIndex(NotesIndex(last: d.id, notebooks: [d.nb], folders: [fac, an]));
      await Storage.settleWrites();
      for (final e in root.listSync().whereType<File>().where((e) => e.path.contains('index.json'))) {
        e.deleteSync(); // sin índice ni respaldo
      }
      store.indexFile.writeAsStringSync('{"format":3,"notebooks":[{"id":"' + d.id); // cortado
      final s2 = await restart();
      final idx = await s2.loadIndex();
      expect(Directory(root.path).listSync().any((e) => e.path.contains('index.json.corrupto-')), isTrue,
          reason: 'el índice roto tiene que quedar guardado aparte');
      final nb = idx.notebooks.single; // y NO el cuaderno de ejemplo
      expect(nb.id, d.id);
      expect(nb.toJson()..remove('last'), antes, reason: 'nombre, carpeta, PIN y ajustes vuelven como estaban');
      expect(idx.pathOf(nb.folder).map((f) => (f.id, f.name)), [(fac.id, 'Facultad'), (an.id, 'Análisis')]);
      expect(idx.pathOf(nb.folder).last.parent, fac.id);
      final doc = await s2.loadNotebook(nb);
      expect(doc.texts['t0']!.text, 'hoja 0');
      expect(doc.texts['t1']!.text, 'hoja 1');
      expect(doc.strokes.length, 2);
    });
  });

  group('restos de una caída a mitad de escritura', () {
    test('.tmp sueltos (de index, notebook y hojas) no molestan, y el guardado siguiente no deja ninguno', () async {
      final d = await persisted(2);
      File('${root.path}/index.json.tmp').writeAsStringSync('{"format":3,"notebo');
      File('${store.nbDir(d.id).path}/notebook.json.tmp').writeAsStringSync('{"for');
      final sh = store.sheetFile(d.id, d.sheets[0].id);
      File('${sh.path}.tmp').writeAsBytesSync([1, 2, 3]);

      final s2 = await restart();
      final idx = await s2.loadIndex();
      final doc = await s2.loadNotebook(idx.notebooks.single);
      expect(doc.texts.length, 2);
      expect(doc.texts['t0']!.text, 'hoja 0');
      doc.texts['t0']!.text = 'cambiada';
      doc.markDirtyAt(44);
      await s2.saveNotebook(doc);
      await s2.saveIndex(idx);
      await Storage.settleWrites();
      final tmps = root.listSync(recursive: true).where((e) => e.path.endsWith('.tmp')).toList();
      expect(tmps, isEmpty, reason: 'quedaron temporales: $tmps');
      final s3 = await restart();
      final doc3 = await s3.loadNotebook((await s3.loadIndex()).notebooks.single);
      expect(doc3.texts['t0']!.text, 'cambiada');
    });

    test('corte justo después de escribir una hoja y antes de notebook.json: al reiniciar todo es coherente', () async {
      final d = await persisted(3);
      // se edita la hoja 0 y 1 y se agrega la 3; el "corte" tira justo después de escribir la primera hoja
      d.texts['t0']!.text = 'nuevo 0';
      d.markDirtyAt(44);
      d.texts['t1']!.text = 'nuevo 1';
      d.markDirtyAt(kSheetStep + 44);
      d.addSheet();
      d.strokes['s3'] = Stroke('s3', 'pen', '#000000', 2, [1, 3 * kSheetStep + 5, .5, 9, 3 * kSheetStep + 9, .5]);
      var escritas = 0;
      store.onSheetWrite = (_, _) {
        if (++escritas == 1) throw const FileSystemException('se cortó la luz');
      };
      await expectLater(store.saveNotebook(d), throwsA(isA<FileSystemException>()));
      store.onSheetWrite = null;

      // reinicio (sin retry): cada archivo tiene que ser entero y la lista de hojas apunta a hojas que existen
      final s2 = await restart();
      final idx = await s2.loadIndex();
      final nb = idx.notebooks.single;
      final doc = await s2.loadNotebook(nb);
      expect(doc.sheetCount, 3, reason: 'notebook.json sigue siendo el viejo (3 hojas)');
      for (final m in nb.sheets) {
        final f = s2.sheetFile(nb.id, m.id);
        expect(f.existsSync(), isTrue, reason: 'falta la hoja ${m.id}');
        expect(() => decodeSheet(f.readAsBytesSync()), returnsNormally, reason: 'hoja ${m.id} a medias');
      }
      expect(doc.texts['t2']!.text, 'hoja 2', reason: 'lo no editado no cambia');
      expect({'hoja 0', 'nuevo 0'}, contains(doc.texts['t0']!.text));
      expect({'hoja 1', 'nuevo 1'}, contains(doc.texts['t1']!.text));
    });

    test('el guardado que falló se reintenta y converge: el disco termina igual a la memoria', () async {
      final d = await persisted(3);
      for (var k = 0; k < 3; k++) {
        d.texts['t$k']!.text = 'v2 $k';
        d.markDirtyAt(k * kSheetStep + 44);
      }
      d.addSheet();
      var n = 0;
      store.onSheetWrite = (_, _) {
        if (++n == 2) throw const FileSystemException('disco lleno');
      };
      await expectLater(store.saveNotebook(d), throwsA(anything));
      store.onSheetWrite = null;
      expect(d.hasDirty, isTrue, reason: 'si no se guardó tiene que seguir sucio');
      await store.saveNotebook(d);
      final s2 = await restart();
      final back = await s2.loadNotebook((await s2.loadIndex()).notebooks.single);
      expect(snapshotDocLoose(back), snapshotDocLoose(d));
    });
  });

  group('guardados concurrentes', () {
    for (final seed in kSeeds.take(4)) {
      test('muchos guardados sin esperar, mezclados con ediciones (semilla $seed): el último estado queda en disco', () async {
        final r = Random(seed);
        final d = sample(4);
        await store.saveNotebook(d);
        final pend = <Future<void>>[];
        for (var i = 0; i < 40; i++) {
          final k = r.nextInt(d.sheetCount);
          switch (r.nextInt(5)) {
            case 0:
              final s = randomStroke(r, 'n$i', yBase: k * kSheetStep, n: 2 + r.nextInt(30));
              d.strokes[s.id] = s;
              d.markDirtyElement(s); // como el editor: la hoja del trazo queda sucia
            case 1:
              if (d.strokes.isEmpty) break;
              final id = d.strokes.keys.elementAt(r.nextInt(d.strokes.length));
              d.markDirtyElement(d.strokes[id]!);
              d.strokes.remove(id);
            case 2:
              final j = r.nextInt(4); // el texto tj está en la hoja j: se marca ESA hoja, como hace el editor
              d.texts['t$j']!.text = 'edit $i';
              d.markDirtyAt(j * kSheetStep + 44);
            case 3:
              d.addSheet();
            case 4:
              if (d.sheetCount > 1 && d.lastSheetEmpty) d.removeLastSheetIfEmpty();
          }
          pend.add(store.saveNotebook(d));
          if (r.nextBool()) await Future<void>.delayed(Duration(microseconds: r.nextInt(300)));
        }
        await Future.wait(pend);
        await Storage.settleWrites();
        final s2 = await restart();
        final nb = Notebook(d.id, d.nb.name)..loadSheetsJson(jsonDecode(nbJson(s2, d.nb).readAsStringSync()) as Map);
        final back = await s2.loadNotebook(nb);
        expect(snapshotDocLoose(back), snapshotDocLoose(d), reason: 'semilla $seed');
        expect(sheetFiles(s2, d.nb).length, d.sheetCount, reason: 'sobran o faltan archivos de hoja (semilla $seed)');
      });
    }

    test('borrar el cuaderno con guardados en cola: la carpeta no resucita', () async {
      final d = sample(3);
      final idx = NotesIndex(notebooks: [d.nb]);
      final saves = [for (var i = 0; i < 3; i++) store.saveNotebook(d)];
      d.texts['t0']!.text = 'otra';
      d.markDirtyAt(44);
      saves.add(store.saveNotebook(d));
      final del = store.deleteNotebook(idx, d.nb);
      await Future.wait([...saves.map((f) => f.catchError((_) {})), del]);
      await Storage.settleWrites();
      expect(store.nbDir(d.id).existsSync(), isFalse, reason: 'un guardado en cola volvió a crear la carpeta borrada');
      expect(idx.notebooks, isEmpty);
    });

    test('un trazo con un punto no finito no impide guardar el resto del cuaderno (ni los otros cuadernos)', () async {
      final d = sample(2);
      await store.saveNotebook(d);
      // el trazo entra sano (bounds cacheados) y después sus puntos se corrompen (una transformación 0/0, un driver)
      final bad = Stroke('malo', 'pen', '#000000', 2, [10, kSheetStep + 10, .5, 20, kSheetStep + 20, .5]);
      d.strokes['malo'] = bad;
      bad.bounds;
      bad.pts[0] = double.nan;
      final nuevo = Stroke('bueno', 'pen', '#000000', 2, [10, 10, .5, 30, 30, .5]);
      d.strokes['bueno'] = nuevo;
      await expectLater(store.saveNotebook(d), completes,
          reason: 'cada intento de autoguardado vuelve a tirar UnsupportedError: la hoja 0 sana tampoco se guarda nunca más');
      final s2 = await restart();
      final nb = Notebook(d.id, d.nb.name)..loadSheetsJson(jsonDecode(nbJson(s2, d.nb).readAsStringSync()) as Map);
      final back = await s2.loadNotebook(nb);
      expect(back.strokes.containsKey('bueno'), isTrue, reason: 'el trazo sano se perdió');
    });
  });

  group('cuaderno enorme', () {
    test('2000 hojas: guardar, reabrir con carga perezosa y borrar una del medio sin tocar el resto', () async {
      final nb = Notebook.create('Enorme');
      while (nb.sheets.length < 2000) {
        nb.sheets.add(nb.newSheet());
      }
      final d = NotebookDoc(nb);
      for (var k = 0; k < 2000; k += 7) {
        d.texts['t$k'] = TextBlock('t$k', 90, k * kSheetStep + 44, 800, 'hoja $k');
      }
      await store.saveNotebook(d);
      await store.saveIndex(NotesIndex(notebooks: [nb]));
      await Storage.settleWrites();
      expect(sheetFiles(store, nb).length, 2000);

      final s2 = await restart();
      final nb2 = (await s2.loadIndex()).notebooks.single;
      final doc = await s2.openNotebook(nb2, around: 1000);
      expect(doc.sheetCount, 2000);
      expect(doc.loadedSheets.length, lessThanOrEqualTo(7), reason: 'carga perezosa: solo las cercanas');
      expect(doc.isLoadedAt(1000), isTrue);
      // borrar la hoja 1000 y guardar: solo cambia ESA hoja (y notebook.json); el resto de los archivos no se reescribe
      final escritas = <String>[];
      s2.onSheetWrite = (_, id) => escritas.add(id);
      doc.deleteSheet(1000);
      await s2.saveNotebook(doc);
      await Storage.settleWrites();
      expect(escritas.length, lessThanOrEqualTo(10), reason: 'borrar una hoja reescribió ${escritas.length} archivos');
      expect(sheetFiles(s2, nb2).length, 1999);
    }, tags: ['lento'], timeout: const Timeout(Duration(minutes: 3)));
  });
}
