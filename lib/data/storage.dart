import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
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
///
/// Carga perezosa: [openNotebook] lee solo las hojas cercanas a la que se ve; [loadSheets] / [unloadSheets] cargan y
/// sueltan hojas mientras se scrollea. REGLA DE ORO: una hoja sin cargar NUNCA se escribe (su archivo en disco es la
/// verdad), y una hoja solo se suelta si lo que hay en memoria es lo mismo que hay en disco (misma huella de contenido).
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

  /// Solo para los tests: se llama con (id del cuaderno, id de la hoja) cada vez que se escribe un `.sheet`.
  void Function(String nbId, String sheetId)? onSheetWrite;

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
  /// Lee todas las hojas del cuaderno (decodificadas en otro isolate): todo queda cargado.
  /// Para duplicar, exportar y los tests; la app abre con [openNotebook].
  /// Una hoja que falta o está rota queda vacía; la rota se aparta como `.roto` para no pisarla.
  Future<NotebookDoc> loadNotebook(Notebook nb) async {
    if (nb.sheets.isEmpty) await _readSheetList(nb);
    return openNotebook(nb, radius: nb.sheets.length);
  }

  /// Abre el cuaderno leyendo notebook.json y SOLO las hojas de [around] - [radius] a [around] + [radius]
  /// (con [radius] negativo no carga ninguna). Las demás quedan sin cargar: se piden con [loadSheets].
  Future<NotebookDoc> openNotebook(Notebook nb, {int around = 0, int radius = 2}) async {
    if (nb.sheets.isEmpty) await _readSheetList(nb);
    final onDisk = {for (final s in nb.sheets) s.id};
    final doc = NotebookDoc.lazy(nb);
    // los hashes de las hojas sin cargar son desconocidos: no se tocan hasta leerlas
    _disk[nb.id] = _DiskState({}, jsonEncode(nb.sheetsJson()), onDisk);
    final n = nb.sheets.length;
    if (radius >= 0 && n > 0) {
      final from = (around - radius).clamp(0, n - 1), to = (around + radius).clamp(0, n - 1);
      await loadSheets(doc, [for (var k = from; k <= to; k++) nb.sheets[k].id]);
    }
    await _sweep(nb);
    return doc;
  }

  /// Carga de disco las hojas [ids] que no estén cargadas (leyendo y decodificando en otro isolate) y las pone en [doc].
  /// Devuelve los ids que cargó. Si falla la lectura no se carga NINGUNA (y se lanza el error): una hoja sin cargar
  /// no se pisa, pero una hoja "cargada vacía" por un error de lectura sí se guardaría vacía.
  Future<List<String>> loadSheets(NotebookDoc doc, Iterable<String> ids) async {
    final nb = doc.nb;
    final want = [
      for (final id in ids.toSet())
        if (!doc.isLoaded(id) && doc.indexOfSheet(id) >= 0) id
    ];
    if (want.isEmpty) return [];
    final raw = <Uint8List?>[];
    final tRead = developer.TimelineTask()..start('ON loadSheets leer disco', arguments: {'hojas': want.length});
    try {
      for (final id in want) {
        final f = sheetFile(nb.id, id);
        raw.add(await f.exists() ? await f.readAsBytes() : null);
      }
    } catch (_) {
      if (want.every((id) => doc.indexOfSheet(id) < 0)) return []; // se borraron mientras tanto
      rethrow;
    } finally {
      tRead.finish();
    }
    final tDec = developer.TimelineTask()..start('ON loadSheets decodificar (isolate)', arguments: {'hojas': want.length});
    final List<(SheetContent, String)?> decoded;
    try {
      decoded = await _decodeDigestInIsolate(raw);
    } finally {
      tDec.finish();
    }
    final state = _disk.putIfAbsent(nb.id, () => _DiskState({}, '', {for (final s in nb.sheets) s.id}));
    final done = <String>[];
    for (var i = 0; i < want.length; i++) {
      final id = want[i];
      if (doc.isLoaded(id) || doc.indexOfSheet(id) < 0) continue; // otro la cargó, o se borró: no se pisa nada
      final c = decoded[i]?.$1;
      if (c == null && raw[i] != null) {
        final f = sheetFile(nb.id, id);
        if (await f.exists()) await f.rename('${f.path}.roto');
      }
      if (doc.isLoaded(id) || doc.indexOfSheet(id) < 0) continue; // (el rename esperó)
      if (doc.attachSheet(id, c ?? SheetContent())) {
        if (c != null) {
          state.hashes[id] = _hash(raw[i]!);
          state.digests[id] = decoded[i]!.$2;
        }
        done.add(id);
      }
    }
    return done;
  }

  /// Suelta de memoria las hojas [ids] cargadas. Solo suelta una hoja si TODO esto se cumple:
  /// no hay un guardado en curso, no tiene cambios sin guardar, se conoce su archivo en disco, [canUnload] lo permite
  /// y el contenido en memoria tiene la misma huella ([sheetDigest]) que el archivo (si no, se la marca sucia para que se guarde:
  /// va en [healed], hay que pedir un guardado). Lo que no se suelta queda cargado.
  Future<({List<String> unloaded, List<String> healed})> unloadSheets(NotebookDoc doc, Iterable<String> ids,
      {bool Function(String id)? canUnload}) async {
    final nb = doc.nb;
    final unloaded = <String>[], healed = <String>[];
    await _idle(nb.id);
    final state = _disk[nb.id];
    bool ok(String id) =>
        doc.isLoaded(id) && !doc.isSheetDirty(id) && state != null && state.hashes.containsKey(id) && state.digests.containsKey(id) && (canUnload?.call(id) ?? true);
    final cand = [for (final id in ids.toSet()) if (ok(id)) id];
    if (state == null || cand.isEmpty) return (unloaded: unloaded, healed: healed);
    final contents = developer.Timeline.timeSync('ON unloadSheets splitSheets', () => doc.splitSheets(cand.toSet()));
    final tDig = developer.TimelineTask()..start('ON unloadSheets huella (isolate)', arguments: {'hojas': cand.length});
    final List<String> digests;
    try {
      digests = await _digestInIsolate([for (final id in cand) contents[id]!]);
    } finally {
      tDig.finish();
    }
    for (var i = 0; i < cand.length; i++) {
      final id = cand[i];
      // desde acá todo es sincrónico: lo que se chequea es lo que vale al soltar
      if (_queues[nb.id]?.running != null) continue; // empezó un guardado mientras se codificaba: otra vez será
      if (!ok(id)) continue;
      if (state.digests[id] != digests[i]) {
        developer.log('la hoja $id en memoria no es igual a su archivo: se marca para guardar y no se suelta', name: 'storage');
        doc.markDirtySheet(doc.indexOfSheet(id));
        healed.add(id);
        continue;
      }
      if (doc.detachSheet(id)) unloaded.add(id);
    }
    return (unloaded: unloaded, healed: healed);
  }

  /// Espera a que no haya ningún guardado en curso de ese cuaderno.
  Future<void> _idle(String nbId) async {
    while (true) {
      final r = _queues[nbId]?.running;
      if (r == null) return;
      try {
        await r;
      } catch (_) {}
    }
  }

  /// Copia los archivos de las hojas de [src] a [copy] (con sus mismas hojas y ids) sin cargar nada.
  Future<void> copyNotebookFiles(Notebook src, Notebook copy) async {
    await _idle(src.id);
    if (src.sheets.isEmpty) await _readSheetList(src);
    for (final m in src.sheets) {
      final from = sheetFile(src.id, m.id);
      if (!await from.exists()) continue;
      final to = sheetFile(copy.id, m.id);
      await to.parent.create(recursive: true);
      final tmp = File('${to.path}.tmp');
      await from.copy(tmp.path);
      await tmp.rename(to.path);
    }
    await _writeJson(_nbFile(copy.id), copy.sheetsJson());
  }

  /// Espera a que termine el guardado en curso de [nbId] (para leer sus archivos al exportar).
  Future<void> settle(String nbId) => _idle(nbId);

  /// Escribe en disco un cuaderno que viene de afuera (importar un `.opennote`): los archivos de las hojas tal cual
  /// ([sheetFiles]: id de hoja → bytes) y su notebook.json. Si algo falla borra lo escrito.
  Future<void> writeImportedNotebook(Notebook nb, Map<String, Uint8List> sheetFiles) async {
    try {
      for (final e in sheetFiles.entries) {
        await _writeBytes(sheetFile(nb.id, e.key), e.value);
      }
      await _writeJson(_nbFile(nb.id), nb.sheetsJson());
    } catch (_) {
      await removeNotebookFiles(nb.id);
      rethrow;
    }
  }

  /// El contenido de la hoja [m] leído de disco, sin tocar ningún documento (vacío si falta o está rota).
  Future<SheetContent> readSheetContent(Notebook nb, SheetMeta m) async {
    final f = sheetFile(nb.id, m.id);
    if (!await f.exists()) return SheetContent();
    return (await _decodeInIsolate([await f.readAsBytes()])).single ?? SheetContent();
  }

  /// Los textos y notas de la hoja [m] leyéndola de disco (en otro isolate), sin dejarla en memoria. Para buscar
  /// en las hojas sin cargar. `y` es local a la hoja.
  Future<List<SheetText>> readSheetTexts(Notebook nb, SheetMeta m) async {
    final f = sheetFile(nb.id, m.id);
    if (!await f.exists()) return [];
    final bytes = await f.readAsBytes();
    return _compute(() => _textsOf(bytes));
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

  /// Guarda el cuaderno: codifica en otro isolate SOLO las hojas sucias (ver [NotebookDoc.takeDirty]) y escribe
  /// las que cambiaron (más notebook.json si cambió algún dato de las hojas). Los guardados de un mismo cuaderno
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
    // lo sucio se toma y se copia SIN esperar nada en el medio: lo que se edite desde ahora
    // se marca de nuevo y queda para el próximo guardado
    final taken = doc.takeDirty();
    try {
      final sheets = List.of(nb.sheets);
      final disk = _disk[nb.id];
      final loaded = doc.loadedSheets;
      // sin estado en disco (primer guardado) o todo sucio: se guardan todas las CARGADAS.
      // Si no, las sucias y las que nunca se escribieron (hojas nuevas, o una rota que se apartó).
      // Las hojas sin cargar NUNCA entran: su archivo es la verdad y no hay nada en memoria para escribir.
      final ids = <String>{
        for (final m in sheets)
          if (loaded.contains(m.id) && (disk == null || taken.all || taken.ids.contains(m.id) || !disk.hashes.containsKey(m.id)))
            m.id
      };
      assert(ids.every(loaded.contains), 'se intenta guardar una hoja sin cargar');
      final contents = doc.splitSheets(ids); // copia solo esas hojas: se puede seguir editando
      final order = [for (final m in sheets) if (ids.contains(m.id) && contents.containsKey(m.id)) m];
      final encoded = await _encodeInIsolate([for (final m in order) contents[m.id]!]);
      final state = _disk.putIfAbsent(nb.id, () => _DiskState({}, '', {}));
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var k = 0; k < order.length; k++) {
        final m = order[k];
        final (bytes, hash, digest) = encoded[k];
        if (!doc.isLoaded(m.id)) {
          developer.log('NO se escribe la hoja ${m.id}: no está cargada', name: 'storage', level: 1000);
          continue;
        }
        if (state.hashes[m.id] == hash && await sheetFile(nb.id, m.id).exists()) {
          state.digests[m.id] = digest;
          continue;
        }
        m
          ..rev += 1
          ..updated = now;
        await _writeBytes(sheetFile(nb.id, m.id), bytes);
        onSheetWrite?.call(nb.id, m.id);
        state.hashes[m.id] = hash;
        state.digests[m.id] = digest; // ya está en disco: si algo falla más adelante, el hash es el cierto
      }
      final metaJson = jsonEncode(nb.sheetsJson());
      if (metaJson != state.meta || !await _nbFile(nb.id).exists()) {
        await _writeBytes(_nbFile(nb.id), utf8.encode(metaJson));
        state.meta = metaJson;
      }
      // las hojas borradas, al final: si se corta antes, solo sobran archivos
      // (también las que no estaban cargadas: su archivo se conoce por notebook.json)
      final alive = {for (final m in sheets) m.id};
      for (final gone in {...state.onDisk, ...state.hashes.keys}.where((id) => !alive.contains(id)).toList()) {
        final f = sheetFile(nb.id, gone);
        if (await f.exists()) await f.delete();
        state.hashes.remove(gone);
        state.digests.remove(gone);
      }
      state.onDisk = alive;
    } catch (_) {
      doc.restoreDirty(taken); // no se guardó: sigue sucio
      rethrow;
    }
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

  /// Mezcla [p] con lo que ya hay: así las herramientas y las opciones de actualización
  /// (que se guardan por separado) no se pisan entre sí.
  Future<void> savePrefs(Map<String, dynamic> p) async {
    final prev = await loadPrefs();
    await _writeJson(_prefs, {...?prev?.cast<String, dynamic>(), ...p});
  }
}

Future<R> _compute<R>(R Function() f) => Storage.useIsolates ? Isolate.run(f) : Future.sync(f);

// Los isolates se lanzan desde funciones sueltas: así el mensaje no arrastra a la [Storage].
Future<List<SheetContent?>> _decodeInIsolate(List<Uint8List?> raw) => _compute(() => [
      for (final b in raw)
        if (b == null) null else _tryDecode(b)
    ]);

/// Decodifica y saca la huella del contenido de cada hoja.
Future<List<(SheetContent, String)?>> _decodeDigestInIsolate(List<Uint8List?> raw) => _compute(() => [
      for (final b in raw)
        if (b == null) null else _tryDecodeDigest(b)
    ]);

(SheetContent, String)? _tryDecodeDigest(Uint8List b) {
  final c = _tryDecode(b);
  if (c == null) return null;
  // las mallas de los trazos se arman acá, fuera del hilo de la UI (los buffers viajan sin copiarse)
  for (final s in c.strokes) {
    s.mesh = buildStrokeMesh(s);
  }
  return (c, sheetDigest(c));
}

Future<List<String>> _digestInIsolate(List<SheetContent> contents) => _compute(() => [for (final c in contents) sheetDigest(c)]);

/// (bytes, hash de los bytes, huella del contenido)
Future<List<(Uint8List, String, String)>> _encodeInIsolate(List<SheetContent> contents) => _compute(() => [
      for (final c in contents) _encodeHashed(c),
    ]);

(Uint8List, String, String) _encodeHashed(SheetContent c) {
  final b = encodeSheet(c);
  return (b, _hash(b), sheetDigest(c));
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
  final Map<String, String> hashes; // id de hoja → hash de su archivo (solo las hojas cuyo archivo se leyó o escribió)
  final digests = <String, String>{}; // id de hoja → huella de su contenido en disco (ver [sheetDigest])
  String meta; // notebook.json como está escrito
  Set<String> onDisk; // ids de las hojas que figuran en el notebook.json de disco (aunque no estén cargadas)
  _DiskState(this.hashes, this.meta, this.onDisk);
}

/// Un texto o nota de una hoja leída de disco (ver [Storage.readSheetTexts]).
typedef SheetText = ({String id, double y, String text, bool sticky});

List<SheetText> _textsOf(Uint8List b) {
  final c = _tryDecode(b);
  if (c == null) return [];
  return [
    for (final t in c.texts) (id: t.id, y: t.y, text: t.text, sticky: false),
    for (final it in c.items)
      if (it.type == 'sticky') (id: it.id, y: it.y, text: it.text, sticky: true),
  ];
}

class _SaveQueue {
  Future<void>? running;
  NotebookDoc? waiting; // pedido mientras se guardaba
  Completer<void>? waiters;
}
