import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:apuntes/data/media_import.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/sync/drive_remote_store.dart';
import 'package:apuntes/sync/fake_remote_store.dart';
import 'package:apuntes/sync/sync_engine.dart';
import 'package:apuntes/sync/sync_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Imágenes y audios (`media/`) en la sincronización: de dónde salen los nombres, qué se sube y cómo (issue #11b).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final realAudioPicker = Pickers.audio, realLength = Pickers.audioLength;
  setUp(() => Pickers.audioLength = (_) async => 1500);
  setUpAll(() => Storage.useIsolates = false);
  tearDownAll(() => Storage.useIsolates = true);

  final dirs = <Directory>[];
  tearDown(() {
    for (final d in dirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    dirs.clear();
    Pickers.audio = realAudioPicker;
    Pickers.audioLength = realLength;
  });

  Future<Storage> device() async {
    final d = await Directory.systemTemp.createTemp('apuntes_media');
    dirs.add(d);
    final s = Storage(root: d);
    await s.init();
    return s;
  }

  Future<File> fileAt(String relDir, String name, List<int> bytes) async {
    final base = await Directory.systemTemp.createTemp('apuntes_pick');
    dirs.add(base);
    final d = Directory('${base.path}/$relDir')..createSync(recursive: true);
    return File('${d.path}/$name')..writeAsBytesSync(bytes);
  }

  Future<void> notebookWith(Storage s, Item it) async {
    final nb = Notebook.create('Con audio');
    final d = NotebookDoc(nb);
    d.items[it.id] = it;
    nb.touch();
    await s.saveNotebook(d);
    final idx = NotesIndex()..notebooks.add(nb);
    await s.saveIndex(idx);
  }

  group('nombres de los archivos de media', () {
    // Causa 1: la extensión salía de lo que viniera después del último punto de la RUTA entera. Con un nombre sin
    // extensión dentro de una carpeta con punto (el paquete de Android es `io.github.santiagofr1.vynote`), o con espacios, el
    // archivo quedaba con un nombre que el motor no reconoce (silenciosamente no se sube) o directamente no se copiaba.
    final raros = {
      'sin extensión, carpeta con punto': ('io.github.santiagofr1.vynote/cache/file_picker/17000', 'Nota de voz'),
      'extensión con espacio': ('cache', 'clase.m4a copia'),
      'fecha con puntos y letras': ('cache', 'Grabación 21.11.2026 de la mañana'),
      'extensión en mayúsculas': ('cache', 'CLASE.M4A'),
    };
    for (final e in raros.entries) {
      test('audio elegido: ${e.key} se sincroniza a la nube', () async {
        final a = await device(), r = FakeRemoteStore();
        final src = await fileAt(e.value.$1, e.value.$2, List.generate(2048, (i) => i % 251));
        Pickers.audio = () async => src;
        final it = await makeAudioFileItem(a);
        expect(it, isNotNull);
        expect(isSyncPath('media/${it!.file}'), isTrue, reason: 'el nombre ${it.file} tiene que ser sincronizable');
        await notebookWith(a, it);
        final rep = await SyncEngine(a, r, account: 'a@b.c').sync();
        expect(rep.errors, isEmpty);
        expect(r.has('media/${it.file}'), isTrue, reason: 'el audio ${it.file} nunca llegó a la nube');
        expect(r.bytesOf('media/${it.file}'), List.generate(2048, (i) => i % 251));
      });
    }

    test('mediaExt: solo letras y números, corto, y si no sirve usa el de respaldo', () {
      expect(mediaExt('/a/b/clase.MP3', 'm4a'), 'mp3');
      expect(mediaExt('/a.b/c/audio', 'm4a'), 'm4a');
      expect(mediaExt('/a/b/x.m4a copia', 'm4a'), 'm4a');
      expect(mediaExt('/a/b/x.', 'm4a'), 'm4a');
      expect(mediaExt('/a/b/x.abcdefghijkl', 'm4a'), 'm4a');
    });
  });

  group('archivos a medio escribir', () {
    test('un temporal de grabación no se sincroniza; al renombrarlo a .m4a sí', () async {
      final a = await device(), r = FakeRemoteStore();
      await notebookWith(a, Item('i1', 'audio', 0, 0, 360, 64, file: 'mgrab.m4a'));
      await File('${a.dir.path}/media/mgrab.m4a.tmp').writeAsBytes([1, 2, 3]);
      expect(isSyncPath('media/mgrab.m4a.tmp'), isFalse);
      await SyncEngine(a, r, account: 'a@b.c').sync();
      expect(r.has('media/mgrab.m4a.tmp'), isFalse);
      expect(r.has('media/mgrab.m4a'), isFalse);
      await File('${a.dir.path}/media/mgrab.m4a.tmp').rename('${a.dir.path}/media/mgrab.m4a');
      await SyncEngine(a, r, account: 'a@b.c').sync();
      expect(r.has('media/mgrab.m4a'), isTrue);
    });

    test('addMedia / addMediaFile no dejan temporales (se escribe aparte y se renombra)', () async {
      final a = await device();
      final src = await fileAt('x', 'a.mp3', List.filled(4096, 7));
      final n1 = await a.addMedia(List.filled(4096, 1), 'jpg'), n2 = await a.addMediaFile(src, 'mp3');
      expect(a.media(n1).readAsBytesSync(), hasLength(4096));
      expect(a.media(n2).readAsBytesSync(), hasLength(4096));
      expect(Directory('${a.dir.path}/media').listSync().where((e) => e.path.endsWith('.tmp')), isEmpty);
    });

    test('un archivo que sigue creciendo (grabación) se vuelve a subir sin conflicto', () async {
      final a = await device(), r = FakeRemoteStore();
      await notebookWith(a, Item('i1', 'audio', 0, 0, 360, 64, file: 'mgrow.m4a'));
      final f = a.media('mgrow.m4a')..writeAsBytesSync(List.filled(100, 1));
      await SyncEngine(a, r, account: 'a@b.c').sync();
      for (var i = 0; i < 3; i++) {
        f.writeAsBytesSync([...f.readAsBytesSync(), ...List.filled(100, 2 + i)]);
        final rep = await SyncEngine(a, r, account: 'a@b.c').sync();
        expect(rep.errors, isEmpty, reason: rep.toString());
        expect(r.bytesOf('media/mgrow.m4a'), f.readAsBytesSync());
      }
    });
  });

  group('Drive: subida de archivos grandes', () {
    /// Drive falso que anota cómo se subió cada archivo (uploadType y bytes recibidos).
    (http.Client, List<({String type, int bytes})>) drive() {
      final uploads = <({String type, int bytes})>[];
      var n = 0, got = 0, total = 0;
      http.Response json(Object o) => http.Response(jsonEncode(o), 200, headers: {'content-type': 'application/json'});
      Map file(String name, {bool folder = false}) => {
            'id': 'id${n++}',
            'name': name,
            'mimeType': folder ? 'application/vnd.google-apps.folder' : 'application/octet-stream',
            if (!folder) 'md5Checksum': 'abc',
            'modifiedTime': '2026-11-21T10:00:00.000Z',
            'createdTime': '2026-11-21T09:00:00.000Z',
          };
      final c = MockClient((req) async {
        final p = req.url.path;
        if (p.endsWith('/changes/startPageToken')) return json({'startPageToken': 'T1'});
        if (req.method == 'GET' && p.endsWith('/files')) return json({'files': []});
        if (req.method == 'POST' && p == '/drive/v3/files') {
          final b = jsonDecode(req.body) as Map;
          return json(file(b['name'] as String, folder: b['mimeType'] == 'application/vnd.google-apps.folder'));
        }
        if (p.endsWith('/upload/drive/v3/files') && req.method == 'POST') {
          final type = req.url.queryParameters['uploadType']!;
          if (type == 'resumable') {
            got = 0;
            total = int.parse(req.headers['x-upload-content-length'] ?? '0');
            return http.Response('', 200, headers: {'location': 'https://www.googleapis.com/upload/drive/v3/files?upload_id=u1'});
          }
          uploads.add((type: type, bytes: req.bodyBytes.length));
          return json(file('m.bin'));
        }
        if (req.method == 'PUT' && req.url.queryParameters['upload_id'] == 'u1') {
          got += req.bodyBytes.length;
          if (got < total) return http.Response('', 308, headers: {'range': 'bytes=0-${got - 1}'});
          uploads.add((type: 'resumable', bytes: got));
          return json(file('m.bin'));
        }
        return http.Response('{}', 404);
      });
      return (c, uploads);
    }

    test('un archivo de más de 5 MB (audio importado, foto grande) se sube con subida reanudable', () async {
      final (c, uploads) = drive();
      final store = DriveRemoteStore(c, rootName: 'Vynote');
      final big = Uint8List(6 * 1024 * 1024)..fillRange(0, 6 * 1024 * 1024, 9);
      await store.upload('media/mbig.mp3', big);
      expect(uploads, hasLength(1));
      expect(uploads.single.type, 'resumable', reason: 'multipart junta todo en un solo POST: se corta con archivos grandes');
      expect(uploads.single.bytes, big.length);
    });

    test('uno chico sigue yendo en un solo pedido (multipart)', () async {
      final (c, uploads) = drive();
      final store = DriveRemoteStore(c, rootName: 'Vynote');
      await store.upload('media/mchico.jpg', Uint8List(100 * 1024));
      expect(uploads.single.type, 'multipart');
    });
  });
}
