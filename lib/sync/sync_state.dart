import 'dart:convert';

import '../data/storage.dart';
import 'sync_paths.dart';

/// Cómo estaba un archivo la última vez que quedó igual en los dos lados: su hash (md5 de los bytes) y su tamaño y
/// fecha locales, para no releerlo entero en cada pasada si no se tocó.
class FileBase {
  final String md5;
  final int size;
  final int mtime;
  const FileBase(this.md5, this.size, this.mtime);
  factory FileBase.fromJson(Map j) => FileBase(j['md5'] as String, (j['size'] ?? 0) as int, (j['mtime'] ?? 0) as int);
  Map<String, dynamic> toJson() => {'md5': md5, 'size': size, 'mtime': mtime};
}

/// Lo que recuerda la sincronización entre pasadas, en `sync_state.json` junto a los datos (no se sube).
/// Si se pierde el archivo no se pierde nada: la próxima pasada reconstruye todo (lo que está en un solo lado se
/// copia al otro, y lo que difiere en los dos se trata como conflicto).
class SyncState {
  /// Token de cambios del remoto (null: todavía no se listó).
  String? token;

  /// Cuenta con la que se sincronizó: si cambia, se empieza de cero.
  String? account;
  int lastSync = 0; // ms de la última pasada completa
  int lastAttempt = 0;
  String? lastError;
  int conflictCount = 0;

  /// ruta → la versión de la última sincronización (iguales en los dos lados en ese momento).
  final Map<String, FileBase> base = {};

  /// ruta → hash que se sabe que tiene el remoto (listado + deltas + lo que se subió).
  final Map<String, String> remote = {};

  /// ruta → texto de la base de `notebook.json` e `index.json` (para fusionar cuando cambian los dos lados).
  final Map<String, String> baseText = {};

  SyncState();

  factory SyncState.fromJson(Map j) {
    final s = SyncState()
      ..token = j['token'] as String?
      ..account = j['account'] as String?
      ..lastSync = (j['lastSync'] ?? 0) as int
      ..lastAttempt = (j['lastAttempt'] ?? 0) as int
      ..lastError = j['lastError'] as String?
      ..conflictCount = (j['conflicts'] ?? 0) as int;
    for (final e in ((j['base'] ?? {}) as Map).entries) {
      s.base[e.key as String] = FileBase.fromJson(e.value as Map);
    }
    for (final e in ((j['remote'] ?? {}) as Map).entries) {
      s.remote[e.key as String] = e.value as String;
    }
    for (final e in ((j['baseText'] ?? {}) as Map).entries) {
      s.baseText[e.key as String] = e.value as String;
    }
    return s;
  }

  Map<String, dynamic> toJson() => {
        'format': 1,
        if (token != null) 'token': token,
        if (account != null) 'account': account,
        'lastSync': lastSync,
        'lastAttempt': lastAttempt,
        if (lastError != null) 'lastError': lastError,
        'conflicts': conflictCount,
        'base': {for (final e in base.entries) e.key: e.value.toJson()},
        'remote': remote,
        'baseText': baseText,
      };

  /// Lee el estado (uno vacío si no hay o está roto: se reconstruye solo).
  static Future<SyncState> load(Storage store) async {
    try {
      return SyncState.fromJson(jsonDecode(await store.syncFile(kSyncStateFile).readAsString()) as Map);
    } catch (_) {
      return SyncState();
    }
  }

  Future<void> save(Storage store) => store.writeSyncFile(kSyncStateFile, utf8.encode(jsonEncode(toJson())));

  /// Borra el archivo (al desconectar).
  static Future<void> clear(Storage store) => store.deleteSyncFile(kSyncStateFile);
}
