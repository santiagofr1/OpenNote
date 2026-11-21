import 'dart:typed_data';

/// Un archivo del remoto. [path] es relativo a la carpeta `OpenNote/` (ver sync_paths.dart), [md5] el hash de sus
/// bytes y [modified] la hora (ms) de la última modificación según el remoto.
class RemoteFile {
  final String path;
  final String md5;
  final int modified;
  const RemoteFile(this.path, this.md5, this.modified);
  @override
  String toString() => 'RemoteFile($path, $md5)';
}

/// Lo que cambió en el remoto desde un token. [full]: es el listado completo (no un delta): lo que no figura en
/// [files] no existe. Si no, [files] son los archivos nuevos o cambiados y [removed] las rutas que ya no están.
/// [nextToken] se guarda para pedir el próximo delta.
class RemoteChanges {
  final List<RemoteFile> files;
  final List<String> removed;
  final String nextToken;
  final bool full;
  const RemoteChanges({required this.files, this.removed = const [], required this.nextToken, this.full = false});
}

/// Falla del remoto. [message] se le puede mostrar al usuario.
class RemoteException implements Exception {
  final String message;
  const RemoteException(this.message);
  @override
  String toString() => message;
}

/// Sin red (o el servidor no responde): la pasada se corta y se reintenta después.
class RemoteOfflineException extends RemoteException {
  const RemoteOfflineException([super.message = 'Sin conexión']);
}

/// La sesión venció o se revocó: hay que volver a conectar.
class RemoteAuthException extends RemoteException {
  const RemoteAuthException([super.message = 'La sesión de Google venció. Volvé a conectar.']);
}

/// El archivo cambió en el remoto desde lo que se creía (otro dispositivo escribió en el medio).
class RemoteConflictException extends RemoteException {
  const RemoteConflictException([super.message = 'El archivo cambió en la nube mientras se subía; se reintenta']);
}

class RemoteNotFoundException extends RemoteException {
  const RemoteNotFoundException([super.message = 'No existe en la nube']);
}

/// El otro lado de la sincronización: un almacén de archivos por ruta. Nada acá sabe de Google (ver
/// drive_remote_store.dart) ni de cuadernos. Las rutas son siempre las de sync_paths.dart.
abstract class RemoteStore {
  /// Cambios desde [token] (null: listado completo). Las subidas propias también aparecen en el próximo delta, con
  /// el mismo hash: no es un problema.
  Future<RemoteChanges> changes(String? token);

  /// Los bytes del archivo en [path]. [RemoteNotFoundException] si no existe.
  Future<Uint8List> download(String path);

  /// Sube [bytes] a [path] (crea las carpetas que falten). Optimista: si [ifRemoteMd5] no es el hash que tiene el
  /// remoto ahora (null = el archivo no debe existir), lanza [RemoteConflictException] sin escribir nada.
  Future<RemoteFile> upload(String path, Uint8List bytes, {String? ifRemoteMd5});

  /// Borra [path] (no falla si ya no estaba).
  Future<void> delete(String path);

  /// Crea la carpeta [path] y las de arriba (no falla si ya existe).
  Future<void> createFolder(String path);
}
