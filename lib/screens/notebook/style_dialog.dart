import 'package:flutter/material.dart';

import '../../domain/domain.dart';
import '../../widgets/backgrounds.dart';
import '../../widgets/paper_preview.dart';

/// Colores de papel: valor guardado y nombre (el nombre lo usan los tests como tooltip).
const papers = [
  ('#fffefb', 'Marfil'),
  ('#ffffff', 'Blanco'),
  ('#fbf3e0', 'Crema'),
  ('#f0efeb', 'Gris'),
  ('#eaf3fb', 'Celeste'),
  ('#eef6ec', 'Verde'),
];

/// Lo elegido en el diálogo: [all] aplica a todas las hojas (y a las nuevas); si no, solo a la hoja visible.
typedef StyleChoice = ({String bg, String paper, double spacing, bool all});

/// Estilo de hoja: fondo, color de papel y espaciado (en mm de A4), con vista previa.
/// Parte del estilo de la hoja [sheet] (la que se está viendo). Devuelve lo elegido, o null si se canceló.
Future<StyleChoice?> showStyleDialog(BuildContext context, NotebookDoc doc, {required int sheet}) async {
  final cur = doc.sheets[sheet.clamp(0, doc.sheetCount - 1)];
  var bg = cur.bg, paper = cur.paper, spacing = cur.spacing, all = true;
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
      final options = spacingsFor(bg);
      final controls = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Fondo', style: title),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (v, i, label) in backgrounds)
            ChoiceChip(
              avatar: Icon(i, size: 18, weight: 300),
              label: Text(label),
              selected: bg == v,
              onSelected: (_) => set(() {
                bg = v;
                spacing = validSpacing(v, spacing);
              }),
            ),
        ]),
        const SizedBox(height: 18),
        Text('Color del papel', style: title),
        const SizedBox(height: 8),
        Wrap(spacing: 10, children: [for (final (c, label) in papers) paperOpt(c, label)]),
        if (options.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(bg == 'lined' ? 'Interlineado' : 'Cuadrícula', style: title),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final o in options)
              ChoiceChip(
                key: Key('spacing-${fmtMm(o)}'),
                label: Text('${fmtMm(o)} mm'),
                selected: spacing == o,
                onSelected: (_) => set(() => spacing = o),
              ),
          ]),
        ],
        const SizedBox(height: 18),
        Text('Aplicar a', style: title),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          ChoiceChip(
              key: const Key('applySheet'),
              label: const Text('Esta hoja'),
              selected: !all,
              onSelected: (_) => set(() => all = false)),
          ChoiceChip(
              key: const Key('applyAll'),
              label: const Text('Todo el cuaderno'),
              selected: all,
              onSelected: (_) => set(() => all = true)),
        ]),
      ]);
      return AlertDialog(
        title: const Text('Estilo de hoja'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: controls),
              const SizedBox(width: 20),
              PaperPreview(bg: bg, paper: paper, spacing: spacing, width: 130),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(key: const Key('styleOk'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Aplicar')),
        ],
      );
    }),
  );
  return ok == true ? (bg: bg, paper: paper, spacing: spacing, all: all) : null;
}
