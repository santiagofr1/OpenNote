import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/domain.dart';
import '../../widgets/menu_row.dart';

/// Qué se pidió en la lista de secciones.
enum SectionAction { open, create, rename, moveUp, moveDown, delete }

typedef SectionPick = ({SectionAction action, String? id});

/// La lista de secciones, desplegada debajo de [anchor] (el botón del panel de hojas, en coordenadas globales).
/// Tocar una sección la abre; el ⋮ de cada una trae Renombrar / Subir / Bajar / Borrar; al final, "Nueva sección".
/// Devuelve lo elegido (la pantalla del cuaderno lo ejecuta) o null si se cerró.
/// Keys: `section-<id>`, `sectionMenu-<id>` (el ⋮), `sectionRename`, `sectionUp`, `sectionDown`, `sectionDelete`, `newSection`.
Future<SectionPick?> showSectionsList(BuildContext context, Rect anchor, Notebook nb) => showDialog<SectionPick>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        final size = MediaQuery.sizeOf(ctx);
        final width = anchor.width.clamp(260.0, 340.0);
        final left = anchor.left.clamp(8.0, (size.width - width - 8).clamp(8.0, double.infinity));
        return Stack(children: [
          Positioned(
            left: left,
            top: anchor.bottom + 4,
            width: width,
            child: Material(
              key: const Key('sectionsList'),
              color: cs.surfaceContainerHigh,
              elevation: 6,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: (size.height - anchor.bottom - 24).clamp(160.0, 480.0)),
                child: ListView(shrinkWrap: true, padding: const EdgeInsets.symmetric(vertical: 6), children: [
                  for (var i = 0; i < nb.sections.length; i++) _row(ctx, cs, nb, i),
                  const Divider(height: 8),
                  ListTile(
                    key: const Key('newSection'),
                    dense: true,
                    leading: Icon(Symbols.add, weight: 300, color: cs.primary),
                    title: Text('Nueva sección', style: TextStyle(color: cs.primary)),
                    onTap: () => Navigator.pop(ctx, (action: SectionAction.create, id: null)),
                  ),
                ]),
              ),
            ),
          ),
        ]);
      },
    );

Widget _row(BuildContext ctx, ColorScheme cs, Notebook nb, int i) {
  final s = nb.sections[i], isActive = s.id == nb.activeSection.id, n = nb.sheetCountOf(s.id);
  final only = nb.sections.length < 2;
  return ListTile(
    key: Key('section-${s.id}'),
    dense: true,
    selected: isActive,
    selectedTileColor: cs.secondaryContainer.withValues(alpha: .6),
    selectedColor: cs.onSecondaryContainer,
    leading: Icon(isActive ? Symbols.folder_open : Symbols.folder, weight: 300, fill: isActive ? 1 : 0),
    title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text('$n ${n == 1 ? 'hoja' : 'hojas'}'),
    trailing: PopupMenuButton<SectionAction>(
      key: Key('sectionMenu-${s.id}'),
      tooltip: 'Opciones de la sección',
      icon: Icon(Symbols.more_vert, weight: 300, color: cs.onSurfaceVariant),
      onSelected: (a) => Navigator.pop(ctx, (action: a, id: s.id)),
      itemBuilder: (_) => [
        const PopupMenuItem(value: SectionAction.rename, key: Key('sectionRename'), child: MenuRow(Symbols.edit, 'Renombrar')),
        PopupMenuItem(
            value: SectionAction.moveUp, key: const Key('sectionUp'), enabled: i > 0, child: const MenuRow(Symbols.arrow_upward, 'Subir')),
        PopupMenuItem(
            value: SectionAction.moveDown,
            key: const Key('sectionDown'),
            enabled: i < nb.sections.length - 1,
            child: const MenuRow(Symbols.arrow_downward, 'Bajar')),
        const PopupMenuDivider(),
        PopupMenuItem(
            value: SectionAction.delete,
            key: const Key('sectionDelete'),
            enabled: !only,
            child: const MenuRow(Symbols.delete, 'Borrar', danger: true)),
      ],
    ),
    onTap: () => Navigator.pop(ctx, (action: SectionAction.open, id: s.id)),
  );
}

/// Pregunta qué secciones exportar (PDF y PNG): "Todas" o las que se marquen, en el orden de las secciones. Con una sola
/// sección no pregunta. Devuelve los ids elegidos (todos si se dejó "Todas") o null si se canceló.
/// Keys: `exportSectionsAll`, `exportSection-<id>`, `exportSectionsOk`.
Future<Set<String>?> askExportSections(BuildContext context, Notebook nb) async {
  if (nb.sections.length < 2) return {for (final s in nb.sections) s.id};
  final picked = {for (final s in nb.sections) s.id};
  return showDialog<Set<String>>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final all = picked.length == nb.sections.length;
        return AlertDialog(
          scrollable: true,
          title: const Text('¿Qué secciones exportar?'),
          contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CheckboxListTile(
                key: const Key('exportSectionsAll'),
                dense: true,
                value: all,
                title: const Text('Todas'),
                onChanged: (v) => setState(() {
                  picked.clear();
                  if (v ?? false) picked.addAll(nb.sections.map((s) => s.id));
                }),
              ),
              const Divider(height: 1),
              for (final s in nb.sections)
                CheckboxListTile(
                  key: Key('exportSection-${s.id}'),
                  dense: true,
                  value: picked.contains(s.id),
                  title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${nb.sheetCountOf(s.id)} ${nb.sheetCountOf(s.id) == 1 ? 'hoja' : 'hojas'}'),
                  onChanged: (v) => setState(() => (v ?? false) ? picked.add(s.id) : picked.remove(s.id)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
                key: const Key('exportSectionsOk'),
                onPressed: picked.isEmpty ? null : () => Navigator.pop(ctx, Set.of(picked)),
                child: const Text('Exportar')),
          ],
        );
      },
    ),
  );
}
