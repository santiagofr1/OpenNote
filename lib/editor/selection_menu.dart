import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../domain/domain.dart';

/// Barrita oscura sobre la selección: copiar, cortar, duplicar, orden (capas), eliminar, deseleccionar.
class SelectionMenu extends StatelessWidget {
  final VoidCallback onCopy, onCut, onDuplicate, onDelete, onClose;
  final ValueChanged<ZMove> onOrder;

  /// Filtros "Solo resaltador" / "Sin resaltador": solo se pasan si la selección tiene resaltador y algo más.
  final VoidCallback? onOnlyHl, onOnlyInk;
  const SelectionMenu({
    super.key,
    required this.onCopy,
    required this.onCut,
    required this.onDuplicate,
    required this.onDelete,
    required this.onClose,
    required this.onOrder,
    this.onOnlyHl,
    this.onOnlyInk,
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
    // filtros: botones con texto, en una fila aparte (para que se vean y la barrita entre en el ancho)
    Widget only(Key k, IconData i, String label, VoidCallback f) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
      child: TextButton.icon(
        key: k,
        onPressed: f,
        style: TextButton.styleFrom(
          backgroundColor: fg.withValues(alpha: .16),
          foregroundColor: fg,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        icon: Icon(i, size: 19, weight: 300, color: fg),
        label: Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
    Widget order() => PopupMenuButton<ZMove>(
      key: const Key('selOrder'),
      tooltip: 'Orden',
      onSelected: onOrder,
      position: PopupMenuPosition.under,
      itemBuilder: (_) => const [
        PopupMenuItem(value: ZMove.front, child: Text('Traer al frente')),
        PopupMenuItem(value: ZMove.up, child: Text('Subir uno')),
        PopupMenuItem(value: ZMove.down, child: Text('Bajar uno')),
        PopupMenuItem(value: ZMove.back, child: Text('Enviar al fondo')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Symbols.layers, size: 19, weight: 300, color: fg),
            const SizedBox(width: 6),
            Text('Orden', style: TextStyle(color: fg, fontSize: 14)),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onOnlyHl != null || onOnlyInk != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onOnlyHl != null)
                    only(
                      const Key('selOnlyHl'),
                      Symbols.ink_highlighter,
                      'Solo resaltador',
                      onOnlyHl!,
                    ),
                  if (onOnlyInk != null)
                    only(
                      const Key('selNoHl'),
                      Symbols.layers_clear,
                      'Sin resaltador',
                      onOnlyInk!,
                    ),
                ],
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                b(Symbols.content_copy, 'Copiar', onCopy),
                b(Symbols.content_cut, 'Cortar', onCut),
                b(Symbols.control_point_duplicate, 'Duplicar', onDuplicate),
                order(),
                b(Symbols.delete, 'Eliminar', onDelete),
                IconButton(
                  onPressed: onClose,
                  icon: Icon(
                    Symbols.close,
                    size: 19,
                    weight: 300,
                    color: fg.withValues(alpha: .75),
                  ),
                  tooltip: 'Deseleccionar',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
