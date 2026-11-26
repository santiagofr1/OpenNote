import 'dart:convert';
import 'dart:io';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/sync/fake_remote_store.dart';
import 'package:apuntes/sync/sync_engine.dart';
import 'package:apuntes/sync/sync_paths.dart';
import 'package:flutter_test/flutter_test.dart';

/// prefs.json y sync_state.json dañados, y preferencias guardadas en ráfaga o con valores que no se pueden escribir.
void main() {
  late Directory root;
  late Storage store;

  setUpAll(() => Storage.useIsolates = false);
  tearDownAll(() => Storage.useIsolates = true);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('apuntes_prefs_stress');
    store = Storage(root: root);
    await store.init();
  });
  tearDown(() async {
    await Storage.settleWrites();
    await root.delete(recursive: true);
  });

  group('prefs.json', () {
    final rotos = <String, List<int>>{
      'vacío': [],
      'llave suelta': utf8.encode('{'),
      'cortado': utf8.encode('{"appLanguage":"es","tool'),
      'lista': utf8.encode('[1,2]'),
      'null': utf8.encode('null'),
      'texto': utf8.encode('"hola"'),
      'binario': List.generate(500, (i) => (i * 131) & 0xFF),
      'UTF-8 inválido': [0x7B, 0x22, 0xC3, 0x28, 0x22, 0x3A, 0x31, 0x7D],
      'enorme (5 MB de espacios)': List.filled(5 * 1024 * 1024, 0x20),
    };
    rotos.forEach((nombre, bytes) {
      test('$nombre: loadPrefs no tira, y guardar después anda y deja un JSON válido', () async {
        File('${root.path}/prefs.json').writeAsBytesSync(bytes);
        Map? p;
        await expectLater(store.loadPrefs().then((v) => p = v), completes);
        expect(p == null || p is Map, isTrue);
        await expectLater(store.loadPrefsSettled(), completes);
        await store.savePrefs({'exportBg': false});
        await Storage.settleWrites();
        final back = jsonDecode(File('${root.path}/prefs.json').readAsStringSync()) as Map;
        expect(back['exportBg'], false);
      });
    });

    test('200 guardados en ráfaga con claves distintas: ninguno se pisa, en disco ni en loadPrefsSettled', () async {
      for (var i = 0; i < 200; i++) {
        store.savePrefs({'k$i': i});
      }
      final visto = await store.loadPrefsSettled();
      expect([for (var i = 0; i < 200; i++) visto!['k$i']], [for (var i = 0; i < 200; i++) i]);
      await Storage.settleWrites();
      final disco = jsonDecode(File('${root.path}/prefs.json').readAsStringSync()) as Map;
      expect(disco.length, 200, reason: 'faltan claves en el archivo');
      expect(root.listSync().where((e) => e.path.endsWith('.tmp')), isEmpty);
    });

    test('el mismo valor pisado muchas veces: gana el último', () async {
      for (var i = 0; i < 100; i++) {
        store.savePrefs({'x': i});
      }
      await Storage.settleWrites();
      expect((jsonDecode(File('${root.path}/prefs.json').readAsStringSync()) as Map)['x'], 99);
    });

    test('un valor que no se puede escribir (NaN, un objeto raro) no envenena las preferencias para siempre', () async {
      // savePrefs mete el valor en `_prefsSet` ANTES de codificar: como cada guardado escribe todo `_prefsSet`, el valor
      // malo hace fallar TODOS los guardados siguientes de la sesión (la tablet deja de recordar cualquier opción).
      await expectLater(store.savePrefs({'malo': double.nan}), throwsA(anything));
      await store.savePrefs({'bueno': 1});
      await Storage.settleWrites();
      final back = jsonDecode(File('${root.path}/prefs.json').readAsStringSync()) as Map;
      expect(back['bueno'], 1, reason: 'después de un valor malo ya no se guarda nada');
    });

    test('claves y valores raros (unicode, anidados, enormes) hacen ida y vuelta', () async {
      final p = {
        'ñandú': '😀',
        'a/b': {'x': [1, 2.5, null, true, 'z']},
        '': 'vacía',
        'largo': 'x' * 200000,
        'n': -0.0,
        'grande': 9007199254740993,
      };
      await store.savePrefs(p);
      await Storage.settleWrites();
      final back = await store.loadPrefs();
      expect(jsonEncode(back), jsonEncode(p));
    });
  });

  group('sync_state.json', () {
    // Si el estado de la sync se pierde o se rompe "no se pierde nada: la próxima pasada reconstruye todo".
    final rotos = <String, String?>{
      'borrado': null,
      'vacío': '',
      'cortado': '{"format":1,"base":{"index.json":{"md5":"ab',
      'tipos que no son': '{"base":5,"remote":[],"baseText":"x"}',
      'base con basura': '{"base":{"index.json":7},"remote":{"index.json":3}}',
      'una lista': '[]',
    };
    rotos.forEach((nombre, contenido) {
      test('estado $nombre: la sync no borra ni pierde nada, de ningún lado', () async {
        final d2 = await Directory.systemTemp.createTemp('apuntes_sync_state_b');
        addTearDown(() => d2.delete(recursive: true));
        final b = Storage(root: d2);
        await b.init();
        final remote = FakeRemoteStore();

        final nb = Notebook.create('N');
        nb.sheets.add(nb.newSheet());
        final doc = NotebookDoc(nb);
        doc.texts['t'] = TextBlock('t', 1, 44, 800, 'importante');
        await store.saveNotebook(doc);
        await store.saveIndex(NotesIndex(notebooks: [nb]));
        await SyncEngine(store, remote, account: 'a').sync();
        await SyncEngine(b, remote, account: 'a').sync();

        final f = store.syncFile(kSyncStateFile);
        if (contenido == null) {
          if (f.existsSync()) f.deleteSync();
        } else {
          f.writeAsStringSync(contenido);
        }
        final remotoAntes = {for (final p in remote.paths) p: remote.md5Of(p)};
        final localAntes = {
          for (final e in root.listSync(recursive: true).whereType<File>())
            if (isSyncPath(e.path.substring(root.path.length + 1)) && !e.path.endsWith('index.json')) e.path: e.readAsBytesSync().length
        };
        final rep = await SyncEngine(store, remote, account: 'a').sync();
        expect(rep.deletedLocal + rep.deletedRemote, 0, reason: 'con el estado perdido no se puede borrar nada');
        expect({for (final p in remote.paths) p: remote.md5Of(p)}.keys, containsAll(remotoAntes.keys), reason: 'se borró algo de la nube');
        final localDespues = {
          for (final e in root.listSync(recursive: true).whereType<File>())
            if (isSyncPath(e.path.substring(root.path.length + 1)) && !e.path.endsWith('index.json')) e.path: e.readAsBytesSync().length
        };
        expect(localDespues.keys, containsAll(localAntes.keys));
        // y el estado queda arreglado: la pasada siguiente ya no hace nada
        final rep2 = await SyncEngine(store, remote, account: 'a').sync();
        expect(rep2.nothingToDo, isTrue, reason: '$rep2');
      });
    });
  });
}
