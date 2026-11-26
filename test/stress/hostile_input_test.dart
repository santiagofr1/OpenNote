import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/data/vynote_file.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/sync/fake_remote_store.dart';
import 'package:apuntes/sync/sync_engine.dart';
import 'package:apuntes/sync/sync_paths.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stress.dart';

/// Entradas de afuera que no son de fiar: un `.vynote` armado a mano o roto, un `index.json` que llega de la nube, rutas
/// de sync, nombres de cuaderno raros. Invariantes: (1) NUNCA se lee, escribe ni borra nada fuera de la carpeta de datos;
/// (2) un archivo roto se rechaza con VynoteException (ninguna otra excepción) y no deja nada a medias en disco;
/// (3) cualquier nombre sobrevive a guardar y leer.
void main() {
  late Directory sandbox, root;
  late Storage store;

  setUpAll(() => Storage.useIsolates = false);
  tearDownAll(() => Storage.useIsolates = true);
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('apuntes_hostil');
    root = Directory('${sandbox.path}/datos')..createSync();
    store = Storage(root: root);
    await store.init();
  });
  tearDown(() async {
    await Storage.settleWrites();
    await sandbox.delete(recursive: true);
  });

  /// Lo que no es de la app: una carpeta VECINA a la de datos, con un archivo que no se puede tocar.
  File victim() {
    final d = Directory('${sandbox.path}/victima')..createSync();
    return File('${d.path}/precioso.txt')..writeAsStringSync('no me toques');
  }

  const noteRaw = {'bg': 'lined', 'paper': '#fffefb', 'spacing': 40.0, 'updated': 0, 'last': 0};

  group('ids que vienen del índice (de la nube o de un backup)', () {
    test('un cuaderno con id "../../victima" no permite borrar carpetas ajenas', () async {
      final v = victim();
      store.indexFile.writeAsStringSync(jsonEncode({
        'format': 3,
        'rev': 1,
        'notebooks': [
          {'id': '../../victima', 'name': 'trampa', ...noteRaw}
        ]
      }));
      final idx = await store.loadIndex();
      for (final nb in List.of(idx.notebooks)) {
        await store.deleteNotebook(idx, nb);
      }
      await Storage.settleWrites();
      expect(v.existsSync(), isTrue, reason: 'deleteNotebook borró una carpeta de afuera de los datos (removeNotebookFiles no valida el id)');
    });

    test('guardar un cuaderno con id "../../victima" o hoja "../../../escape" no escribe fuera de la carpeta', () async {
      final v = victim();
      final nb = Notebook('../../victima', 'trampa', sheets: [SheetMeta('../../../../../escape')]);
      final d = NotebookDoc(nb);
      d.texts['t'] = TextBlock('t', 1, 44, 800, 'x');
      try {
        await store.saveNotebook(d);
      } catch (_) {
        // rechazarlo está bien
      }
      await Storage.settleWrites();
      final afuera = sandbox.listSync(recursive: true).whereType<File>().where((f) => !f.path.startsWith(root.path)).map((f) => f.path).toList();
      expect(afuera, [v.path], reason: 'se escribieron archivos fuera de la carpeta de datos: $afuera');
    });

    test('el índice de la nube con ids de cuaderno con ".." no llega al disco local', () async {
      final v = victim();
      final remote = FakeRemoteStore();
      remote.put(
          'index.json',
          utf8.encode(jsonEncode({
            'format': 3,
            'rev': 1,
            'notebooks': [
              {'id': '../../victima', 'name': 'trampa', ...noteRaw},
              {'id': 'bueno', 'name': 'ok', ...noteRaw},
            ]
          })));
      await SyncEngine(store, remote, account: 'a').sync();
      final idx = await store.loadIndex();
      expect(idx.notebooks.where((n) => n.id.contains('..') || n.id.contains('/')), isEmpty,
          reason: 'la sync acepta cualquier contenido de index.json mientras tenga format 3');
      expect(v.existsSync(), isTrue);
    });

    test('item.file con ".." en una hoja no se exporta como "media/../index.json" (lee archivos de afuera de media/)', () async {
      final nb = Notebook.create('Con link malo');
      final d = NotebookDoc(nb);
      d.items['i'] = Item('i', 'image', 10, 10, 100, 100, file: '../index.json');
      await store.saveNotebook(d);
      await store.saveIndex(NotesIndex(notebooks: [nb]));
      final bytes = await exportNotebookBytes(store, nb);
      final names = ZipDecoder().decodeBytes(bytes).map((f) => f.name).toList();
      expect(names.where((n) => n.contains('..')), isEmpty, reason: 'el .vynote exportado se llevó un archivo de afuera de media/: $names');
    });
  });

  group('rutas de sync (propiedad sobre cadenas al azar)', () {
    test('toda ruta aceptada por isSyncPath cae DENTRO de la carpeta de datos y no tiene segmentos raros', () {
      final r = Random(5);
      const piezas = ['notebooks', 'sheets', 'media', 'templates', 'index.json', 'notebook.json', '..', '.', '', 'a', 'a.sheet', 'x.json', '%2e%2e', r'\', '..\\', 'é', '\n', ' ', 'a\u0000b', '😀', '-', '_x', '.hidden', 'a..b'];
      var aceptadas = 0;
      for (var i = 0; i < 20000; i++) {
        final n = 1 + r.nextInt(5);
        var p = [for (var k = 0; k < n; k++) piezas[r.nextInt(piezas.length)]].join('/');
        if (r.nextInt(6) == 0) p = '/$p';
        if (r.nextInt(6) == 0) p = '$p/';
        if (r.nextInt(8) == 0) p = '$p\n';
        if (!isSyncPath(p)) continue;
        aceptadas++;
        final segs = p.split('/');
        expect(segs.any((s) => s.isEmpty || s == '.' || s == '..'), isFalse, reason: 'aceptó "$p"');
        expect(p.contains(r'\') || p.contains('\n') || p.contains('\u0000') || p.startsWith('/'), isFalse, reason: 'aceptó "$p"');
        final resuelta = File('${root.path}/$p').absolute.uri.normalizePath().toFilePath();
        expect(resuelta.startsWith(root.absolute.uri.normalizePath().toFilePath()), isTrue, reason: 'escapa: "$p"');
      }
      expect(aceptadas, greaterThan(100), reason: 'el generador casi no produjo rutas válidas: la propiedad sería vacía');
    });

    test('rutas válidas conocidas siguen siéndolo (para que la propiedad de arriba no sea vacía por un regex roto)', () {
      for (final p in ['index.json', 'notebooks/n1/notebook.json', 'notebooks/n1/sheets/h1.sheet', 'media/m_ab12.png', 'templates/t1.json']) {
        expect(isSyncPath(p), isTrue, reason: p);
      }
    });
  });

  group('.vynote roto o armado a mano', () {
    late Uint8List good;
    Map<String, List<int>> parts() => {for (final f in ZipDecoder().decodeBytes(good)) f.name: f.readBytes()!};
    Uint8List zipOf(Map<String, List<int>> files) {
      final a = Archive();
      files.forEach((k, v) => a.add(ArchiveFile.bytes(k, v)));
      return Uint8List.fromList(ZipEncoder().encode(a));
    }

    int tree(Directory d) => d.listSync(recursive: true).length;

    setUp(() async {
      final nb = Notebook.create('Original');
      while (nb.sheets.length < 3) {
        nb.sheets.add(nb.newSheet());
      }
      final d = NotebookDoc(nb);
      final r = Random(1);
      for (var k = 0; k < 3; k++) {
        for (var i = 0; i < 4; i++) {
          final s = randomStroke(r, 's${k}_$i', yBase: k * kSheetStep, n: 10, jumps: false);
          d.strokes[s.id] = s;
        }
      }
      d.items['i'] = Item('i', 'image', 10, 10, 100, 100, file: 'm_foto.png');
      await store.media('m_foto.png').writeAsBytes([1, 2, 3, 4]);
      await store.saveNotebook(d);
      await store.saveIndex(NotesIndex(notebooks: [nb]));
      good = await exportNotebookBytes(store, nb);
    });

    /// Importa [b]: o devuelve un cuaderno, o VynoteException y el disco queda IGUAL que antes.
    Future<void> importa(Uint8List b, String reason) async {
      final before = tree(root);
      try {
        final nb = await importNotebookBytes(store, b, taken: {});
        expect(nb.sheets, isNotEmpty, reason: reason);
      } on VynoteException {
        await Storage.settleWrites();
        expect(tree(root), before, reason: '$reason: el rechazo dejó cosas en disco');
      }
    }

    test('cortado en 80 largos distintos: VynoteException (ninguna otra) y sin restos', () async {
      final r = Random(9);
      for (var i = 0; i < 80; i++) {
        final len = i < 5 ? i : r.nextInt(good.length);
        await importa(Uint8List.sublistView(good, 0, len), 'corte a $len de ${good.length}');
      }
    });

    test('300 bytes pisados al azar: VynoteException o cuaderno válido, nunca otra excepción', () async {
      final r = Random(10);
      for (var i = 0; i < 300; i++) {
        final b = Uint8List.fromList(good);
        for (var k = 0; k < 1 + r.nextInt(3); k++) {
          b[r.nextInt(b.length)] = r.nextInt(256);
        }
        await importa(b, 'iteración $i');
      }
    });

    test('entradas con "..", absolutas o con barras: no escriben fuera de la carpeta de datos', () async {
      final v = victim();
      final p = parts();
      for (final name in ['media/../../../victima/precioso.txt', 'media/..', '../../victima/x', '/abs/x', 'media/a/b.png', 'sheets/../../x.sheet', 'media/..\\x.png']) {
        final b = zipOf({...p, name: utf8.encode('PWNED')});
        await importa(b, name);
      }
      expect(v.readAsStringSync(), 'no me toques');
      final afuera = sandbox.listSync(recursive: true).whereType<File>().where((f) => !f.path.startsWith(root.path) && f.path != v.path);
      expect(afuera, isEmpty);
    });

    test('formato futuro, formato no entero y app distinta', () async {
      final p = parts();
      final m = jsonDecode(utf8.decode(p['manifest.json']!)) as Map;
      Future<VynoteError> kindOf(Map x) async {
        final b = zipOf({...p, 'manifest.json': utf8.encode(jsonEncode(x))});
        try {
          await importNotebookBytes(store, b, taken: {});
        } on VynoteException catch (e) {
          return e.kind;
        }
        fail('se importó un manifest ${jsonEncode(x)}');
      }

      expect(await kindOf({...m, 'format': kVynoteFormat + 1}), VynoteError.newerVersion);
      expect(await kindOf({...m, 'format': 1.5}), VynoteError.notVynote);
      expect(await kindOf({...m, 'format': '1'}), VynoteError.notVynote);
      expect(await kindOf({...m, 'app': 'Otra'}), VynoteError.notVynote);
    });

    test('un nombre de cuaderno de cualquier tipo en el manifest no rompe la importación', () async {
      final p = parts();
      final m = jsonDecode(utf8.decode(p['manifest.json']!)) as Map;
      for (final name in [...kNombresRaros, 5, null, [], {}]) {
        final b = zipOf({...p, 'manifest.json': utf8.encode(jsonEncode({...m, 'name': name}))});
        await importa(b, 'nombre ${jsonEncode(name)}');
      }
    });
  });

  group('nombres de cuaderno hostiles', () {
    test('index.json: cada nombre vuelve idéntico (unicode, emojis, "/", "..", vacío, 300 caracteres, NUL)', () async {
      final nbs = [for (final n in kNombresRaros) Notebook.create(n)];
      await store.saveIndex(NotesIndex(notebooks: nbs));
      await Storage.settleWrites();
      final s2 = Storage(root: root);
      await s2.init();
      final back = await s2.loadIndex();
      expect([for (final n in back.notebooks) n.name], kNombresRaros);
    });

    test('exportar a .vynote y volver a importar conserva el nombre (salvo recorte de espacios)', () async {
      for (final n in kNombresRaros) {
        final nb = Notebook.create(n);
        final d = NotebookDoc(nb);
        await store.saveNotebook(d);
        final b = await exportNotebookBytes(store, nb);
        final back = await importNotebookBytes(store, b, taken: {});
        expect(back.name, n.trim().isEmpty ? 'Cuaderno' : n.trim(), reason: 'nombre ${jsonEncode(n)}');
      }
    });
  });
}
