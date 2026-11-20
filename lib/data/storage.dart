import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/domain.dart';

/// Guarda todo como archivos JSON:
///   `<dir>/index.json`        cuadernos y páginas
///   `<dir>/prefs.json`        herramientas elegidas
///   `<dir>/pages/<id>.json`   contenido de cada página
///   `<dir>/media/`            imágenes y audios
/// Mismo formato que el servidor web, para poder sincronizar más adelante.
class Storage {
  /// [root]: carpeta propia (los tests usan una temporal para no tocar tus cuadernos)
  Storage({this.root});
  final Directory? root;
  late final Directory dir;

  Future<void> init() async {
    dir = root ?? Directory('${(await _defaultBase()).path}/apuntes');
    await Directory('${dir.path}/pages').create(recursive: true);
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

  File get _index => File('${dir.path}/index.json');
  File get _prefs => File('${dir.path}/prefs.json');
  File _page(String id) => File('${dir.path}/pages/$id.json');

  /// Escribe a un temporal y renombra: si se corta a la mitad, el archivo viejo queda entero.
  Future<void> _write(File f, Object data) async {
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(f.path);
  }

  Future<NotesIndex> loadIndex() async {
    try {
      return NotesIndex.fromJson(jsonDecode(await _index.readAsString()) as Map);
    } catch (_) {
      // primera vez: cuaderno de ejemplo
      final idx = NotesIndex();
      final nb = Notebook(newId('n'), 'Mi cuaderno', []);
      final page = PageData(newId('p'));
      nb.pages.add(PageRef(page.id, 'Primera página'));
      idx.notebooks.add(nb);
      idx.last = page.id;
      await savePage(page);
      await saveIndex(idx);
      return idx;
    }
  }

  Future<void> saveIndex(NotesIndex idx) {
    idx.rev++;
    return _write(_index, idx.toJson());
  }

  Future<PageData> loadPage(String id) async {
    try {
      return PageData.fromJson(jsonDecode(await _page(id).readAsString()) as Map);
    } catch (_) {
      return PageData(id);
    }
  }

  Future<void> savePage(PageData p) {
    p.rev++;
    p.updated = DateTime.now().millisecondsSinceEpoch;
    return _write(_page(p.id), p.toJson());
  }

  Future<void> deletePage(String id) async {
    final f = _page(id);
    if (await f.exists()) await f.delete();
  }

  /// Borra las páginas del cuaderno y lo saca del índice.
  Future<void> deleteNotebook(NotesIndex idx, Notebook nb) async {
    for (final p in nb.pages) {
      await deletePage(p.id);
    }
    idx.notebooks.remove(nb);
    await saveIndex(idx);
  }

  Future<Map?> loadPrefs() async {
    try {
      return jsonDecode(await _prefs.readAsString()) as Map;
    } catch (_) {
      return null;
    }
  }

  Future<void> savePrefs(Map<String, dynamic> p) => _write(_prefs, p);
}
