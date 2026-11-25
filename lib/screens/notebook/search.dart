import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/storage.dart';
import '../../domain/domain.dart';
import '../../l10n/l10n.dart';

/// Un resultado: texto o nota adhesiva ([id]) o el título de la hoja ([id] null).
class SearchHit {
  final int sheet; // índice de la hoja
  final SheetMeta meta;
  final String? id;
  final String snippet;
  SearchHit(this.sheet, this.meta, this.id, this.snippet);
}

/// Busca [query] (sin importar mayúsculas) en los textos, notas adhesivas y títulos de las hojas
/// del cuaderno, en el orden en que aparecen.
List<SearchHit> searchNotebook(NotebookDoc doc, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return [];
  // [orden en la hoja, y, hit]: dentro de cada hoja, de arriba hacia abajo
  final found = <(int, double, SearchHit)>[];
  for (final t in doc.texts.values) {
    final i = t.text.toLowerCase().indexOf(q);
    final k = doc.sheetOfY(t.y);
    if (i >= 0) found.add((k, t.y, SearchHit(k, doc.sheets[k], t.id, snippet(t.text, i, q.length))));
  }
  for (final it in doc.items.values) {
    final i = it.text.toLowerCase().indexOf(q);
    final k = doc.sheetOfY(it.y);
    if (it.type == 'sticky' && i >= 0) found.add((k, it.y, SearchHit(k, doc.sheets[k], it.id, snippet(it.text, i, q.length))));
  }
  for (var k = 0; k < doc.sheetCount; k++) {
    final m = doc.sheets[k];
    if (m.title.toLowerCase().contains(q)) found.add((k, -1, SearchHit(k, m, null, 'Título: ${m.title}')));
  }
  found.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  return [for (final f in found) f.$3];
}

/// Como [searchNotebook] pero en TODAS las hojas: las cargadas se buscan en memoria y las otras se leen de disco
/// de a una (solo sus textos, en otro isolate), sin dejarlas cargadas ni juntar todo el cuaderno en memoria.
Future<List<SearchHit>> searchNotebookAll(Storage store, NotebookDoc doc, String query) async {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return [];
  final found = <(int, double, SearchHit)>[];
  // lo de las hojas cargadas (y los títulos de todas): en memoria, incluye lo que se editó y todavía no se guardó
  final inMemory = searchNotebook(doc, query);
  // el resto, de disco; se decide hoja por hoja (una puede cargarse mientras se busca)
  for (var k = 0; k < doc.sheetCount; k++) {
    final m = doc.sheets[k];
    if (doc.isLoaded(m.id)) continue;
    List<SheetText> texts;
    try {
      texts = await store.readSheetTexts(doc.nb, m);
    } catch (_) {
      continue; // no se pudo leer: se sigue con las demás
    }
    if (doc.isLoaded(m.id)) continue; // se cargó mientras se leía: ya está en memoria
    final k2 = doc.indexOfSheet(m.id);
    if (k2 < 0) continue;
    for (final t in texts) {
      final i = t.text.toLowerCase().indexOf(q);
      if (i >= 0) found.add((k2, t.y, SearchHit(k2, m, t.id, snippet(t.text, i, q.length))));
    }
  }
  found.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  // por hoja: primero lo de memoria (el título y, si está cargada, todo lo suyo) y después lo de disco
  final all = <(int, int, int, SearchHit)>[
    for (final (i, h) in inMemory.indexed) (h.sheet, 0, i, h),
    for (final (i, f) in found.indexed) (f.$1, 1, i, f.$3),
  ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$3.compareTo(b.$3));
  return [for (final h in all) h.$4];
}

/// Pedacito de [s] alrededor de lo encontrado (en [i], de largo [n]), en una línea.
String snippet(String s, int i, int n) {
  final a = (i - 30).clamp(0, s.length), b = (i + n + 50).clamp(0, s.length);
  return '${a > 0 ? '…' : ''}${s.substring(a, b).replaceAll('\n', ' ')}${b < s.length ? '…' : ''}';
}

/// Lista flotante de resultados debajo del campo de búsqueda.
class SearchResults extends StatelessWidget {
  final String query;
  final List<SearchHit> hits;
  final ValueChanged<SearchHit> onTap;
  const SearchResults({super.key, required this.query, required this.hits, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final q = query.trim();
    Widget note(String t) => Padding(padding: const EdgeInsets.all(18), child: Text(t, style: TextStyle(color: cs.onSurfaceVariant)));
    return Material(
      color: cs.surfaceContainerHigh,
      elevation: 6,
      shadowColor: Colors.black45,
      borderRadius: BorderRadius.circular(18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420),
        child: q.isEmpty
            ? note(context.l10n.searchHint)
            : hits.isEmpty
                ? note(context.l10n.searchNone(q))
                : ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(6),
                    children: [
                      for (final h in hits)
                        ListTile(
                          key: Key('hit-${h.id ?? h.meta.id}'),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          leading: Icon(Symbols.description, weight: 300, color: cs.onSurfaceVariant),
                          title: Text(h.meta.title.isEmpty ? context.l10n.sheetLabel(h.sheet + 1) : context.l10n.sheetLabelTitled(h.sheet + 1, h.meta.title),
              style: const TextStyle(fontWeight: FontWeight.w500)),
                          subtitle: Text(h.id == null ? context.l10n.searchTitleSnippet(h.meta.title) : h.snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
                          onTap: () => onTap(h),
                        ),
                    ],
                  ),
      ),
    );
  }
}
