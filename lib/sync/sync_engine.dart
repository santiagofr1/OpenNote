import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

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
/// REGLA DE ORO: un cuaderno abierto en el editor ([openNotebooks]) no se toca (ni sube ni baja: la memoria del
/// editor pisaría lo que escribamos). Mientras haya alguno abierto tampoco se toca `index.json` (la biblioteca lo
/// tiene en memoria). Se sincroniza cuando se cierra.
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
    final open = openNotebooks();
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

      final paths = <String>{..._st.base.keys, ..._st.remote.keys, ...await _localPaths()}.where(isSyncPath).toList();
      int order(String p) => switch (syncKind(p)!) {
            SyncKind.media => 0,
            SyncKind.sheet => 1,
            SyncKind.notebook => 2,
            SyncKind.indexFile => 3,
          };
      paths.sort((a, b) => order(a) != order(b) ? order(a).compareTo(order(b)) : a.compareTo(b));
      for (final p in paths) {
        final nb = notebookIdOf(p);
        if ((nb != null && open.contains(nb)) || (p == 'index.json' && open.isNotEmpty)) {
          _rep.skipped++;
          if (nb != null && !_rep.skippedBusy.contains(nb)) _rep.skippedBusy.add(nb);
          continue;
        }
        try {
          switch (syncKind(p)!) {
            case SyncKind.media:
            case SyncKind.sheet:
              await _opaque(p);
            case SyncKind.notebook:
              await _json(p, (b, l, r) => mergeNotebookJson(b, l, r), validNotebook);
            case SyncKind.indexFile:
              await _json(p, (b, l, r) => mergeIndexJson(b, l, r, keep: _kept), validIndex);
          }
        } on _Skip {
          _rep.skipped++;
        } on RemoteOfflineException {
          rethrow;
        } on RemoteAuthException {
          rethrow;
        } catch (e) {
          _rep.errors.add('$p: $e');
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

  static bool validNotebook(Map j) => j['format'] == Notebook.kFormat && j['sheets'] is List;
  static bool validIndex(Map j) => j['format'] == Notebook.kFormat && j['notebooks'] is List;

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

  /// El estado de [p] en disco ahora (null si no existe). Si tamaño y fecha son los de la base, no se relee.
  Future<FileBase?> _stat(String p) async {
    final f = store.syncFile(p);
    final s = await f.stat();
    if (s.type == FileSystemEntityType.notFound) return null;
    final mt = s.modified.millisecondsSinceEpoch;
    final b = _st.base[p];
    if (b != null && b.size == s.size && b.mtime == mt) return b;
    final bytes = await f.readAsBytes();
    final h = p == 'index.json' ? _md5(utf8.encode(normalizeIndex(utf8.decode(bytes, allowMalformed: true)))) : _md5(bytes);
    return FileBase(h, s.size, mt);
  }

  /// Escribe [bytes] en [p] solo si en disco sigue lo que se vio ([expect], null = no existía): si alguien lo tocó
  /// mientras tanto (la biblioteca guardó el índice, por ejemplo) no se pisa y queda para la próxima pasada.
  Future<void> _writeLocal(String p, Uint8List bytes, String? expect) async {
    if ((await _stat(p))?.md5 != expect) throw const _Skip();
    if (p == 'index.json') {
      final cur = await store.syncFile(p).exists() ? await store.syncFile(p).readAsString() : '{}';
      bytes = Uint8List.fromList(utf8.encode(restoreIndexLocal(utf8.decode(bytes), cur)));
    }
    await store.writeSyncFile(p, bytes);
    _rep.localChanged = true;
    if (p == 'index.json') _rep.indexChanged = true;
  }

  Future<void> _markBase(String p, String hash, {String? text}) async {
    final st = await store.syncFile(p).stat();
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
  Future<void> _opaque(String p) async {
    final l = await _stat(p), L = l?.md5, R = _st.remote[p], B = _st.base[p]?.md5;
    final nb = notebookIdOf(p);
    if (L == null && R == null) return _unBase(p);
    if (L == R) return _markBase(p, L!);
    if (L != null && R == null) {
      if (B != null && L == B) {
        _deferred.add((p, true)); // se borró en la nube
        return;
      }
      if (nb != null) _active.add(nb);
      await _upload(p, await store.syncFile(p).readAsBytes());
      return _markBase(p, L);
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

  Future<void> _putLocal(String p, String L) async {
    await _upload(p, await store.syncFile(p).readAsBytes());
    await _markBase(p, L);
  }

  Future<void> _takeRemote(String p, String? expectLocal) async {
    final bytes = await _download(p);
    if (syncKind(p) == SyncKind.sheet) decodeSheet(bytes); // un archivo roto en la nube no entra
    await _writeLocal(p, bytes, expectLocal);
    await _markBase(p, _md5(bytes));
  }

  /// Misma hoja editada en los dos lados: queda la local y la remota pasa a ser una hoja nueva "(conflicto)" justo
  /// después. Las dos se suben, así el otro dispositivo también recibe las dos.
  Future<void> _sheetConflict(String p, String L) async {
    final nbId = notebookIdOf(p)!, sid = sheetIdOf(p);
    final bytes = await _download(p);
    decodeSheet(bytes);
    final rMd5 = _md5(bytes);
    if (rMd5 == L) return _markBase(p, L);
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
      }..remove('bookmark');
      list.insert(at >= 0 ? at + 1 : list.length, copy);
      final np = sheetPath(nbId, newSid);
      await store.writeSyncFile(np, bytes);
      await _writeLocal(njPath, Uint8List.fromList(utf8.encode(jsonEncode({...j, 'sheets': list}))), _md5(utf8.encode(localJson)));
      await _upload(np, bytes);
      await _markBase(np, rMd5);
    }
    await _upload(p, await store.syncFile(p).readAsBytes());
    await _markBase(p, L);
    _rep.conflicts++;
    _st.conflictCount++;
  }

  // ---------- notebook.json e index.json ----------
  Future<void> _json(
      String p, String Function(String base, String local, String remote) merge, bool Function(Map) valid) async {
    final isIndex = p == 'index.json';
    final nb = notebookIdOf(p);
    final l = await _stat(p), L = l?.md5, R = _st.remote[p], B = _st.base[p]?.md5;
    Future<String> localText() async {
      final t = await store.syncFile(p).readAsString();
      return isIndex ? normalizeIndex(t) : t;
    }
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
      final t = await localText();
      await _upload(p, Uint8List.fromList(utf8.encode(t)));
      await _markBase(p, L!, text: t);
    }

    Future<void> down(String? expect) async {
      final (b, t) = await remoteText();
      await _writeLocal(p, b, expect);
      await _markBase(p, _md5(b), text: t);
    }

    if (L == null && R == null) return _unBase(p);
    if (L == R) return _markBase(p, L!, text: await localText());
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
      final lt = await localText();
      final merged = merge(_st.baseText[p] ?? '{}', lt, rt);
      final mb = Uint8List.fromList(utf8.encode(merged));
      final mh = _md5(mb);
      if (mh != L) await _writeLocal(p, mb, L);
      if (mh != R) {
        await _upload(p, mb);
      }
      return _markBase(p, mh, text: merged);
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
          if ((await _stat(p))?.md5 != _st.base[p]?.md5) continue; // lo tocaron mientras tanto
          await store.deleteSyncFile(p);
          _rep.deletedLocal++;
          _rep.localChanged = true;
          final nb = notebookIdOf(p);
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
      }
    }
    for (final nb in touched) {
      await store.pruneEmptyNotebookDir(nb);
    }
  }
}
