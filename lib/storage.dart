import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'model.dart';

/// Guarda todo como archivos JSON:
///   <dir>/index.json         cuadernos y páginas
///   <dir>/pages/<id>.json    contenido de cada página
/// Mismo formato que el servidor web, para poder sincronizar más adelante.
class Storage {
  late final Directory dir;

  Future<void> init() async {
    Directory? base;
    if (Platform.isAndroid) base = await getExternalStorageDirectory();
    base ??= await getApplicationDocumentsDirectory();
    dir = Directory('${base.path}/apuntes');
    await Directory('${dir.path}/pages').create(recursive: true);
  }

  File get _index => File('${dir.path}/index.json');
  File _page(String id) => File('${dir.path}/pages/$id.json');

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
}
