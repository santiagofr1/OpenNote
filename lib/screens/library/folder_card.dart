import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/domain.dart';
import '../../l10n/l10n.dart';

/// Tarjeta de una carpeta en la biblioteca: ícono de carpeta, nombre y cuántos cuadernos tiene.
/// Quien la arma le pone la key `folder-<nombre>` (la usan los tests).
class FolderCard extends StatelessWidget {
  final Folder folder;
  final int count; // cuadernos adentro (con subcarpetas)
  final String? location; // ruta donde está (al buscar); reemplaza el conteo
  final bool pressed; // resaltada: menú abierto
  final bool dropping; // un cuaderno arrastrado está encima (por si se usa arrastrar)
  final VoidCallback onTap;
  final VoidCallback? onLongPress; // null: el menú lo abre quien arrastra (DragSource)
  const FolderCard(
      {super.key,
      required this.folder,
      required this.count,
      this.location,
      this.pressed = false,
      this.dropping = false,
      required this.onTap,
      this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tint = folder.color != null ? parseColor(folder.color!) : cs.primary;
    final active = pressed || dropping;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutQuart,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Color.alphaBlend(tint.withValues(alpha: active ? .22 : .12), cs.surfaceContainerHigh),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? tint : tint.withValues(alpha: .35), width: active ? 2 : 1),
        ),
        child: Row(children: [
          Icon(Symbols.folder, size: 36, fill: 1, weight: 300, color: tint),
          const SizedBox(width: 12),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: cs.onSurface)),
              const SizedBox(height: 2),
              Text(location ?? context.l10n.libraryNotebookCount(count),
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            ]),
          ),
        ]),
      ),
    );
  }
}
