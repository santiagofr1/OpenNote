import 'dart:convert';
import 'dart:io';

/// Candado entre procesos/isolates para que NUNCA corran a la vez la pasada de la app y la de fondo (WorkManager corre
/// en otro isolate, sin memoria compartida). Es un archivo `sync.lock` en la carpeta de datos con el PID, el dueño y la
/// hora. Se toma creándolo de forma exclusiva (atómico en el sistema de archivos). Si el archivo es más viejo que [ttl]
/// se considera abandonado (la app o la tarea murió sin soltarlo) y se pisa: así un candado viejo no bloquea para siempre.
class SyncLock {
  SyncLock(Directory dir, {this.owner = 'app', this.ttl = const Duration(minutes: 10), DateTime Function()? now})
      : _file = File('${dir.path}/sync.lock'),
        _now = now ?? DateTime.now;
  final File _file;
  final String owner;
  final Duration ttl;
  final DateTime Function() _now;
  String? _token;

  bool get held => _token != null;

  /// Intenta tomarlo. Devuelve false si lo tiene otro y no venció.
  Future<bool> tryAcquire() async {
    if (_token != null) return true;
    final token = '$pid-${_now().microsecondsSinceEpoch}';
    for (var i = 0; i < 2; i++) {
      try {
        await _file.create(exclusive: true);
        await _file.writeAsString(jsonEncode({'pid': pid, 'owner': owner, 'token': token, 'at': _now().millisecondsSinceEpoch}), flush: true);
        _token = token;
        return true;
      } on FileSystemException {
        // ya existe (o no se pudo crear): si está vencido o roto se borra y se reintenta una vez
        if (!await _expired()) return false;
        try {
          await _file.delete();
        } on FileSystemException {
          return false; // otro lo borró o lo tomó justo antes
        }
      }
    }
    return false;
  }

  Future<bool> _expired() async {
    try {
      final j = jsonDecode(await _file.readAsString()) as Map;
      final at = DateTime.fromMillisecondsSinceEpoch(j['at'] as int);
      return _now().difference(at) >= ttl;
    } on PathNotFoundException {
      return true; // desapareció: se puede reintentar
    } catch (_) {
      // vacío (otro lo está creando) o roto: se mira la fecha del archivo
      try {
        return _now().difference(await _file.lastModified()) >= ttl;
      } catch (_) {
        return true;
      }
    }
  }

  /// Lo suelta (solo si todavía es nuestro).
  Future<void> release() async {
    final mine = _token;
    if (mine == null) return;
    _token = null;
    try {
      final j = jsonDecode(await _file.readAsString()) as Map;
      if (j['token'] == mine) await _file.delete();
    } catch (_) {}
  }
}

/// Marcas en la carpeta de datos para coordinar la app con la tarea de fondo:
///  - `sync.fg`: la app está en primer plano (se renueva en cada consulta; si es vieja, la app murió y no cuenta);
///  - `sync.busy`: cuadernos abiertos en el editor cuando la app pasó a segundo plano (la tarea de fondo no les
///    escribe encima, solo les sube lo suyo);
///  - `sync.bgchanged`: la tarea de fondo bajó cambios; al volver a primer plano la app relee el disco.
class SyncMarks {
  SyncMarks(Directory dir, {DateTime Function()? now})
      : _fg = File('${dir.path}/sync.fg'),
        _busy = File('${dir.path}/sync.busy'),
        _changed = File('${dir.path}/sync.bgchanged'),
        _now = now ?? DateTime.now;
  final File _fg, _busy, _changed;
  final DateTime Function() _now;

  Future<void> beatForeground() async {
    try {
      await _fg.writeAsString('${_now().millisecondsSinceEpoch}', flush: true);
    } catch (_) {}
  }

  Future<void> clearForeground() => _del(_fg);

  /// ¿La app está en primer plano? Vale si la marca se renovó hace menos de [maxAge].
  Future<bool> foregroundFresh({Duration maxAge = const Duration(minutes: 3)}) async {
    try {
      final at = DateTime.fromMillisecondsSinceEpoch(int.parse(await _fg.readAsString()));
      return _now().difference(at) < maxAge;
    } catch (_) {
      return false;
    }
  }

  Future<void> writeBusy(Set<String> ids) async {
    try {
      if (ids.isEmpty) {
        await _del(_busy);
      } else {
        await _busy.writeAsString(jsonEncode(ids.toList()), flush: true);
      }
    } catch (_) {}
  }

  Future<Set<String>> readBusy() async {
    try {
      return {for (final e in jsonDecode(await _busy.readAsString()) as List) e as String};
    } catch (_) {
      return const {};
    }
  }

  Future<void> clearBusy() => _del(_busy);

  Future<void> markBackgroundChanged() async {
    try {
      await _changed.writeAsString('${_now().millisecondsSinceEpoch}', flush: true);
    } catch (_) {}
  }

  /// Si la tarea de fondo bajó algo desde la última vez, lo devuelve (true) y borra la marca.
  Future<bool> takeBackgroundChanged() async {
    if (!await _changed.exists()) return false;
    await _del(_changed);
    return true;
  }

  static Future<void> _del(File f) async {
    try {
      await f.delete();
    } catch (_) {}
  }
}
