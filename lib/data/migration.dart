import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import '../domain/domain.dart';
import 'legacy_page.dart';
import 'storage.dart';

// Migración del formato viejo (índice con páginas + `pages/<id>.json`) al formato 3
// (un cuaderno = una tira de hojas). Se hace sola al leer el índice.

/// Títulos que la app ponía sola: no vale la pena conservarlos como título de hoja.
bool isDefaultPageTitle(String t) {
  t = t.trim();
  return t.isEmpty || t == 'Primera página' || RegExp(r'^Página \d+$').hasMatch(t) || RegExp(r'^\d{2}/\d{2}$').hasMatch(t);
}

/// Convierte todos los cuadernos del índice viejo [old] y devuelve el índice nuevo.
///
/// Es seguro si se interrumpe: el índice nuevo se escribe AL FINAL; mientras siga el viejo,
/// la próxima vez se rehace todo desde cero pisando lo que haya quedado a medias.
/// Las páginas viejas no se borran: quedan en `legacy_pages_backup/`.
Future<NotesIndex> migrateLegacy(Storage store, Map old) async {
  final out = NotesIndex(rev: (old['rev'] ?? 0) as int, last: null);
  final oldLastNb = old['last'];
  for (final n in (old['notebooks'] as List? ?? [])) {
    n as Map;
    final nb = Notebook(n['id'] as String, n['name'] as String,
        updated: (n['updated'] ?? 0) as int, favorite: (n['favorite'] ?? false) as bool, pin: n['pin'] as String?);
    nb.sheets.clear();
    final strokes = <String, Stroke>{}, texts = <String, TextBlock>{}, items = <String, Item>{};
    final lastPage = n['last'];
    var offset = 0; // hojas ya puestas
    for (final p in (n['pages'] as List? ?? [])) {
      p as Map;
      final page = await _readPage(store, p['id'] as String);
      final count = sheetCount(page.h);
      if (offset == 0) {
        nb.bg = page.bg;
        nb.paper = page.paper;
      }
      final title = (p['title'] ?? '') as String;
      for (var k = 0; k < count; k++) {
        nb.sheets.add(SheetMeta(newId('h'),
            title: k == 0 && !isDefaultPageTitle(title) ? title.trim() : '',
            bookmark: k == 0 && (p['bookmark'] ?? false) == true,
            bg: page.bg,
            paper: page.paper));
      }
      if (p['id'] == lastPage) nb.last = offset;
      _append(strokes, texts, items, page, offset * kSheetStep);
      offset += count;
    }
    if (nb.sheets.isEmpty) nb.sheets.add(nb.newSheet());
    final doc = NotebookDoc(nb, strokes: strokes, texts: texts, items: items); // con las hojas ya armadas: todas cargadas
    await store.removeNotebookFiles(nb.id); // restos de un intento anterior
    await store.saveNotebook(doc);
    out.notebooks.add(nb);
    if (n['id'] == oldLastNb) out.last = nb.id;
  }
  out.last ??= out.notebooks.isEmpty ? null : out.notebooks.first.id;
  await store.saveIndex(out); // lo último: recién acá el formato nuevo "existe"
  await archiveLegacyPages(store);
  return out;
}

Future<LegacyPage> _readPage(Storage store, String id) async {
  try {
    return LegacyPage.fromJson(jsonDecode(await File('${store.dir.path}/pages/$id.json').readAsString()) as Map);
  } catch (_) {
    return LegacyPage(id); // falta o está rota: una hoja vacía (como antes)
  }
}

/// Suma lo de [page] al final de los mapas, [dy] más abajo. Las páginas duplicadas conservaban los
/// ids de sus trazos, así que si un id ya está se le da uno nuevo.
void _append(Map<String, Stroke> strokes, Map<String, TextBlock> texts, Map<String, Item> items, LegacyPage page, double dy) {
  final d = Offset(0, dy);
  for (final s in page.strokes.values) {
    final id = strokes.containsKey(s.id) ? newId('s') : s.id;
    strokes[id] = s.moved(d, id: id);
  }
  for (final t in page.texts.values) {
    final id = texts.containsKey(t.id) ? newId('t') : t.id;
    texts[id] = t.copy(id: id, d: d);
  }
  for (final i in page.items.values) {
    final id = items.containsKey(i.id) ? newId('i') : i.id;
    items[id] = i.copy(id: id, d: d);
  }
}

/// Mueve `pages/` a `legacy_pages_backup/` (no borra nada).
Future<void> archiveLegacyPages(Storage store) async {
  final pages = Directory('${store.dir.path}/pages');
  if (!await pages.exists()) return;
  final backup = Directory('${store.dir.path}/legacy_pages_backup');
  await backup.create(recursive: true);
  await for (final e in pages.list()) {
    if (e is File) await e.rename('${backup.path}/${e.uri.pathSegments.last}');
  }
  if (await pages.list().isEmpty) await pages.delete();
}
