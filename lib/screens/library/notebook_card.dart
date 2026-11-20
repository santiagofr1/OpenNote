import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/domain.dart';
import '../../rendering/sheet_render.dart';

/// Tarjeta de un cuaderno en la biblioteca: miniatura de la primera hoja, nombre y fecha.
/// Quien la arma le pone la key `nb-<nombre>` (la usan los tests).
class NotebookCard extends StatelessWidget {
  final Notebook nb;
  final NotebookDoc? thumb; // primera hoja, null mientras carga
  final bool pressed; // resaltada mientras está abierto su menú
  final String? location; // ruta de su carpeta (al buscar); reemplaza la fecha
  final VoidCallback onTap, onLongPress;
  const NotebookCard(
      {super.key,
      required this.nb,
      this.thumb,
      this.pressed = false,
      this.location,
      required this.onTap,
      required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final n = nb.sheets.length;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedScale(
        scale: pressed ? .95 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutQuart,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: pressed ? cs.primary : cs.outlineVariant.withValues(alpha: .7), width: pressed ? 2 : 1),
                boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, 3))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: AspectRatio(
                  aspectRatio: kW / kSheetH,
                  child: Stack(children: [
                    Positioned.fill(child: _cover(cs)),
                    if (nb.favorite)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: cs.surface.withValues(alpha: .9), shape: BoxShape.circle),
                          child: Icon(Symbols.star, key: Key('fav-${nb.id}'), size: 16, fill: 1, color: cs.primary),
                        ),
                      ),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(nb.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 15, color: cs.onSurface)),
          const SizedBox(height: 2),
          Text(
            location ?? '$n ${n == 1 ? 'hoja' : 'hojas'}${nb.updated > 0 ? ' · ${fmtDate(nb.updated)}' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }

  Widget _cover(ColorScheme cs) {
    // bloqueado: no se muestra el contenido
    if (nb.pin != null) {
      return Container(
        color: cs.surfaceContainerHighest,
        child: Icon(Symbols.lock, size: 36, weight: 200, color: cs.onSurfaceVariant),
      );
    }
    final t = thumb;
    if (t == null) return Container(color: const Color(0xFFFFFEFB));
    return RepaintBoundary(child: CustomPaint(painter: SheetThumbPainter(t)));
  }
}
