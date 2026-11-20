import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/domain.dart';
import '../../rendering/sheet_render.dart';
import '../../widgets/menu_row.dart';

enum PageAction { rename, duplicate, moveUp, moveDown, delete }

/// Panel de páginas a la izquierda: contador, filtros y miniaturas en dos columnas.
class PagesPanel extends StatelessWidget {
  final Notebook nb;
  final String? currentId;
  final bool onlyBookmarks;
  final Future<PageData> Function(String id) thumb;
  final ValueListenable<int> liveVersion; // cambia al editar la página abierta
  final VoidCallback onToggleBookmarksFilter, onSearch, onAddPage;
  final ValueChanged<PageRef> onOpen, onToggleBookmark;
  final void Function(PageRef ref, PageAction action) onAction;

  const PagesPanel({
    super.key,
    required this.nb,
    required this.currentId,
    required this.onlyBookmarks,
    required this.thumb,
    required this.liveVersion,
    required this.onToggleBookmarksFilter,
    required this.onSearch,
    required this.onAddPage,
    required this.onOpen,
    required this.onToggleBookmark,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = onlyBookmarks ? nb.pages.where((p) => p.bookmark).toList() : nb.pages;
    final cur = nb.pages.indexWhere((p) => p.id == currentId);
    return Container(
      key: const Key('pagesPanel'),
      width: 300,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(right: BorderSide(color: cs.outlineVariant.withValues(alpha: .6))),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 6, 6),
          child: Row(children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(text: '${cur + 1}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: cs.onSurface)),
                TextSpan(text: ' / ${nb.pages.length}', style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
              ]),
              key: const Key('pageCounter'),
            ),
            const Spacer(),
            IconButton(
              tooltip: onlyBookmarks ? 'Ver todas' : 'Solo marcadas',
              isSelected: onlyBookmarks,
              onPressed: onToggleBookmarksFilter,
              icon: Icon(Symbols.bookmark,
                  weight: 300, fill: onlyBookmarks ? 1 : 0, color: onlyBookmarks ? cs.primary : cs.onSurfaceVariant),
            ),
            IconButton(
              tooltip: 'Buscar',
              onPressed: onSearch,
              icon: Icon(Symbols.search, weight: 300, color: cs.onSurfaceVariant),
            ),
            IconButton(
              key: const Key('addPage'),
              tooltip: 'Página nueva',
              onPressed: onAddPage,
              icon: Icon(Symbols.note_add, weight: 300, color: cs.onSurfaceVariant),
            ),
          ]),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(child: Text('No hay páginas marcadas', style: TextStyle(color: cs.onSurfaceVariant)))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 12,
                    childAspectRatio: .62,
                  ),
                  itemCount: list.length,
                  itemBuilder: (context, i) => _thumb(context, list[i], cs),
                ),
        ),
      ]),
    );
  }

  Widget _thumb(BuildContext context, PageRef ref, ColorScheme cs) {
    final cur = ref.id == currentId;
    final n = nb.pages.indexOf(ref) + 1;
    return GestureDetector(
      key: Key('thumb-$n'),
      onTap: () => onOpen(ref),
      onLongPressStart: (d) async {
        HapticFeedback.mediumImpact();
        final g = d.globalPosition;
        final v = await showMenu<PageAction>(
          context: context,
          position: RelativeRect.fromLTRB(g.dx, g.dy, g.dx + 1, g.dy + 1),
          items: [
            const PopupMenuItem(value: PageAction.rename, child: MenuRow(Symbols.edit, 'Renombrar')),
            const PopupMenuItem(value: PageAction.duplicate, child: MenuRow(Symbols.content_copy, 'Duplicar')),
            if (n > 1) const PopupMenuItem(value: PageAction.moveUp, child: MenuRow(Symbols.arrow_upward, 'Mover antes')),
            if (n < nb.pages.length)
              const PopupMenuItem(value: PageAction.moveDown, child: MenuRow(Symbols.arrow_downward, 'Mover después')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: PageAction.delete, child: MenuRow(Symbols.delete, 'Borrar', danger: true)),
          ],
        );
        if (v != null) onAction(ref, v);
      },
      child: Column(children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cur ? cs.primary : cs.outlineVariant.withValues(alpha: .6), width: cur ? 2.5 : 1),
              boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(cur ? 8 : 9),
              child: Stack(children: [
                Positioned.fill(
                  child: FutureBuilder<PageData>(
                    future: thumb(ref.id),
                    builder: (_, snap) => snap.data == null
                        ? Container(color: const Color(0xFFFFFEFB))
                        : ValueListenableBuilder(
                            valueListenable: liveVersion,
                            // solo la abierta se repinta al editar
                            builder: (_, v, _) => CustomPaint(painter: SheetThumbPainter(snap.data!, cur ? v : 0)),
                          ),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: ref.bookmark ? 'Quitar marcador' : 'Marcar',
                    onPressed: () => onToggleBookmark(ref),
                    icon: Icon(Symbols.bookmark,
                        size: 20,
                        fill: ref.bookmark ? 1 : 0,
                        weight: 400,
                        color: ref.bookmark ? cs.primary : const Color(0x55000000)),
                  ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text('$n · ${ref.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12.5,
                color: cur ? cs.primary : cs.onSurfaceVariant,
                fontWeight: cur ? FontWeight.w600 : FontWeight.w400)),
      ]),
    );
  }
}
