import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

enum SheetMenuAction { paste }

/// Menú al mantener el dedo sobre la hoja (solo si hay algo copiado), en [global]. Null si se cerró sin elegir.
Future<SheetMenuAction?> showSheetMenu(BuildContext context, Offset global) {
  final cs = Theme.of(context).colorScheme;
  return showMenu<SheetMenuAction>(
    context: context,
    position: RelativeRect.fromLTRB(global.dx, global.dy, global.dx + 1, global.dy + 1),
    items: [
      PopupMenuItem(
        value: SheetMenuAction.paste,
        child: Row(children: [
          Icon(Symbols.content_paste, size: 20, weight: 300, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          const Text('Pegar acá'),
        ]),
      ),
    ],
  );
}
