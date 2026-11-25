import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/export_folder.dart';
import '../../data/storage.dart';
import '../../domain/domain.dart';
import '../../l10n/l10n.dart';
import '../../widgets/menu_row.dart';

// Menús de la barra del cuaderno. Devuelven el valor elegido (los mismos que reciben
// NotebookScreenState.runInsert / runMore) o null.

/// Menú "+" anclado en [at] (esquina inferior derecha del botón).
Future<String?> showInsertMenu(BuildContext context, Offset at, {bool canvas = false}) => showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx - 200, at.dy, at.dx, at.dy),
      items: [
        PopupMenuItem(value: 'pdf', child: MenuRow(Symbols.picture_as_pdf, context.l10n.menuInsertPdf)),
        PopupMenuItem(value: 'voice', child: MenuRow(Symbols.mic, context.l10n.menuInsertVoice)),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'image', child: MenuRow(Symbols.image, context.l10n.menuInsertImage)),
        PopupMenuItem(value: 'camera', child: MenuRow(Symbols.photo_camera, context.l10n.menuInsertCamera)),
        PopupMenuItem(value: 'audio', child: MenuRow(Symbols.music_note, context.l10n.menuInsertAudio)),
        PopupMenuItem(value: 'sticky', child: MenuRow(Symbols.sticky_note_2, context.l10n.menuInsertSticky)),
        if (!canvas) PopupMenuItem(value: 'sheet', child: MenuRow(Symbols.note_add, context.l10n.menuInsertSheet)),
      ],
    );

/// Menú ⋮ anclado en [at]. Abajo, una fila de íconos con keys `more-<valor>`.
/// Con [compact] (teléfono vertical) arriba van lectura, marcador y pantalla completa, que no entran en la barra.
Future<String?> showMoreMenu(BuildContext context, Offset at, Notebook nb, {({bool reading, bool bookmark})? compact}) =>
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx - 260, at.dy, at.dx, at.dy),
      items: [
        if (compact != null) ...[
          PopupMenuItem(
              value: 'reading',
              key: const Key('more-reading'),
              child: MenuRow(Symbols.menu_book, compact.reading ? context.l10n.menuMoreReadingExit : context.l10n.menuMoreReading)),
          PopupMenuItem(
              value: 'bookmark',
              key: const Key('more-bookmark'),
              child: MenuRow(Symbols.bookmark, compact.bookmark ? context.l10n.menuMoreBookmarkRemove : context.l10n.menuMoreBookmarkAdd)),
          PopupMenuItem(
              value: 'fullscreen',
              key: const Key('more-fullscreen'),
              child: MenuRow(Symbols.open_in_full, context.l10n.menuMoreFullscreen)),
          const PopupMenuDivider(),
        ],
        PopupMenuItem(value: 'search', child: MenuRow(Symbols.search, context.l10n.commonSearch)),
        PopupMenuItem(
            value: 'style',
            child: MenuRow(Symbols.palette, nb.canvas ? context.l10n.menuMorePaperColor : context.l10n.menuMoreStyle)),
        PopupMenuItem(value: 'shortcuts', child: MenuRow(Symbols.keyboard, context.l10n.menuMoreShortcuts)),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'export', child: MenuRow(Symbols.ios_share, context.l10n.commonExport)),
        const PopupMenuDivider(),
        _IconRow([
          (Symbols.star, nb.favorite ? context.l10n.menuMoreFavoriteRemove : context.l10n.menuMoreFavoriteAdd, 'fav',
              nb.favorite),
          (nb.pin != null ? Symbols.lock : Symbols.lock_open,
              nb.pin != null ? context.l10n.menuMoreLockRemove : context.l10n.menuMoreLockAdd, 'lock', nb.pin != null),
          (Symbols.share, context.l10n.menuMoreShare, 'share', false),
          (Symbols.print, context.l10n.menuMorePrint, 'print', false),
          (Symbols.delete, context.l10n.menuMoreDeleteNotebook, 'delete', false),
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

/// Hoja "Exportar carpeta": en qué formato va cada cuaderno dentro del .zip. Null si se cierra sin elegir.
Future<FolderExportFormat?> showFolderExportSheet(BuildContext context) {
  final cs = Theme.of(context).colorScheme;
  Widget tile(IconData i, String t, String sub, FolderExportFormat v) => ListTile(
        key: Key('folderExport-${v.name}'),
        leading: Icon(i, weight: 300, color: cs.onSurfaceVariant),
        title: Text(t),
        subtitle: Text(sub),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onTap: () => Navigator.pop(context, v),
      );
  return showModalBottomSheet<FolderExportFormat>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(ctx.l10n.menuExportFolderTitle, style: Theme.of(ctx).textTheme.titleLarge)),
          tile(Symbols.picture_as_pdf, ctx.l10n.menuExportFormatPdf, ctx.l10n.menuExportFolderPdf, FolderExportFormat.pdf),
          tile(Symbols.photo_library, ctx.l10n.menuExportFormatPng, ctx.l10n.menuExportFolderPng,
              FolderExportFormat.png),
          tile(Symbols.archive, ctx.l10n.menuExportFormatVynote, ctx.l10n.menuExportFolderVynote,
              FolderExportFormat.vynote),
        ]),
      ),
    ),
  );
}

/// "Exportar": una sola hoja con todo. Devuelve 'pdf' y 'png' (cuaderno entero), 'vynote', y solo si hay [sheetName]
/// (dentro del cuaderno) 'sheet' (PDF de la hoja que se ve) y 'sheetpng' (su imagen). Keys `export-<valor>`.
///
/// Arriba va el interruptor "Incluir el fondo de la hoja": la elección queda en [tools] y en prefs.json enseguida,
/// y los flujos de exportar la leen de ahí.
Future<String?> showExportSheet(BuildContext context, Storage store, ToolState tools, {String? sheetName}) {
  final cs = Theme.of(context).colorScheme;
  Widget tile(IconData i, String t, String sub, String v) => ListTile(
        key: Key('export-$v'),
        leading: Icon(i, weight: 300, color: cs.onSurfaceVariant),
        title: Text(t),
        subtitle: Text(sub),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onTap: () => Navigator.pop(context, v),
      );
  // Con la tablet en horizontal no entran todas: la hoja puede ocupar toda la altura y se scrollea.
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(ctx.l10n.commonExport, style: Theme.of(ctx).textTheme.titleLarge)),
          StatefulBuilder(
            builder: (ctx, setS) => SwitchListTile(
              key: const Key('exportBg'),
              title: Text(ctx.l10n.menuExportBackground),
              subtitle: Text(ctx.l10n.menuExportBackgroundOff),
              value: tools.exportBackground,
              onChanged: (v) {
                setS(() => tools.exportBackground = v);
                store.savePrefs({'exportBg': v});
              },
            ),
          ),
          tile(Symbols.picture_as_pdf, ctx.l10n.menuExportFormatPdf, ctx.l10n.menuExportAllPdf, 'pdf'),
          tile(Symbols.photo_library, ctx.l10n.menuExportFormatPng, ctx.l10n.menuExportAllPng, 'png'),
          tile(Symbols.archive, ctx.l10n.menuExportVynoteTitle, ctx.l10n.menuExportVynoteHint, 'vynote'),
          if (sheetName != null) ...[
            const Divider(indent: 16, endIndent: 16),
            tile(Symbols.description, ctx.l10n.menuExportSheetPdf, sheetName, 'sheet'),
            tile(Symbols.image, ctx.l10n.menuExportSheetPng, sheetName, 'sheetpng'),
          ],
        ]),
      ),
    ),
  );
}
