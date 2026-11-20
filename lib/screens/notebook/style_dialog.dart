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

/// Estilo del cuaderno: fondo y color de papel de TODAS las hojas (y de las nuevas).
/// Devuelve lo elegido, o null si se canceló. Agregar/quitar hojas al final se aplica a [doc]
/// en el momento, aunque después se cancele.
Future<({String bg, String paper})?> showStyleDialog(BuildContext context, NotebookDoc doc) async {
  var bg = doc.nb.bg, paper = doc.nb.paper;
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
        title: const Text('Estilo del cuaderno'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Se aplica a todas las hojas', style: TextStyle(color: cs.onSurfaceVariant)),
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
            const SizedBox(height: 18),
            Text('Hojas del cuaderno: ${doc.sheetCount}', style: title),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () => set(doc.addSheet),
                icon: const Icon(Symbols.add, size: 18),
                label: const Text('Agregar hoja al final'),
              ),
              OutlinedButton.icon(
                onPressed: doc.sheetCount > 1 && doc.lastSheetEmpty ? () => set(doc.removeLastSheetIfEmpty) : null,
                icon: const Icon(Symbols.remove, size: 18),
                label: const Text('Quitar la última (vacía)'),
              ),
            ]),
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
