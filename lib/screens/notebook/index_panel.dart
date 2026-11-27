// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/domain.dart';
import '../../widgets/menu_row.dart';
import '../../l10n/l10n.dart';

enum IndexAction { rename, levelUp, levelDown, remove }

/// Panel del índice a la derecha: los títulos marcados con la herramienta Título, numerados por nivel y con la hoja a la
/// derecha. Tocar una entrada lleva ahí; mantenerla apretada abre su menú (renombrar, cambiar de nivel, quitar).
class IndexPanel extends StatelessWidget {
  final Notebook nb;
  final Listenable refresh; // cambian los títulos, las hojas o la sección abierta
  final ValueChanged<OutlineEntry> onOpen;
  final void Function(OutlineEntry entry, IndexAction action) onAction;
  final VoidCallback onMindMap;
  const IndexPanel(
      {super.key, required this.nb, required this.refresh, required this.onOpen, required this.onAction, required this.onMindMap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const Key('indexPanel'),
      width: 300,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(left: BorderSide(color: cs.outlineVariant.withValues(alpha: .6))),
      ),
      child: ListenableBuilder(
        listenable: refresh,
        builder: (context, _) {
          final all = buildOutline(nb);
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              child: Row(children: [
                Expanded(child: Text(context.l10n.indexTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                if (all.isNotEmpty)
                  IconButton(
                    key: const Key('indexMindMap'),
                    tooltip: context.l10n.indexMindMap,
                    icon: const Icon(Symbols.account_tree),
                    onPressed: onMindMap,
                  ),
              ]),
            ),
            Expanded(
              child: all.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          context.l10n.indexEmpty,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, height: 1.4, color: cs.onSurfaceVariant),
                        ),
                      ),
                    )
                  : ListView(padding: const EdgeInsets.only(bottom: 12), children: _rows(context, cs, all)),
            ),
          ]);
        },
      ),
    );
  }

  List<Widget> _rows(BuildContext context, ColorScheme cs, List<OutlineEntry> all) {
    final several = nb.sections.length > 1;
    final rows = <Widget>[];
    for (final s in nb.sections) {
      final mine = [for (final e in all) if (e.sectionId == s.id) e];
      if (mine.isEmpty) continue;
      if (several) {
        rows.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(s.name,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
        ));
      }
      for (final e in mine) {
        rows.add(_entry(context, cs, e));
      }
    }
    return rows;
  }

  Widget _entry(BuildContext context, ColorScheme cs, OutlineEntry e) {
    final top = e.level == 1;
    return Builder(
      builder: (ctx) => InkWell(
        key: Key('indexEntry-${e.headingId}'),
        onTap: () => onOpen(e),
        onLongPress: () => _menu(ctx, e),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16 + 16.0 * (e.level - 1), 8, 16, 8),
          child: Row(children: [
            Text(e.number,
                style: TextStyle(
                    fontSize: top ? 15 : 14,
                    fontWeight: top ? FontWeight.w600 : FontWeight.w400,
                    fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(width: 8),
            Expanded(
              child: Text(e.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: top ? 15 : 14, fontWeight: top ? FontWeight.w600 : FontWeight.w400)),
            ),
            const SizedBox(width: 8),
            Text('${e.sheet + 1}', style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }

  /// Menú de la entrada, anclado en ella.
  Future<void> _menu(BuildContext ctx, OutlineEntry e) async {
    final box = ctx.findRenderObject() as RenderBox;
    final overlay = Overlay.of(ctx).context.findRenderObject() as RenderBox;
    final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    final v = await showMenu<IndexAction>(
      context: ctx,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      items: [
        PopupMenuItem(value: IndexAction.rename, child: MenuRow(Symbols.edit, ctx.l10n.commonRename)),
        PopupMenuItem(value: IndexAction.levelUp, enabled: e.level > 1, child: MenuRow(Symbols.format_indent_decrease, ctx.l10n.indexLevelUp(e.level - 1))),
        PopupMenuItem(value: IndexAction.levelDown, enabled: e.level < 9, child: MenuRow(Symbols.format_indent_increase, ctx.l10n.indexLevelDown(e.level + 1))),
        const PopupMenuDivider(),
        PopupMenuItem(value: IndexAction.remove, child: MenuRow(Symbols.delete, ctx.l10n.indexRemove, danger: true)),
      ],
    );
    if (v != null) onAction(e, v);
  }
}
