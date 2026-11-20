import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/domain.dart';
import '../../rendering/sheet_render.dart';
import '../../widgets/menu_row.dart';

enum SheetAction { rename, addAfter, duplicate, moveUp, moveDown, delete }

/// Panel de hojas a la izquierda: contador, filtros y una miniatura por hoja en dos columnas.
/// Tocar una miniatura lleva a esa hoja; mantenerla apretada abre el menú de la hoja.
class PagesPanel extends StatelessWidget {
  final NotebookDoc doc;
  final ValueListenable<int> current; // hoja que se está viendo
  final ValueListenable<int> structure; // cambia al agregar, mover o borrar hojas (o cambiar su estilo)
  final ValueListenable<int> liveVersion; // cambia al editar la hoja abierta
  final bool onlyBookmarks;
  final VoidCallback onToggleBookmarksFilter, onSearch, onAdd;
  final ValueChanged<int> onOpen, onToggleBookmark;
  final void Function(int sheet, SheetAction action) onAction;

  const PagesPanel({
    super.key,
    required this.doc,
    required this.current,
    required this.structure,
    required this.liveVersion,
    required this.onlyBookmarks,
    required this.onToggleBookmarksFilter,
    required this.onSearch,
    required this.onAdd,
    required this.onOpen,
    required this.onToggleBookmark,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const Key('pagesPanel'),
      width: 300,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(right: BorderSide(color: cs.outlineVariant.withValues(alpha: .6))),
      ),
      child: ListenableBuilder(
        listenable: Listenable.merge([current, structure]),
        builder: (context, _) {
          final n = doc.sheetCount, cur = current.value.clamp(0, n - 1);
          final list = [
            for (var k = 0; k < n; k++)
              if (!onlyBookmarks || doc.sheets[k].bookmark) k
          ];
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 6, 6),
              child: Row(children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${cur + 1}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: cs.onSurface)),
                    TextSpan(text: ' / $n', style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant)),
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
                  tooltip: 'Hoja nueva después de la actual',
                  onPressed: onAdd,
                  icon: Icon(Symbols.note_add, weight: 300, color: cs.onSurfaceVariant),
                ),
              ]),
            ),
            Expanded(
              child: list.isEmpty
                  ? Center(child: Text('No hay hojas marcadas', style: TextStyle(color: cs.onSurfaceVariant)))
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 20),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 12,
                        childAspectRatio: .62,
                      ),
                      itemCount: list.length,
                      itemBuilder: (context, i) => _thumb(context, list[i], cur, cs),
                    ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _thumb(BuildContext context, int k, int cur, ColorScheme cs) {
    final meta = doc.sheets[k], isCur = k == cur, n = k + 1;
    return GestureDetector(
      key: Key('thumb-$n'),
      onTap: () => onOpen(k),
      onLongPressStart: (d) async {
        HapticFeedback.mediumImpact();
        final g = d.globalPosition;
        final v = await showMenu<SheetAction>(
          context: context,
          position: RelativeRect.fromLTRB(g.dx, g.dy, g.dx + 1, g.dy + 1),
          items: [
            const PopupMenuItem(value: SheetAction.rename, child: MenuRow(Symbols.edit, 'Renombrar')),
            const PopupMenuItem(value: SheetAction.addAfter, child: MenuRow(Symbols.note_add, 'Hoja nueva después')),
            const PopupMenuItem(value: SheetAction.duplicate, child: MenuRow(Symbols.content_copy, 'Duplicar')),
            if (k > 0) const PopupMenuItem(value: SheetAction.moveUp, child: MenuRow(Symbols.arrow_upward, 'Mover antes')),
            if (k < doc.sheetCount - 1)
              const PopupMenuItem(value: SheetAction.moveDown, child: MenuRow(Symbols.arrow_downward, 'Mover después')),
            if (doc.sheetCount > 1) ...const [
              PopupMenuDivider(),
              PopupMenuItem(value: SheetAction.delete, child: MenuRow(Symbols.delete, 'Borrar', danger: true)),
            ],
          ],
        );
        if (v != null) onAction(k, v);
      },
      child: Column(children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: isCur ? cs.primary : cs.outlineVariant.withValues(alpha: .6), width: isCur ? 2.5 : 1),
              boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(isCur ? 8 : 9),
              child: Stack(children: [
                Positioned.fill(
                  child: ValueListenableBuilder(
                    valueListenable: liveVersion,
                    // al editar solo se repinta la hoja abierta; con la estructura cambian todas
                    builder: (_, v, _) => CustomPaint(
                        painter: SheetThumbPainter(doc, sheet: k, version: structure.value * 1000003 + (isCur ? v : 0))),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: meta.bookmark ? 'Quitar marcador' : 'Marcar',
                    onPressed: () => onToggleBookmark(k),
                    icon: Icon(Symbols.bookmark,
                        size: 20,
                        fill: meta.bookmark ? 1 : 0,
                        weight: 400,
                        color: meta.bookmark ? cs.primary : const Color(0x55000000)),
                  ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(meta.title.isEmpty ? '$n' : '$n · ${meta.title}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12.5,
                color: isCur ? cs.primary : cs.onSurfaceVariant,
                fontWeight: isCur ? FontWeight.w600 : FontWeight.w400)),
      ]),
    );
  }
}
