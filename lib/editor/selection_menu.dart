import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../domain/domain.dart';
import '../l10n/l10n.dart';

/// Barrita oscura sobre la selección: copiar, cortar, duplicar, orden (capas), eliminar, deseleccionar.
class SelectionMenu extends StatelessWidget {
  final VoidCallback onCopy, onCut, onDuplicate, onDelete, onClose;
  final ValueChanged<ZMove> onOrder;

  /// "Enderezar": solo aparece si hay un texto con escala o giro.
  final VoidCallback? onStraighten;

  /// "Renombrar": solo aparece con un único audio elegido.
  final VoidCallback? onRename;

  /// "Link": convierte lo elegido en un link (si no hay ninguno). "Editar link" / "Quitar link": con un único link elegido.
  final VoidCallback? onLink, onEditLink, onRemoveLink;

  const SelectionMenu({
    super.key,
    required this.onCopy,
    required this.onCut,
    required this.onDuplicate,
    required this.onDelete,
    required this.onClose,
    required this.onOrder,
    this.onStraighten,
    this.onRename,
    this.onLink,
    this.onEditLink,
    this.onRemoveLink,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = cs.onInverseSurface;
    Widget b(IconData i, String label, VoidCallback f) => InkWell(
      onTap: f,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(i, size: 19, weight: 300, color: fg),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: fg, fontSize: 14)),
          ],
        ),
      ),
    );
    Widget order() => PopupMenuButton<ZMove>(
      key: const Key('selOrder'),
      tooltip: context.l10n.selOrder,
      onSelected: onOrder,
      position: PopupMenuPosition.under,
      itemBuilder: (_) => [
        PopupMenuItem(value: ZMove.front, child: Text(context.l10n.selFront)),
        PopupMenuItem(value: ZMove.up, child: Text(context.l10n.selUp)),
        PopupMenuItem(value: ZMove.down, child: Text(context.l10n.selDown)),
        PopupMenuItem(value: ZMove.back, child: Text(context.l10n.selBack)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Symbols.layers, size: 19, weight: 300, color: fg),
            const SizedBox(width: 6),
            Text(context.l10n.selOrder, style: TextStyle(color: fg, fontSize: 14)),
          ],
        ),
      ),
    );
    return Material(
      color: cs.inverseSurface,
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            b(Symbols.content_copy, context.l10n.commonCopy, onCopy),
            b(Symbols.content_cut, context.l10n.formatCut, onCut),
            b(Symbols.control_point_duplicate, context.l10n.selDuplicate, onDuplicate),
            order(),
            if (onRename != null) b(Symbols.edit, context.l10n.commonRename, onRename!),
            if (onLink != null) b(Symbols.link, context.l10n.selLink, onLink!),
            if (onEditLink != null) b(Symbols.edit, context.l10n.selEditLink, onEditLink!),
            if (onRemoveLink != null) b(Symbols.link_off, context.l10n.selRemoveLink, onRemoveLink!),
            if (onStraighten != null) b(Symbols.format_align_left, context.l10n.selStraighten, onStraighten!),
            b(Symbols.delete, context.l10n.selDelete, onDelete),
            IconButton(
              onPressed: onClose,
              icon: Icon(Symbols.close, size: 19, weight: 300, color: fg.withValues(alpha: .75)),
              tooltip: context.l10n.selDeselect,
            ),
          ],
        ),
      ),
    );
  }
}
