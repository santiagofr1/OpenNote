import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' show AccessDeniedException;
import 'package:http/http.dart' as http;

import 'e2e_crypto.dart' show kCryptoFile;
import 'remote_store.dart';
import 'sync_paths.dart';

const _folderMime = 'application/vnd.google-apps.folder';
const _fields = 'id,name,mimeType,md5Checksum,modifiedTime,createdTime,parents';

class _Node {
  final String id;
  final String name;
  final String? parent;
  final bool folder;
  String? md5;
  final int modified, created;
  _Node(this.id, this.name, this.parent, this.folder, this.md5, this.modified, this.created);

  factory _Node.from(drive.File f) => _Node(
        f.id!,
        f.name ?? '',
        (f.parents?.isNotEmpty ?? false) ? f.parents!.first : null,
        f.mimeType == _folderMime,
        f.md5Checksum,
        f.modifiedTime?.millisecondsSinceEpoch ?? 0,
        f.createdTime?.millisecondsSinceEpoch ?? 0,
      );
}

/// [RemoteStore] sobre Google Drive (API v3) con el permiso `drive.file`: la app solo ve lo que ella misma creó. Todo
/// vive en una carpeta [rootName] de "Mi unidad", con la misma estructura que los datos locales (ver
/// docs/SINCRONIZACION.md). [client] ya viene autenticado (ver google_auth.dart).
///
/// Mantiene en memoria un mapa id → nodo de todo lo que la app tiene en Drive; las rutas salen de ahí. Los deltas usan
/// la API de cambios (`changes.list` con un `startPageToken`).
///
/// NOTA: escrito contra la documentación de Drive v3 y `googleapis` 19; todavía NO se probó contra Drive real (hacen falta
/// credenciales, ver docs/SINCRONIZACION.md).
class DriveRemoteStore implements RemoteStore, PurgingRemoteStore {
  DriveRemoteStore(http.Client client, {this.rootName = kDefaultRoot}) : _api = drive.DriveApi(client);

  /// La carpeta de Drive. Los builds de desarrollo (debug, como "OpenNote Test") usan otra para no tocar los cuadernos reales.
  static const kDefaultRoot = bool.fromEnvironment('dart.vm.product') ? 'OpenNote' : 'OpenNote Test';
  final drive.DriveApi _api;
  final String rootName;

  final _nodes = <String, _Node>{};
  /// Si el mapa de Drive ya se cargó (para no recargarlo en download/upload/delete).
  bool _loaded = false;

  /// Si ya se le entregó al motor un listado COMPLETO. Es distinto de `_loaded`: un `download('crypto.json')` previo carga
  /// el mapa sin que el motor se entere de lo que cambió en Drive antes, y su `SyncState.remote` quedaría desfasado.
  bool _listed = false;
  String? _rootId;

  // ------------------------------------------------------------------ errores

  Future<T> _g<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on RemoteException {
      rethrow;
    } on drive.DetailedApiRequestError catch (e) {
      final s = e.status ?? 0;
      if (s == 401) throw const RemoteAuthException();
      if (s == 404) throw const RemoteNotFoundException();
      if (s == 403 && (e.message ?? '').toLowerCase().contains('rate')) throw const RemoteException('Google pide esperar un rato (límite de uso)');
      if (s == 403) throw const RemoteAuthException('Google no dejó acceder a Drive. Volvé a conectar.');
      if (s == 429 || s >= 500) throw RemoteOfflineException('Drive no responde ($s)');
      throw RemoteException('Error de Drive ($s): ${e.message}');
    } on AccessDeniedException {
      throw const RemoteAuthException();
    } on SocketException {
      throw const RemoteOfflineException();
    } on http.ClientException {
      throw const RemoteOfflineException();
    } on TimeoutException {
      throw const RemoteOfflineException();
    } on HandshakeException {
      throw const RemoteOfflineException();
    }
  }

  // ------------------------------------------------------------------ mapa de lo que hay en Drive

  /// Lista TODO lo que la app tiene en Drive (con `drive.file` son solo sus archivos) y arma [_nodes] y [_rootId].
  Future<void> _loadAll() async {
    final nodes = <String, _Node>{};
    String? page;
    do {
      final r = await _api.files.list(
        q: 'trashed = false',
        spaces: 'drive',
        pageSize: 1000,
        pageToken: page,
        $fields: 'nextPageToken,files($_fields)',
      );
      for (final f in r.files ?? <drive.File>[]) {
        if (f.id != null) nodes[f.id!] = _Node.from(f);
      }
      page = r.nextPageToken;
    } while (page != null);
    _nodes
      ..clear()
      ..addAll(nodes);
    _loaded = true;
    _pickRoot();
  }

  /// La carpeta raíz: la `OpenNote` más vieja cuyo padre no es nada de lo que la app creó (o sea, está en Mi unidad).
  void _pickRoot() {
    final c = [
      for (final n in _nodes.values)
        if (n.folder && n.name == rootName && (n.parent == null || !_nodes.containsKey(n.parent))) n
    ]..sort((a, b) => a.created.compareTo(b.created));
    _rootId = c.isEmpty ? null : c.first.id;
  }

  /// La ruta de [n] relativa a la raíz, o null si no cuelga de ella.
  String? _pathOf(_Node n) {
    final parts = <String>[];
    var cur = n;
    for (var i = 0; i < 16; i++) {
      if (cur.id == _rootId) return parts.reversed.join('/');
      parts.add(cur.name);
      final p = cur.parent == null ? null : _nodes[cur.parent];
      if (p == null) return null;
      cur = p;
    }
    return null;
  }

  /// ruta → archivo de todo lo que cuelga de la raíz y es sincronizable. Si hay dos con la misma ruta (dos
  /// dispositivos crearon el mismo archivo a la vez) gana el modificado más recientemente.
  Map<String, _Node> _snapshot() {
    final out = <String, _Node>{};
    if (_rootId == null) return out;
    for (final n in _nodes.values) {
      if (n.folder) continue;
      final p = _pathOf(n);
      if (p == null || !(isSyncPath(p) || p == kCryptoFile)) continue;
      final prev = out[p];
      if (prev == null || n.modified > prev.modified) out[p] = n;
    }
    return out;
  }

  RemoteFile _rf(String p, _Node n) => RemoteFile(p, n.md5 ?? '', n.modified);

  // ------------------------------------------------------------------ RemoteStore

  @override
  Future<RemoteChanges> changes(String? token) => _g(() async {
        // Sin token, o proceso nuevo (todavía no se le entregó un listado al motor): listado COMPLETO. Con un delta no
        // alcanza: lo cambiado o borrado mientras la app no corría no figura en el mapa recién cargado y nunca saldría
        // en el delta. Ojo: no vale mirar `_loaded`, el mapa ya puede estar cargado por un download previo (crypto.json).
        if (token == null || !_listed) {
          final start = (await _api.changes.getStartPageToken()).startPageToken!;
          await _loadAll(); // el token se pide ANTES de listar: lo que cambie en el medio llega en el próximo delta
          _listed = true;
          return RemoteChanges(files: [for (final e in _snapshot().entries) _rf(e.key, e.value)], nextToken: start, full: true);
        }
        final before = {for (final e in _snapshot().entries) e.key: e.value.md5};
        var page = token;
        String? next;
        try {
          while (true) {
            final r = await _api.changes.list(
              page,
              includeRemoved: true,
              pageSize: 1000,
              spaces: 'drive',
              $fields: 'nextPageToken,newStartPageToken,changes(fileId,removed,file($_fields,trashed))',
            );
            for (final c in r.changes ?? <drive.Change>[]) {
              final id = c.fileId;
              if (id == null) continue;
              final f = c.file;
              if (c.removed == true || f == null || f.trashed == true) {
                _nodes.remove(id);
              } else {
                _nodes[id] = _Node.from(f);
              }
            }
            if (r.nextPageToken != null) {
              page = r.nextPageToken!;
            } else {
              next = r.newStartPageToken;
              break;
            }
          }
        } on drive.DetailedApiRequestError catch (e) {
          if (e.status == 410) {
            // el token venció: se vuelve a listar todo
            final start = (await _api.changes.getStartPageToken()).startPageToken!;
            await _loadAll();
            return RemoteChanges(files: [for (final e in _snapshot().entries) _rf(e.key, e.value)], nextToken: start, full: true);
          }
          rethrow;
        }
        final hadRoot = _rootId != null;
        _pickRoot();
        if (hadRoot && _rootId == null) {
          // borraron la carpeta OpenNote entera: se avisa como listado completo (y vacío), no como cientos de borrados
          return RemoteChanges(files: const [], nextToken: next ?? token, full: true);
        }
        final after = _snapshot();
        return RemoteChanges(
          files: [for (final e in after.entries) if (before[e.key] != e.value.md5) _rf(e.key, e.value)],
          removed: [for (final p in before.keys) if (!after.containsKey(p)) p],
          nextToken: next ?? token,
        );
      });

  @override
  Future<Uint8List> download(String path) => _g(() async {
        if (!_loaded) await _loadAll();
        final n = _snapshot()[path];
        if (n == null) throw const RemoteNotFoundException();
        final media = await _api.files.get(n.id, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
        final b = BytesBuilder(copy: false);
        await for (final chunk in media.stream) {
          b.add(chunk);
        }
        return b.takeBytes();
      });

  @override
  Future<RemoteFile> upload(String path, Uint8List bytes, {String? ifRemoteMd5}) => _g(() async {
        if (!_loaded) await _loadAll();
        final existing = _snapshot()[path];
        if (existing != null) {
          // Drive no tiene escritura condicional: se mira el hash de ahora justo antes de escribir (queda una ventana
          // chica; si dos dispositivos pisan a la vez, el próximo listado lo muestra y se resuelve como conflicto)
          final cur = await _api.files.get(existing.id, $fields: 'md5Checksum,trashed') as drive.File;
          if (cur.trashed == true || cur.md5Checksum != ifRemoteMd5) throw const RemoteConflictException();
        } else if (ifRemoteMd5 != null) {
          throw const RemoteConflictException();
        }
        final media = drive.Media(Stream.value(bytes), bytes.length);
        final drive.File res;
        if (existing != null) {
          res = await _api.files.update(drive.File(), existing.id, uploadMedia: media, $fields: _fields);
        } else {
          final slash = path.lastIndexOf('/');
          final parent = await _ensureFolders(slash < 0 ? '' : path.substring(0, slash));
          res = await _api.files.create(
            drive.File(name: path.substring(slash + 1), parents: [parent], mimeType: 'application/octet-stream'),
            uploadMedia: media,
            $fields: _fields,
          );
        }
        final node = _Node.from(res);
        _nodes[node.id] = node;
        final got = node.md5 ?? md5.convert(bytes).toString();
        return RemoteFile(path, got, node.modified);
      });

  @override
  Future<void> delete(String path) => _g(() async {
        if (!_loaded) await _loadAll();
        final n = _snapshot()[path];
        if (n == null) return;
        // a la papelera (no borrado definitivo): se puede recuperar desde Drive
        await _api.files.update(drive.File(trashed: true), n.id, $fields: 'id');
        _nodes.remove(n.id);
      });

  @override
  Future<void> purge(String path) => _g(() async {
        if (!_loaded) await _loadAll();
        final n = _snapshot()[path];
        if (n == null) return;
        // borrado definitivo (no pasa por la papelera): con el cifrado no debe quedar el archivo viejo en claro
        await _api.files.delete(n.id);
        _nodes.remove(n.id);
      });

  @override
  Future<void> createFolder(String path) => _g(() async {
        if (!_loaded) await _loadAll();
        await _ensureFolders(path);
      });

  /// Crea (si faltan) la raíz y las carpetas de [path] ("a/b/c"; vacío = la raíz) y devuelve el id de la última.
  Future<String> _ensureFolders(String path) async {
    var cur = _rootId;
    if (cur == null) {
      final f = await _api.files.create(drive.File(name: rootName, mimeType: _folderMime), $fields: _fields);
      final n = _Node.from(f);
      _nodes[n.id] = n;
      cur = _rootId = n.id;
    }
    for (final seg in path.split('/').where((s) => s.isNotEmpty)) {
      final parent = cur!;
      _Node? hit;
      for (final n in _nodes.values) {
        if (n.folder && n.name == seg && n.parent == parent) {
          if (hit == null || n.created < hit.created) hit = n;
        }
      }
      if (hit == null) {
        final f = await _api.files.create(drive.File(name: seg, mimeType: _folderMime, parents: [parent]), $fields: _fields);
        hit = _Node.from(f);
        _nodes[hit.id] = hit;
      }
      cur = hit.id;
    }
    return cur!;
  }
}
