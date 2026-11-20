import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/domain.dart';

/// Un resultado: texto o nota adhesiva ([id]) o el título de la página ([id] null).
class SearchHit {
  final PageRef page;
  final String? id;
  final String snippet;
  SearchHit(this.page, this.id, this.snippet);
}

/// Busca [query] (sin importar mayúsculas) en los textos, notas adhesivas y títulos del cuaderno.
Future<List<SearchHit>> searchNotebook(Notebook nb, Future<PageData> Function(String id) load, String query) async {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return [];
  final out = <SearchHit>[];
  for (final ref in nb.pages) {
    final p = await load(ref.id);
    for (final t in p.texts.values) {
      final i = t.text.toLowerCase().indexOf(q);
      if (i >= 0) out.add(SearchHit(ref, t.id, snippet(t.text, i, q.length)));
    }
    for (final it in p.items.values) {
      final i = it.text.toLowerCase().indexOf(q);
      if (it.type == 'sticky' && i >= 0) out.add(SearchHit(ref, it.id, snippet(it.text, i, q.length)));
    }
    if (ref.title.toLowerCase().contains(q)) out.add(SearchHit(ref, null, 'Título: ${ref.title}'));
  }
  return out;
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
            ? note('Buscá en los textos, notas adhesivas y títulos de páginas')
            : hits.isEmpty
                ? note('Sin resultados para "$q"')
                : ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(6),
                    children: [
                      for (final h in hits)
                        ListTile(
                          key: Key('hit-${h.id ?? h.page.id}'),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          leading: Icon(Symbols.description, weight: 300, color: cs.onSurfaceVariant),
                          title: Text(h.page.title, style: const TextStyle(fontWeight: FontWeight.w500)),
                          subtitle: Text(h.snippet, maxLines: 2, overflow: TextOverflow.ellipsis),
                          onTap: () => onTap(h),
                        ),
                    ],
                  ),
      ),
    );
  }
}
