import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Barrita oscura sobre la selección: copiar, cortar, duplicar, eliminar, deseleccionar.
class SelectionMenu extends StatelessWidget {
  final VoidCallback onCopy, onCut, onDuplicate, onDelete, onClose;
  const SelectionMenu({
    super.key,
    required this.onCopy,
    required this.onCut,
    required this.onDuplicate,
    required this.onDelete,
    required this.onClose,
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
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(i, size: 19, weight: 300, color: fg),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: fg, fontSize: 14)),
            ]),
          ),
        );
    return Material(
      color: cs.inverseSurface,
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          b(Symbols.content_copy, 'Copiar', onCopy),
          b(Symbols.content_cut, 'Cortar', onCut),
          b(Symbols.control_point_duplicate, 'Duplicar', onDuplicate),
          b(Symbols.delete, 'Eliminar', onDelete),
          IconButton(
              onPressed: onClose,
              icon: Icon(Symbols.close, size: 19, weight: 300, color: fg.withValues(alpha: .75)),
              tooltip: 'Deseleccionar'),
        ]),
      ),
    );
  }
}
