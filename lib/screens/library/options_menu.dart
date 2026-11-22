import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

/// Opción del menú: (ícono, texto, valor, key). La de valor 'delete' va con un separador y en rojo.
typedef MenuItem = (IconData, String, String, String?);

/// Menú de opciones anclado a una tarjeta de la biblioteca.
/// No es una ruta modal (esas cancelan los punteros y cortarían el arrastre del dedo que sigue apoyado): es un
/// OverlayEntry con una barrera que lo cierra al tocar afuera.
class OptionsMenu {
  OverlayEntry? _entry;
  Completer<String?>? _done;

  bool get isOpen => _entry != null;

  /// Cierra el menú (si hay uno) sin elegir nada.
  void close() => _closeWith(null);

  void _closeWith(String? value) {
    _entry?.remove();
    _entry = null;
    final c = _done;
    _done = null;
    if (c != null && !c.isCompleted) c.complete(value);
  }

  /// Muestra el menú anclado a la tarjeta [card], con [title] arriba. Devuelve el valor elegido, o null si se cerró.
  /// "Borrar" va al final y en rojo.
  Future<String?> show(BuildContext context, BuildContext card, String title, List<MenuItem> items) {
    close();
    final cs = Theme.of(context).colorScheme;
    final box = card.findRenderObject() as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final done = _done = Completer<String?>();
    const width = 270.0;
    final height = 60.0 + items.length * 52 + 12;
    final entry = OverlayEntry(
      builder: (ctx) {
        final size = MediaQuery.sizeOf(ctx);
        final pad = MediaQuery.paddingOf(ctx);
        final left = (rect.center.dx - width / 2).clamp(8.0, max(8.0, size.width - width - 8)).toDouble();
        // debajo de la tarjeta si entra; si no, arriba; si tampoco, pegado al borde de abajo
        var top = rect.bottom + 6;
        if (top + height > size.height - pad.bottom - 8) top = rect.top - height - 6;
        top = top.clamp(pad.top + 8, max(pad.top + 8, size.height - pad.bottom - height - 8)).toDouble();
        return Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              key: const Key('menuBarrier'),
              behavior: HitTestBehavior.opaque,
              onTap: close,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: left,
            top: top,
            width: width,
            child: Material(
              key: const Key('optionsMenu'),
              elevation: 8,
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Text(title, style: Theme.of(ctx).textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  for (final (icon, label, value, key) in items) ...[
                    if (value == 'delete') const Divider(height: 8, indent: 12, endIndent: 12),
                    ListTile(
                      key: key == null ? null : Key(key),
                      dense: true,
                      leading: Icon(icon, weight: 300, color: value == 'delete' ? cs.error : cs.onSurfaceVariant),
                      title: Text(label, style: TextStyle(color: value == 'delete' ? cs.error : cs.onSurface)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      onTap: () => _closeWith(value),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ]);
      },
    );
    _entry = entry;
    Overlay.of(context).insert(entry);
    return done.future;
  }
}
