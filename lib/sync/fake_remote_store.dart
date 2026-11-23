import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'remote_store.dart';

/// Remoto en memoria para los tests (y para probar la pantalla sin red). Varios dispositivos pueden compartir uno.
/// Se puede simular un corte: [failAfter] deja pasar esa cantidad de operaciones y después falla todo con
/// [RemoteOfflineException] hasta que se pone en null.
class FakeRemoteStore implements RemoteStore {
  final _files = <String, ({Uint8List bytes, String md5, int modified})>{};
  final _log = <(int, String)>[]; // (número de cambio, ruta)
  int _seq = 0;
  int _epoch = 0;
  int _clock = 1000;
  final folders = <String>{};

  int uploads = 0, downloads = 0, deletes = 0, changeCalls = 0;
  final uploaded = <String>[];
  int? failAfter;
  bool offline = false;
  int _ops = 0;

  /// Gancho opcional: corre al empezar cada subida, antes de que se complete (simula que la app sigue guardando
  /// archivos mientras la red está lenta).
  Future<void> Function(String path)? onUpload;

  void _tick() {
    if (offline || (failAfter != null && _ops >= failAfter!)) throw const RemoteOfflineException();
    _ops++;
  }

  /// Arranca de nuevo el conteo de [failAfter].
  void resetOps() => _ops = 0;

  Iterable<String> get paths => _files.keys;
  bool has(String path) => _files.containsKey(path);
  Uint8List? bytesOf(String path) => _files[path]?.bytes;
  String? md5Of(String path) => _files[path]?.md5;

  /// Pone un archivo sin pasar por la API (para armar escenarios).
  void put(String path, List<int> bytes) {
    final b = Uint8List.fromList(bytes);
    _files[path] = (bytes: b, md5: md5.convert(b).toString(), modified: _clock++);
    _log.add((++_seq, path));
  }

  /// Vacía el remoto como si hubieran borrado la carpeta entera: los tokens viejos dejan de valer (el próximo
  /// `changes` es un listado completo, ahora vacío).
  void wipe() {
    _files.clear();
    _log.clear();
    _epoch++;
  }

  void clearCounters() {
    uploads = downloads = deletes = changeCalls = 0;
    uploaded.clear();
  }

  @override
  Future<RemoteChanges> changes(String? token) async {
    _tick();
    changeCalls++;
    RemoteFile rf(String p) => RemoteFile(p, _files[p]!.md5, _files[p]!.modified);
    final parts = token?.split(':');
    if (parts == null || int.parse(parts[0]) != _epoch) {
      return RemoteChanges(files: [for (final p in _files.keys) rf(p)], nextToken: '$_epoch:$_seq', full: true);
    }
    final since = int.parse(parts[1]);
    final touched = {for (final (n, p) in _log) if (n > since) p};
    return RemoteChanges(
      files: [for (final p in touched) if (_files.containsKey(p)) rf(p)],
      removed: [for (final p in touched) if (!_files.containsKey(p)) p],
      nextToken: '$_epoch:$_seq',
    );
  }

  @override
  Future<Uint8List> download(String path) async {
    _tick();
    downloads++;
    final f = _files[path];
    if (f == null) throw const RemoteNotFoundException();
    return Uint8List.fromList(f.bytes);
  }

  @override
  Future<RemoteFile> upload(String path, Uint8List bytes, {String? ifRemoteMd5}) async {
    _tick();
    await onUpload?.call(path);
    if (_files[path]?.md5 != ifRemoteMd5) throw const RemoteConflictException();
    uploads++;
    uploaded.add(path);
    put(path, bytes);
    final parts = path.split('/')..removeLast();
    for (var i = 1; i <= parts.length; i++) {
      folders.add(parts.take(i).join('/'));
    }
    return RemoteFile(path, _files[path]!.md5, _files[path]!.modified);
  }

  @override
  Future<void> delete(String path) async {
    _tick();
    if (_files.remove(path) != null) {
      deletes++;
      _log.add((++_seq, path));
    }
  }

  @override
  Future<void> createFolder(String path) async {
    _tick();
    folders.add(path);
  }
}
