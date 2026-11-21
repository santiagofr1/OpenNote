import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/domain.dart';
import '../../widgets/menu_row.dart';

// Menús de la barra del cuaderno. Devuelven el valor elegido (los mismos que reciben
// NotebookScreenState.runInsert / runMore) o null.

/// Menú "+" anclado en [at] (esquina inferior derecha del botón).
Future<String?> showInsertMenu(BuildContext context, Offset at) => showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx - 200, at.dy, at.dx, at.dy),
      items: const [
        PopupMenuItem(value: 'pdf', child: MenuRow(Symbols.picture_as_pdf, 'PDF')),
        PopupMenuItem(value: 'voice', child: MenuRow(Symbols.mic, 'Grabación de voz')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'image', child: MenuRow(Symbols.image, 'Imagen')),
        PopupMenuItem(value: 'camera', child: MenuRow(Symbols.photo_camera, 'Cámara')),
        PopupMenuItem(value: 'audio', child: MenuRow(Symbols.music_note, 'Archivo de audio')),
        PopupMenuItem(value: 'sticky', child: MenuRow(Symbols.sticky_note_2, 'Nota adhesiva')),
        PopupMenuItem(value: 'sheet', child: MenuRow(Symbols.note_add, 'Hoja nueva')),
      ],
    );

/// Menú ⋮ anclado en [at]. Abajo, una fila de íconos con keys `more-<valor>`.
Future<String?> showMoreMenu(BuildContext context, Offset at, Notebook nb) => showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx - 260, at.dy, at.dx, at.dy),
      items: [
        const PopupMenuItem(value: 'search', child: MenuRow(Symbols.search, 'Buscar')),
        const PopupMenuItem(value: 'style', child: MenuRow(Symbols.palette, 'Estilo de hoja')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'saveas', child: MenuRow(Symbols.save_as, 'Guardar como')),
        const PopupMenuItem(value: 'opennote', child: MenuRow(Symbols.archive, 'Exportar cuaderno (.opennote)')),
        const PopupMenuDivider(),
        _IconRow([
          (Symbols.star, nb.favorite ? 'Quitar de favoritos' : 'Favorito', 'fav', nb.favorite),
          (nb.pin != null ? Symbols.lock : Symbols.lock_open, nb.pin != null ? 'Quitar bloqueo' : 'Bloquear con PIN', 'lock',
              nb.pin != null),
          (Symbols.share, 'Compartir', 'share', false),
          (Symbols.print, 'Imprimir', 'print', false),
          (Symbols.delete, 'Borrar cuaderno', 'delete', false),
        ]),
      ],
    );

/// Fila de íconos al pie del menú ⋮: (ícono, tooltip, valor, activo).
class _IconRow extends PopupMenuEntry<String> {
  final List<(IconData, String, String, bool)> items;
  const _IconRow(this.items);
  @override
  double get height => 56;
  @override
  bool represents(String? value) => false;
  @override
  State<_IconRow> createState() => _IconRowState();
}

class _IconRowState extends State<_IconRow> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (final (icon, tip, value, on) in widget.items)
          IconButton(
            key: Key('more-$value'),
            tooltip: tip,
            onPressed: () => Navigator.pop(context, value),
            icon: Icon(icon,
                weight: 300,
                fill: on ? 1 : 0,
                color: value == 'delete' ? cs.error : (on ? cs.primary : cs.onSurfaceVariant)),
          ),
      ]),
    );
  }
}

/// "Guardar como": PDF del cuaderno ('nb'), PDF de la hoja que se ve ('sheet') o PNG de esa hoja ('png').
Future<String?> showSaveAsSheet(BuildContext context, {required String sheetName}) {
  final cs = Theme.of(context).colorScheme;
  Widget tile(IconData i, String t, String sub, String v) => ListTile(
        leading: Icon(i, weight: 300, color: cs.onSurfaceVariant),
        title: Text(t),
        subtitle: Text(sub),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onTap: () => Navigator.pop(context, v),
      );
  return showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text('Guardar como', style: Theme.of(ctx).textTheme.titleLarge)),
          tile(Symbols.picture_as_pdf, 'PDF del cuaderno', 'Todas las hojas', 'nb'),
          tile(Symbols.description, 'PDF de esta hoja', sheetName, 'sheet'),
          tile(Symbols.image, 'Imagen (PNG)', 'La hoja que estás viendo', 'png'),
        ]),
      ),
    ),
  );
}
