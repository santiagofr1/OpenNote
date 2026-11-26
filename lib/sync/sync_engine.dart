import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:crypto/crypto.dart';

import '../data/sheet_codec.dart';
import '../data/storage.dart';
import '../domain/domain.dart';
import 'remote_store.dart';
import 'sync_merge.dart';
import 'sync_paths.dart';
import 'sync_state.dart';

/// Lo que pasó en una pasada.
class SyncReport {
  int uploaded = 0, downloaded = 0, deletedLocal = 0, deletedRemote = 0, conflicts = 0, skipped = 0;
  final errors = <String>[];

  /// Cuadernos que se saltearon porque estaban abiertos en el editor.
  final skippedBusy = <String>[];

  /// Cuadernos abiertos en el editor que tienen cambios de la nube sin aplicar (el motor no escribe en un cuaderno
  /// abierto: solo sube lo suyo). Se aplican al cerrarlo o con "Actualizar".
  final remoteWaiting = <String>{};

  /// Cambió algo del disco local: la biblioteca tiene que volver a leer el índice.
  bool localChanged = false;

  /// Se escribió `index.json` local.
  bool indexChanged = false;
  bool get ok => errors.isEmpty;
  bool get nothingToDo => ok && uploaded + downloaded + deletedLocal + deletedRemote + conflicts == 0;
  bool get changedRemote => uploaded + deletedRemote > 0;
  @override
  String toString() =>
      'SyncReport(subidos $uploaded, bajados $downloaded, borrados local $deletedLocal / nube $deletedRemote, '
      'conflictos $conflicts, saltados $skipped, errores $errors)';
}

class _Skip implements Exception {
  const _Skip();
}

/// Una pasada completa de sincronización entre una [Storage] (disco local) y un [RemoteStore]. No sabe de Google.
///
/// Por cada archivo (ver sync_paths.dart) se compara el hash local, el hash remoto y la BASE (el hash de la última
/// versión que quedó igual en los dos lados, en sync_state.json). Cambió un solo lado: se copia al otro. Cambiaron los
/// dos: en una hoja queda la local y la remota se agrega como hoja nueva "(conflicto)" justo después; en
/// `notebook.json` e `index.json` se fusionan (sync_merge.dart). Un archivo que falta de un lado y está en la base se
/// borró en ese lado: se borra del otro si no cambió (si cambió, editar le gana a borrar y se vuelve a subir/bajar).
///
/// Orden: medios, hojas, notebook.json, index.json y al final los borrados: si se corta a la mitad nunca queda un
/// índice que apunte a algo que todavía no llegó. El estado se guarda después de CADA archivo y todo lo local se
/// escribe de forma atómica, así que repetir la pasada converge (es idempotente).
///
/// REGLA DE ORO: en un cuaderno abierto en el editor ([openNotebooks]) el motor NUNCA escribe ni borra archivos locales
/// (la memoria del editor los pisaría). Lo único que hace ahí es SUBIR: una hoja o `notebook.json` que cambió acá
/// (lo guardado en disco es consistente: la escritura es atómica) mientras la nube sigue en la base. Si la nube
/// también cambió (o borró) algo de ese cuaderno, queda sin aplicar y se anota en [SyncReport.remoteWaiting]: se
/// aplica al cerrarlo o con "Actualizar" (ver `docs/SYNC.md`). Con algún cuaderno abierto `index.json` también
/// es solo-subida (la biblioteca lo tiene en memoria). Lo abierto se consulta en cada archivo, no al empezar.
class SyncEngine {
  SyncEngine(this.store, this.remote, {Set<String> Function()? busy, this.account = ''})
      : openNotebooks = busy ?? (() => const {});
  final Storage store;
  final RemoteStore remote;
  final Set<String> Function() openNotebooks;

  /// Identifica la cuenta; si cambia respecto de la última pasada se empieza de cero.
  final String account;

  Future<SyncReport>? _current;
  bool get running => _current != null;

  late SyncState _st;
  late SyncReport _rep;
  final _active = <String>{}; // cuadernos con alguna hoja subida/bajada en esta pasada
  final _kept = <String>{}; // cuadernos salvados de un borrado porque se editaron del otro lado
  final _deferred = <(String, bool)>[]; // (ruta, true = borrar local / false = borrar remoto)
  bool _upOnly = false; // el archivo que se está procesando es de un cuaderno abierto: solo se sube

  /// Corre una pasada (si ya hay una en curso devuelve esa). Si el remoto falla del todo (sin red, sesión vencida)
  /// guarda el error en el estado y lo relanza ([RemoteException]); los errores de un solo archivo van a `errors`.
  Future<SyncReport> sync() => _current ??= _pass().whenComplete(() => _current = null);

  Future<SyncReport> _pass() async {
    _st = await SyncState.load(store);
    if (_st.account != account) _st = SyncState()..account = account;
    _rep = SyncReport();
    _active.clear();
    _kept.clear();
    _deferred.clear();
    try {
      final ch = await remote.changes(_st.token);
      if (ch.full) {
        _st.remote.clear();
        // La carpeta de la nube apareció vacía habiendo cosas sincronizadas: la borraron, no hay que borrar acá.
        if (!ch.files.any((f) => isSyncPath(f.path)) && _st.base.isNotEmpty) {
          _st.base.clear();
          _st.baseText.clear();
        }
      }
      for (final f in ch.files) {
        if (isSyncPath(f.path)) _st.remote[f.path] = f.md5;
      }
      for (final p in ch.removed) {
        _st.remote.remove(p);
      }
      _st.token = ch.nextToken;
      _st.lastAttempt = DateTime.now().millisecondsSinceEpoch;
      await _st.save(store);

      await _dropUntouchedSample();

      final paths = <String>{..._st.base.keys, ..._st.remote.keys, ...await _localPaths()}.where(isSyncPath).toList();
      int order(String p) => switch (syncKind(p)!) {
            SyncKind.media => 0,
            SyncKind.template => 1, // después de la media: la imagen llega antes que la plantilla que la usa
            SyncKind.sheet => 2,
            SyncKind.notebook => 3,
            SyncKind.indexFile => 4,
          };
      paths.sort((a, b) => order(a) != order(b) ? order(a).compareTo(order(b)) : a.compareTo(b));
      for (final p in paths) {
        final nb = notebookIdOf(p);
        final open = openNotebooks();
        _upOnly = (nb != null && open.contains(nb)) || (p == 'index.json' && open.isNotEmpty);
        try {
          switch (syncKind(p)!) {
            case SyncKind.media:
            case SyncKind.template:
            case SyncKind.sheet:
              await _opaque(p);
            case SyncKind.notebook:
              await _json(p, (b, l, r) => mergeNotebookJson(b, l, r), validNotebook);
            case SyncKind.indexFile:
              await _json(p, (b, l, r) => mergeIndexJson(b, l, r, keep: _kept), validIndex);
          }
        } on _Skip {
          _rep.skipped++;
          if (nb != null && openNotebooks().contains(nb)) _wait(p);
        } on RemoteOfflineException {
          rethrow;
        } on RemoteAuthException {
          rethrow;
        } catch (e) {
          _rep.errors.add('$p: $e');
          if (e is RemoteConflictException) _st.token = null; // lo que sabemos de la nube está desfasado: listado completo
        }
        await _st.save(store);
      }
      await _runDeferred();
      if (_rep.ok) {
        _st.lastSync = DateTime.now().millisecondsSinceEpoch;
        _st.lastError = null;
      } else {
        _st.lastError = _rep.errors.isEmpty ? null : _rep.errors.first;
      }
    } catch (e) {
      _st.lastError = e is RemoteException ? e.message : '$e';
      await _st.save(store);
      if (e is RemoteException) rethrow;
      throw RemoteException('$e');
    }
    await _st.save(store);
    return _rep;
  }

  /// Primera sincronización de este dispositivo (sin base) y la nube ya tiene cuadernos: el cuaderno de ejemplo
  /// "Mi cuaderno" que crea cada instalación al primer arranque, si sigue intacto (una sola hoja vacía), se descarta acá
  /// en vez de subirlo (si no, quedarían dos "Mi cuaderno"). Se borra de disco sin lápida: la nube nunca lo tuvo.
  Future<void> _dropUntouchedSample() async {
    if (_st.base.isNotEmpty || !_st.remote.containsKey('index.json')) return;
    try {
      final idxFile = store.syncFile('index.json');
      if (!await idxFile.exists()) return;
      final local = jsonDecode(await idxFile.readAsString()) as Map;
      final nbs = local['notebooks'];
      if (nbs is! List || nbs.length != 1 || (local['folders'] as List? ?? const []).isNotEmpty) return;
      final n = nbs.single as Map;
      final id = n['id'] as String;
      if (!kSampleNotebookNames.contains(n['name']) || n['folder'] != null || n['pin'] != null || openNotebooks().contains(id)) return;
      // la nube tiene que tener algún cuaderno
      final remoteIdx = jsonDecode(utf8.decode(await remote.download('index.json'))) as Map;
      if (remoteIdx['notebooks'] is! List || (remoteIdx['notebooks'] as List).isEmpty) return;
      // intacto: una hoja y sin nada escrito
      final nj = store.syncFile(notebookJsonPath(id));
      if (await nj.exists()) {
        final sheets = (jsonDecode(await nj.readAsString()) as Map)['sheets'] as List;
        if (sheets.length != 1) return;
        final f = store.syncFile(sheetPath(id, (sheets.single as Map)['id'] as String));
        if (await f.exists() && !decodeSheet(await f.readAsBytes()).isEmpty) return;
      }
      local['notebooks'] = [];
      if (local['last'] == id) local['last'] = null;
      await store.writeSyncFile('index.json', utf8.encode(jsonEncode(local)));
      await store.removeNotebookFiles(id);
      _rep.localChanged = true;
      _rep.indexChanged = true;
    } on RemoteException {
      rethrow;
    } catch (_) {
      // cualquier cosa rara: no se descarta nada
    }
  }

  // Lo que viene de la nube se revisa a fondo antes de pisar lo local: cada entrada tiene que ser un mapa con un id que sirva
  // de nombre de archivo (los ids son nombres de carpeta y de archivo en disco).
  static bool _entries(Object? l, {bool needId = true}) => l is List && l.every((e) => e is Map && (!needId || isSafeId(e['id'])));
  static bool validNotebook(Map j) =>
      j['format'] == Notebook.kFormat && _entries(j['sheets']) && (j['sections'] == null || _entries(j['sections'], needId: false));
  static bool validIndex(Map j) =>
      j['format'] == Notebook.kFormat && _entries(j['notebooks']) && (j['folders'] == null || _entries(j['folders'], needId: false));

  // ---------- local ----------
  Future<Set<String>> _localPaths() async {
    final out = <String>{};
    final prefix = '${store.dir.path}/';
    await for (final e in store.dir.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final rel = e.path.startsWith(prefix) ? e.path.substring(prefix.length) : null;
      if (rel != null && isSyncPath(rel)) out.add(rel);
    }
    return out;
  }

  /// El estado de [p] en disco ahora (null si no existe). Si tamaño y fecha son los de la base, no se relee, salvo el
  /// índice y los notebook.json: son chicos y se hashean siempre. Antes se usaba el atajo también para ellos y, si la
  /// biblioteca guardaba el índice mientras se subía, la base quedaba con el hash viejo y la fecha/tamaño nuevos: el
  /// atajo devolvía para siempre el hash viejo y el cambio nunca se subía. Releyendo, un estado ya trabado se arregla
  /// solo en la próxima pasada.
  Future<FileBase?> _stat(String p) async {
    final f = store.syncFile(p);
    final s = await f.stat();
    if (s.type == FileSystemEntityType.notFound) return null;
    final mt = s.modified.millisecondsSinceEpoch;
    final b = _st.base[p];
    final kind = syncKind(p);
    final siempreLee = kind == SyncKind.indexFile || kind == SyncKind.notebook;
    if (!siempreLee && b != null && b.size == s.size && b.mtime == mt) return b;
    final bytes = await f.readAsBytes();
    final h = p == 'index.json' ? _md5(utf8.encode(normalizeIndex(utf8.decode(bytes, allowMalformed: true)))) : _md5(bytes);
    return FileBase(h, s.size, mt);
  }

  /// Escribe [bytes] en [p] solo si en disco sigue lo que se vio ([expect], null = no existía): si alguien lo tocó
  /// mientras tanto (la biblioteca guardó el índice, por ejemplo) no se pisa y queda para la próxima pasada.
  /// Devuelve el `stat` tomado justo después de escribir, para anotarlo en la base.
  Future<FileStat> _writeLocal(String p, Uint8List bytes, String? expect) async {
    final nb = notebookIdOf(p);
    if (nb != null && openNotebooks().contains(nb)) throw const _Skip(); // se abrió mientras tanto
    if ((await _stat(p))?.md5 != expect) throw const _Skip();
    if (p == 'index.json') {
      final cur = await store.syncFile(p).exists() ? await store.syncFile(p).readAsString() : '{}';
      bytes = Uint8List.fromList(utf8.encode(restoreIndexLocal(utf8.decode(bytes), cur)));
    }
    await store.writeSyncFile(p, bytes);
    _rep.localChanged = true;
    if (p == 'index.json') _rep.indexChanged = true;
    return store.syncFile(p).stat();
  }

  /// Lo de la nube para [p] no se aplica ahora porque el cuaderno está abierto.
  void _wait(String p) {
    final nb = notebookIdOf(p);
    if (nb != null) {
      _rep.remoteWaiting.add(nb);
      if (!_rep.skippedBusy.contains(nb)) _rep.skippedBusy.add(nb);
    }
  }

  /// En un cuaderno abierto solo se sube. Es seguro seguir si no hay nada que escribir acá: iguales, o cambió solo lo local
  /// (la nube sigue en la base o no existe), o se borró acá y la nube sigue en la base (el borrado es solo remoto).
  bool _upOnlyOk(String? L, String? R, String? B) {
    if (L == R) return true;
    if (L != null) return L != B && (R == null || R == B);
    return B != null && R == B;
  }

  Future<void> _markBase(String p, String hash, {String? text, FileStat? stat}) async {
    final st = stat ?? await store.syncFile(p).stat();
    _st.base[p] = FileBase(hash, st.size, st.modified.millisecondsSinceEpoch);
    _st.remote[p] = hash;
    if (text != null) _st.baseText[p] = text;
  }

  void _unBase(String p) {
    _st.base.remove(p);
    _st.baseText.remove(p);
  }

  // ---------- remoto ----------
  Future<void> _upload(String p, Uint8List bytes) async {
    final rf = await remote.upload(p, bytes, ifRemoteMd5: _st.remote[p]);
    _st.remote[p] = rf.md5;
    _rep.uploaded++;
  }

  Future<Uint8List> _download(String p) async {
    final b = await remote.download(p);
    _rep.downloaded++;
    return b;
  }

  String _md5(List<int> b) => md5.convert(b).toString();

  // ---------- hojas y medios ----------
  /// Lee [p] para subirlo: sus bytes, el hash DE ESOS BYTES y el `stat` tomado antes de leer. Si el archivo cambia mientras
  /// se lee (una grabación o una copia que sigue escribiéndose) no se sube a medias: queda para la próxima pasada. La base
  /// se anota con este hash y este `stat` (no con los de una lectura anterior): si no, un archivo que creció entre el hash
  /// y la subida quedaba anotado con el hash viejo, la próxima subida pedía el hash equivocado y Drive devolvía conflicto.
  Future<(Uint8List, String, FileStat)> _readStable(String p) async {
    final f = store.syncFile(p);
    final before = await f.stat();
    final bytes = await f.readAsBytes();
    final after = await f.stat();
    if (before.size != after.size || before.modified != after.modified || bytes.length != after.size) throw const _Skip();
    return (bytes, _md5(bytes), after);
  }

  /// Como [_readStable] pero para index.json / notebook.json: devuelve el texto (normalizado si es el índice), el hash de
  /// ESE texto y el `stat` tomado antes de leer. Si el archivo cambió mientras se leía, queda para la próxima pasada.
  Future<(String, String, FileStat)> _readStableText(String p) async {
    final (bytes, _, st) = await _readStable(p);
    final raw = utf8.decode(bytes, allowMalformed: true);
    final t = p == 'index.json' ? normalizeIndex(raw) : raw;
    return (t, p == 'index.json' ? _md5(utf8.encode(t)) : _md5(bytes), st);
  }

  Future<void> _uploadFile(String p) async {
    final (bytes, h, st) = await _readStable(p);
    await _upload(p, bytes);
    await _markBase(p, h, stat: st);
  }

  Future<void> _opaque(String p) async {
    final l = await _stat(p), L = l?.md5, R = _st.remote[p], B = _st.base[p]?.md5;
    final nb = notebookIdOf(p);
    if (_upOnly && !_upOnlyOk(L, R, B)) return _wait(p);
    if (L == null && R == null) return _unBase(p);
    if (L == R) return _markBase(p, L!);
    if (L != null && R == null) {
      if (B != null && L == B) {
        _deferred.add((p, true)); // se borró en la nube
        return;
      }
      if (nb != null) _active.add(nb);
      return _uploadFile(p);
    }
    if (L == null && R != null) {
      if (B != null && R == B) {
        _deferred.add((p, false)); // se borró acá
        return;
      }
      if (nb != null) _active.add(nb);
      return _takeRemote(p, null);
    }
    // existe en los dos lados y difiere
    if (nb != null) _active.add(nb);
    if (B == null || (L != B && R != B)) {
      if (syncKind(p) == SyncKind.sheet) return _sheetConflict(p, L!);
      return _putLocal(p, L!); // medios: nombres únicos, no debería pasar; queda el local
    }
    if (L == B) return _takeRemote(p, L);
    await _putLocal(p, L!);
  }

  Future<void> _putLocal(String p, String L) => _uploadFile(p);

  Future<void> _takeRemote(String p, String? expectLocal) async {
    final bytes = await _download(p);
    if (syncKind(p) == SyncKind.sheet) decodeSheet(bytes); // un archivo roto en la nube no entra
    final st = await _writeLocal(p, bytes, expectLocal);
    await _markBase(p, _md5(bytes), stat: st);
  }

  /// Misma hoja editada en los dos lados: queda la local y la remota pasa a ser una hoja nueva "(conflicto)" justo
  /// después. Las dos se suben, así el otro dispositivo también recibe las dos.
  Future<void> _sheetConflict(String p, String L) async {
    final nbId = notebookIdOf(p)!, sid = sheetIdOf(p);
    final remoteBytes = await _download(p);
    final remoteContent = decodeSheet(remoteBytes);
    if (_md5(remoteBytes) == L) return _markBase(p, L);
    // La copia "(conflicto)" tiene que tener ids NUEVOS en todos sus elementos: con los de la original, al abrir el cuaderno
    // las dos hojas se pisarían en los mapas por id y se perdería contenido al guardar.
    final bytes = encodeSheet(SheetContent(
      strokes: [for (final s in remoteContent.strokes) s.moved(Offset.zero, id: newId('s'))],
      texts: [for (final t in remoteContent.texts) t.copy(id: newId('t'))],
      items: [for (final i in remoteContent.items) i.copy(id: newId('i'))],
    ));
    final rMd5 = _md5(bytes);
    final njPath = notebookJsonPath(nbId);
    final njFile = store.syncFile(njPath);
    if (await njFile.exists()) {
      final localJson = await njFile.readAsString();
      final j = jsonDecode(localJson) as Map;
      final list = [for (final e in (j['sheets'] as List)) e as Map];
      final at = list.indexWhere((e) => e['id'] == sid);
      final newSid = newId('h');
      final src = at >= 0 ? list[at] : <String, dynamic>{'bg': 'lined', 'paper': '#fffefb'};
      final title = (src['title'] ?? '') as String;
      final copy = {
        ...src,
        'id': newSid,
        'title': title.isEmpty ? '(conflicto)' : '$title (conflicto)',
        'updated': DateTime.now().millisecondsSinceEpoch,
      }
        ..remove('bookmark')
        ..remove('heads'); // los títulos del índice apuntan a elementos de la hoja original
      list.insert(at >= 0 ? at + 1 : list.length, copy);
      final np = sheetPath(nbId, newSid);
      await store.writeSyncFile(np, bytes);
      await _writeLocal(njPath, Uint8List.fromList(utf8.encode(jsonEncode({...j, 'sheets': list}))), _md5(utf8.encode(localJson)));
      await _upload(np, bytes);
      await _markBase(np, rMd5);
    }
    await _uploadFile(p);
    _rep.conflicts++;
    _st.conflictCount++;
  }

  // ---------- notebook.json e index.json ----------
  Future<void> _json(
      String p, String Function(String base, String local, String remote) merge, bool Function(Map) valid) async {
    final isIndex = p == 'index.json';
    final nb = notebookIdOf(p);
    final l = await _stat(p), L = l?.md5, R = _st.remote[p], B = _st.base[p]?.md5;
    Future<(Uint8List, String)> remoteText() async {
      final b = await _download(p);
      final t = utf8.decode(b);
      Map? j;
      try {
        j = jsonDecode(t) as Map;
      } catch (_) {}
      if (j == null || !valid(j)) throw const RemoteException('archivo de la nube inválido');
      return (b, t);
    }

    Future<void> up() async {
      final (t, h, st) = await _readStableText(p);
      await _upload(p, Uint8List.fromList(utf8.encode(t)));
      await _markBase(p, h, text: t, stat: st);
    }

    Future<void> down(String? expect) async {
      final (b, t) = await remoteText();
      final st = await _writeLocal(p, b, expect);
      await _markBase(p, _md5(b), text: t, stat: st);
    }

    if (_upOnly && !_upOnlyOk(L, R, B)) {
      _rep.skipped++;
      if (isIndex) return;
      return _wait(p);
    }
    if (L == null && R == null) return _unBase(p);
    if (L == R) {
      final (t, h, st) = await _readStableText(p);
      if (h != L) throw const _Skip(); // cambió entre medio: queda para la próxima pasada
      return _markBase(p, h, text: t, stat: st);
    }
    if (L != null && R == null) {
      if (B == null || isIndex || L != B || _active.contains(nb)) {
        if (nb != null && B != null) _kept.add(nb);
        return up(); // nuevo, o editado mientras se borraba en la nube: se vuelve a subir
      }
      _deferred.add((p, true));
      return;
    }
    if (L == null && R != null) {
      if (B == null || R != B || isIndex || _active.contains(nb)) {
        if (nb != null && B != null) _kept.add(nb);
        return down(null);
      }
      _deferred.add((p, false));
      return;
    }
    if (B == null || (L != B && R != B)) {
      final (rb, rt) = await remoteText();
      final (lt, lh, lst) = await _readStableText(p);
      final merged = merge(_st.baseText[p] ?? '{}', lt, rt);
      final mb = Uint8List.fromList(utf8.encode(merged));
      final mh = _md5(mb);
      var st = lst;
      if (mh != lh) st = await _writeLocal(p, mb, lh);
      if (mh != R) {
        await _upload(p, mb);
      }
      return _markBase(p, mh, text: merged, stat: st);
    }
    if (L == B) return down(L);
    return up();
  }

  // ---------- borrados ----------
  Future<void> _runDeferred() async {
    final touched = <String>{};
    for (final (p, local) in _deferred) {
      try {
        if (local) {
          final nb = notebookIdOf(p);
          if (nb != null && openNotebooks().contains(nb)) continue; // se abrió mientras tanto
          if ((await _stat(p))?.md5 != _st.base[p]?.md5) continue; // lo tocaron mientras tanto
          await store.deleteSyncFile(p);
          _rep.deletedLocal++;
          _rep.localChanged = true;
          if (nb != null) touched.add(nb);
        } else {
          await remote.delete(p);
          _st.remote.remove(p);
          _rep.deletedRemote++;
        }
        _unBase(p);
        await _st.save(store);
      } on RemoteOfflineException {
        rethrow;
      } on RemoteAuthException {
        rethrow;
      } catch (e) {
        _rep.errors.add('$p: $e');
        if (e is RemoteConflictException) {
          _st.token = null; // lo que sabemos de la nube está desfasado: la próxima pasada lista todo
          await _st.save(store);
        }
      }
    }
    for (final nb in touched) {
      await store.pruneEmptyNotebookDir(nb);
    }
  }
}
