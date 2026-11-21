/// Qué rutas (relativas a la carpeta de datos) se sincronizan, y cómo se reconocen. Son las mismas en el disco local y
/// en el remoto (`OpenNote/` en Drive). Todo lo que viene del remoto se valida con esto antes de escribir: una ruta que
/// no encaja (con `..`, otra carpeta, nombres raros) se ignora.
library;

/// Estado de la sincronización (solo local, no se sube).
const kSyncStateFile = 'sync_state.json';

/// Caché del cifrado (ruta → hash del texto cifrado y del claro; solo local, no se sube). Ver encrypted_remote_store.dart.
const kSyncCryptoCacheFile = 'sync_crypto_cache.json';

final _id = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
final _file = RegExp(r'^[A-Za-z0-9_-][A-Za-z0-9._-]{0,127}$');

enum SyncKind { indexFile, notebook, sheet, media }

/// El tipo de la ruta [p], o null si no se sincroniza (`prefs.json`, temporales, `.roto`, rutas inválidas).
SyncKind? syncKind(String p) {
  if (p == 'index.json') return SyncKind.indexFile;
  final s = p.split('/');
  if (s.length == 3 && s[0] == 'notebooks' && _id.hasMatch(s[1]) && s[2] == 'notebook.json') return SyncKind.notebook;
  if (s.length == 4 && s[0] == 'notebooks' && _id.hasMatch(s[1]) && s[2] == 'sheets' && s[3].endsWith('.sheet')) {
    return _id.hasMatch(s[3].substring(0, s[3].length - 6)) ? SyncKind.sheet : null;
  }
  if (s.length == 2 && s[0] == 'media' && _file.hasMatch(s[1]) && !s[1].endsWith('.tmp') && !s[1].endsWith('.roto')) {
    return SyncKind.media;
  }
  return null;
}

bool isSyncPath(String p) => syncKind(p) != null;

/// El id del cuaderno al que pertenece [p] (`notebooks/<id>/...`), o null.
String? notebookIdOf(String p) {
  final s = p.split('/');
  return s.length >= 3 && s[0] == 'notebooks' && isSyncPath(p) ? s[1] : null;
}

String notebookJsonPath(String id) => 'notebooks/$id/notebook.json';
String sheetPath(String nbId, String sheetId) => 'notebooks/$nbId/sheets/$sheetId.sheet';

/// El id de la hoja de una ruta `.sheet`.
String sheetIdOf(String p) {
  final name = p.split('/').last;
  return name.substring(0, name.length - 6);
}
