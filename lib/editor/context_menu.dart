import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

enum SheetMenuAction { paste, text, selectAll, addSheet, zoomToWidth }

/// Menú al mantener el dedo sobre la hoja, en [global]. Null si se cerró sin elegir.
Future<SheetMenuAction?> showSheetMenu(
  BuildContext context,
  Offset global, {
  required bool canPaste,
  required bool canSelectAll,
  required bool canResetZoom,
}) {
  final cs = Theme.of(context).colorScheme;
  PopupMenuItem<SheetMenuAction> item(SheetMenuAction v, IconData i, String label, {bool enabled = true}) =>
      PopupMenuItem(
        value: v,
        enabled: enabled,
        child: Row(children: [
          Icon(i, size: 20, weight: 300, color: enabled ? cs.onSurfaceVariant : cs.onSurface.withValues(alpha: .3)),
          const SizedBox(width: 12),
          Text(label),
        ]),
      );
  return showMenu<SheetMenuAction>(
    context: context,
    position: RelativeRect.fromLTRB(global.dx, global.dy, global.dx + 1, global.dy + 1),
    items: [
      item(SheetMenuAction.paste, Symbols.content_paste, 'Pegar acá', enabled: canPaste),
      item(SheetMenuAction.text, Symbols.keyboard, 'Escribir acá'),
      item(SheetMenuAction.selectAll, Symbols.select_all, 'Seleccionar todo', enabled: canSelectAll),
      item(SheetMenuAction.addSheet, Symbols.note_add, 'Agregar hoja al final'),
      item(SheetMenuAction.zoomToWidth, Symbols.fit_page_width, 'Zoom al ancho de la hoja', enabled: canResetZoom),
    ],
  );
}
