import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/domain.dart';
import 'migration.dart';
import 'sheet_codec.dart';

/// Guarda todo en archivos (formato 3):
///   `<dir>/index.json`                              cuadernos (sin sus hojas)
///   `<dir>/prefs.json`                              herramientas elegidas
///   `<dir>/notebooks/<id>/notebook.json`            orden y datos de las hojas
///   `<dir>/notebooks/<id>/sheets/<hoja>.sheet`      contenido de cada hoja (binario, ver [encodeSheet])
///   `<dir>/media/`                                  imágenes y audios (compartidos)
/// Al guardar solo se escriben las hojas que cambiaron.
class Storage {
  /// [root]: carpeta propia (los tests usan una temporal para no tocar tus cuadernos)
  Storage({this.root});
  final Directory? root;

  /// Codificar y decodificar hojas en otro isolate. Solo los tests de widgets lo apagan
  /// (Isolate.run no anda dentro del reloj falso de testWidgets).
  static bool useIsolates = true;
  late final Directory dir;

  // lo último que hay en disco de cada cuaderno, para guardar solo lo que cambió
  final _disk = <String, _DiskState>{};
  final _queues = <String, _SaveQueue>{};

  Future<void> init() async {
    dir = root ?? Directory('${(await _defaultBase()).path}/apuntes');
    await Directory('${dir.path}/notebooks').create(recursive: true);
    await Directory('${dir.path}/media').create(recursive: true);
  }

  /// En Android, la carpeta externa de la app (se puede respaldar por USB).
  static Future<Directory> _defaultBase() async {
    Directory? base;
    if (Platform.isAndroid) base = await getExternalStorageDirectory();
    return base ?? await getApplicationDocumentsDirectory();
  }

  File media(String name) => File('${dir.path}/media/$name');

  Future<String> addMedia(List<int> bytes, String ext) async {
    final name = '${newId('m')}.$ext';
    await media(name).writeAsBytes(bytes, flush: true);
    return name;
  }

  Future<String> addMediaFile(File src, String ext) async {
    final name = '${newId('m')}.$ext';
    await src.copy(media(name).path);
    return name;
  }

  File get indexFile => File('${dir.path}/index.json');
  File get _prefs => File('${dir.path}/prefs.json');
  Directory nbDir(String id) => Directory('${dir.path}/notebooks/$id');
  File _nbFile(String id) => File('${nbDir(id).path}/notebook.json');
  Directory _sheetsDir(String id) => Directory('${nbDir(id).path}/sheets');
  File sheetFile(String nbId, String sheetId) => File('${_sheetsDir(nbId).path}/$sheetId.sheet');

  // escrituras en curso por archivo: dos a la vez pisarían el mismo temporal
  final _writing = <String, Future<void>>{};

  /// Escribe a un temporal y renombra: si se corta a la mitad, el archivo viejo queda entero.
  /// Las escrituras al mismo archivo se hacen una después de la otra.
  Future<void> _writeBytes(File f, List<int> data) {
    final prev = _writing[f.path] ?? Future.value();
    final run = prev.catchError((_) {}).then((_) async {
      await f.parent.create(recursive: true);
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsBytes(data, flush: true);
      await tmp.rename(f.path);
    });
    _writing[f.path] = run;
    return run.whenComplete(() {
      if (identical(_writing[f.path], run)) _writing.remove(f.path);
    });
  }

  Future<void> _writeJson(File f, Object data) => _writeBytes(f, utf8.encode(jsonEncode(data)));

  // ================= índice =================
  /// Lee el índice. Si está en el formato viejo (páginas), lo convierte antes (ver [migrateLegacy]).
  Future<NotesIndex> loadIndex() async {
    Map? j;
    try {
      j = jsonDecode(await indexFile.readAsString()) as Map;
    } catch (_) {
      if (await indexFile.exists()) {
        // ilegible: se guarda aparte en vez de pisarlo con el cuaderno de ejemplo
        await indexFile.rename('${indexFile.path}.corrupto-${DateTime.now().millisecondsSinceEpoch}');
      }
    }
    if (j == null) {
      // primera vez: cuaderno de ejemplo
      final nb = Notebook.create('Mi cuaderno');
      final idx = NotesIndex(last: nb.id, notebooks: [nb]);
      await saveNotebook(NotebookDoc(nb));
      await saveIndex(idx);
      return idx;
    }
    if (j['format'] != Notebook.kFormat) return migrateLegacy(this, j);
    final idx = NotesIndex.fromJson(j);
    for (final nb in idx.notebooks) {
      await _readSheetList(nb);
    }
    await archiveLegacyPages(this); // por si la migración se cortó justo antes de mover `pages/`
    return idx;
  }

  Future<void> saveIndex(NotesIndex idx) {
    idx.rev++;
    return _writeJson(indexFile, idx.toJson());
  }

  /// Completa [nb].sheets con lo que dice su notebook.json (vacío si falta o está roto).
  Future<void> _readSheetList(Notebook nb) async {
    nb.sheets.clear();
    try {
      final j = jsonDecode(await _nbFile(nb.id).readAsString()) as Map;
      nb.sheets.addAll([for (final s in (j['sheets'] as List)) SheetMeta.fromJson(s as Map)]);
    } catch (_) {}
  }

  // ================= cuadernos =================
  /// Lee todas las hojas del cuaderno (decodificadas en otro isolate).
  /// Una hoja que falta o está rota queda vacía; la rota se aparta como `.roto` para no pisarla.
  Future<NotebookDoc> loadNotebook(Notebook nb) async {
    if (nb.sheets.isEmpty) await _readSheetList(nb);
    final raw = <Uint8List?>[];
    for (final s in nb.sheets) {
      final f = sheetFile(nb.id, s.id);
      raw.add(await f.exists() ? await f.readAsBytes() : null);
    }
    final decoded = await _decodeInIsolate(raw);
    final contents = <SheetContent>[];
    final hashes = <String, String>{};
    for (var k = 0; k < nb.sheets.length; k++) {
      final s = nb.sheets[k];
      final c = decoded[k];
      if (c != null) {
        contents.add(c);
        hashes[s.id] = _hash(raw[k]!);
      } else {
        contents.add(SheetContent());
        if (raw[k] != null) await sheetFile(nb.id, s.id).rename('${sheetFile(nb.id, s.id).path}.roto');
      }
    }
    final doc = NotebookDoc.fromSheets(nb, contents);
    _disk[nb.id] = _DiskState(hashes, jsonEncode(nb.sheetsJson()));
    await _sweep(nb);
    return doc;
  }

  /// Una sola hoja (miniatura de la biblioteca), sin tocar el resto del cuaderno.
  Future<NotebookDoc?> loadSheetDoc(Notebook nb, int index) async {
    if (index < 0 || index >= nb.sheets.length) return null;
    final meta = nb.sheets[index];
    try {
      final bytes = await sheetFile(nb.id, meta.id).readAsBytes();
      return NotebookDoc.single(meta, (await _decodeInIsolate([bytes])).single ?? SheetContent());
    } catch (_) {
      return NotebookDoc.single(meta, SheetContent());
    }
  }

  /// Guarda el cuaderno: codifica las hojas en otro isolate y escribe SOLO las que cambiaron
  /// (más notebook.json si cambió algún dato de las hojas). Los guardados de un mismo cuaderno
  /// se hacen de a uno; si llegan varios mientras se guarda, se juntan en uno solo.
  Future<void> saveNotebook(NotebookDoc doc) {
    final q = _queues.putIfAbsent(doc.id, _SaveQueue.new);
    if (q.running == null) return q.running = _drain(doc, q);
    q.waiting = doc;
    return (q.waiters ??= Completer<void>()).future;
  }

  Future<void> _drain(NotebookDoc doc, _SaveQueue q) async {
    try {
      await _saveNow(doc);
    } catch (e, st) {
      final w = q.waiters;
      q.waiters = null;
      q.waiting = null;
      q.running = null;
      w?.completeError(e, st);
      rethrow;
    }
    final next = q.waiting, w = q.waiters;
    q.waiting = null;
    q.waiters = null;
    if (next == null) {
      q.running = null;
      return;
    }
    // lo que se pidió mientras tanto: un guardado más, con el estado de ahora
    final again = q.running = _drain(next, q);
    again.then((_) => w?.complete(), onError: (Object e, StackTrace st) => w?.completeError(e, st));
    await again;
  }

  Future<void> _saveNow(NotebookDoc doc) async {
    final nb = doc.nb;
    final contents = doc.splitBySheet(); // copia lo que hay ahora: se puede seguir editando
    final sheets = List.of(nb.sheets);
    final encoded = await _encodeInIsolate(contents);
    final disk = _disk.putIfAbsent(nb.id, () => _DiskState({}, ''));
    final now = DateTime.now().millisecondsSinceEpoch;
    final written = <String, String>{};
    for (var k = 0; k < sheets.length; k++) {
      final m = sheets[k];
      final (bytes, hash) = encoded[k];
      if (disk.hashes[m.id] == hash && await sheetFile(nb.id, m.id).exists()) {
        written[m.id] = hash;
        continue;
      }
      m
        ..rev += 1
        ..updated = now;
      await _writeBytes(sheetFile(nb.id, m.id), bytes);
      written[m.id] = hash;
    }
    final metaJson = jsonEncode(nb.sheetsJson());
    if (metaJson != disk.meta || !await _nbFile(nb.id).exists()) {
      await _writeBytes(_nbFile(nb.id), utf8.encode(metaJson));
      disk.meta = metaJson;
    }
    // las hojas borradas, al final: si se corta antes, solo sobran archivos
    for (final gone in disk.hashes.keys.where((id) => !written.containsKey(id))) {
      final f = sheetFile(nb.id, gone);
      if (await f.exists()) await f.delete();
    }
    disk.hashes
      ..clear()
      ..addAll(written);
  }

  /// Borra los archivos sueltos de una hoja que ya no está en el cuaderno ni en el disco cache.
  Future<void> _sweep(Notebook nb) async {
    if (nb.sheets.isEmpty) return;
    final d = _sheetsDir(nb.id);
    if (!await d.exists()) return;
    final ids = {for (final s in nb.sheets) '${s.id}.sheet'};
    await for (final e in d.list()) {
      if (e is! File) continue;
      final name = e.uri.pathSegments.last;
      if (name.endsWith('.tmp') || (name.endsWith('.sheet') && !ids.contains(name))) await e.delete();
    }
  }

  /// Saca del disco todo lo de un cuaderno (después de esperar que termine de guardarse).
  Future<void> removeNotebookFiles(String id) async {
    await _queues[id]?.running?.catchError((_) {});
    _disk.remove(id);
    final d = nbDir(id);
    if (await d.exists()) await d.delete(recursive: true);
  }

  /// Borra el cuaderno (carpeta incluida) y lo saca del índice.
  Future<void> deleteNotebook(NotesIndex idx, Notebook nb) async {
    idx.notebooks.remove(nb);
    await saveIndex(idx);
    await removeNotebookFiles(nb.id);
  }

  // ================= preferencias =================
  Future<Map?> loadPrefs() async {
    try {
      return jsonDecode(await _prefs.readAsString()) as Map;
    } catch (_) {
      return null;
    }
  }

  Future<void> savePrefs(Map<String, dynamic> p) => _writeJson(_prefs, p);
}

Future<R> _compute<R>(R Function() f) => Storage.useIsolates ? Isolate.run(f) : Future.sync(f);

// Los isolates se lanzan desde funciones sueltas: así el mensaje no arrastra a la [Storage].
Future<List<SheetContent?>> _decodeInIsolate(List<Uint8List?> raw) => _compute(() => [
      for (final b in raw)
        if (b == null) null else _tryDecode(b)
    ]);

Future<List<(Uint8List, String)>> _encodeInIsolate(List<SheetContent> contents) => _compute(() => [
      for (final c in contents) _encodeHashed(c),
    ]);

(Uint8List, String) _encodeHashed(SheetContent c) {
  final b = encodeSheet(c);
  return (b, _hash(b));
}

SheetContent? _tryDecode(Uint8List b) {
  try {
    return decodeSheet(b);
  } on SheetFormatException {
    return null;
  }
}

String _hash(Uint8List b) => md5.convert(b).toString();

class _DiskState {
  final Map<String, String> hashes; // id de hoja → hash de su archivo
  String meta; // notebook.json como está escrito
  _DiskState(this.hashes, this.meta);
}

class _SaveQueue {
  Future<void>? running;
  NotebookDoc? waiting; // pedido mientras se guardaba
  Completer<void>? waiters;
}
