import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/domain.dart';
import '../../widgets/backgrounds.dart';

/// Colores de papel: valor guardado y nombre (el nombre lo usan los tests como tooltip).
const papers = [
  ('#fffefb', 'Marfil'),
  ('#ffffff', 'Blanco'),
  ('#fbf3e0', 'Crema'),
  ('#f0efeb', 'Gris'),
  ('#eaf3fb', 'Celeste'),
  ('#eef6ec', 'Verde'),
];

/// Estilo del cuaderno ([all]) o configuración de una página: fondo, papel y (solo página) hojas.
/// Devuelve el fondo y papel elegidos, o null si se canceló. Agregar/quitar hojas se aplica
/// a [p] en el momento, aunque después se cancele.
Future<({String bg, String paper})?> showStyleDialog(BuildContext context, PageData p, {required bool all}) async {
  var bg = p.bg, paper = p.paper;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final cs = Theme.of(ctx).colorScheme;
      Widget paperOpt(String c, String label) => Tooltip(
            message: label,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => set(() => paper = c),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: parseColor(c),
                  shape: BoxShape.circle,
                  border: Border.all(color: paper == c ? cs.primary : cs.outlineVariant, width: paper == c ? 2.5 : 1),
                ),
              ),
            ),
          );
      final title = TextStyle(fontWeight: FontWeight.w500, color: cs.onSurface);
      return AlertDialog(
        title: Text(all ? 'Estilo del cuaderno' : 'Configuración de página'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(all ? 'Se aplica a todas las páginas' : 'Solo a esta página', style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            Text('Fondo', style: title),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (v, i, label) in backgrounds)
                ChoiceChip(
                  avatar: Icon(i, size: 18, weight: 300),
                  label: Text(label),
                  selected: bg == v,
                  onSelected: (_) => set(() => bg = v),
                ),
            ]),
            const SizedBox(height: 18),
            Text('Color del papel', style: title),
            const SizedBox(height: 8),
            Wrap(spacing: 10, children: [for (final (c, label) in papers) paperOpt(c, label)]),
            if (!all) ...[
              const SizedBox(height: 18),
              Text('Hojas en esta página: ${sheetCount(p.h)}', style: title),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: () => set(() => p.addSheets(1)),
                  icon: const Icon(Symbols.add, size: 18),
                  label: const Text('Agregar hoja'),
                ),
                OutlinedButton.icon(
                  onPressed: sheetCount(p.h) > 1 && p.lastSheetEmpty ? () => set(() => p.addSheets(-1)) : null,
                  icon: const Icon(Symbols.remove, size: 18),
                  label: const Text('Quitar la última (vacía)'),
                ),
              ]),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(key: const Key('styleOk'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Aplicar')),
        ],
      );
    }),
  );
  return ok == true ? (bg: bg, paper: paper) : null;
}
