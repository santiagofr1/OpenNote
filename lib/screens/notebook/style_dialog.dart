import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/storage.dart';
import '../../data/templates.dart';
import '../../domain/domain.dart';
import '../../l10n/l10n.dart';
import '../../widgets/backgrounds.dart';
import '../../widgets/paper_preview.dart';

/// Colores de papel: valor guardado y nombre (el nombre lo usan los tests como tooltip).
final papers = <(String, String Function(L))>[
  ('#fffefb', (l) => l.paperColorIvory),
  ('#ffffff', (l) => l.paperColorWhite),
  ('#fbf3e0', (l) => l.paperColorCream),
  ('#f0efeb', (l) => l.paperColorGray),
  ('#eaf3fb', (l) => l.paperColorLightBlue),
  ('#eef6ec', (l) => l.paperColorGreen),
];

/// Lo elegido en el diálogo: [all] aplica a todas las hojas (y a las nuevas); si no, solo a la hoja visible.
typedef StyleChoice = ({String bg, String? image, String paper, String size, double spacing, bool all});

/// Estilo de hoja: fondo, color de papel y tamaño y espaciado (en mm reales del tamaño de la hoja), con vista previa.
/// Parte del estilo de la hoja [sheet] (la que se está viendo). Devuelve lo elegido, o null si se canceló.
/// [forNew]: el estilo es el de una hoja nueva (sin "Aplicar a"; el botón dice "Crear").
Future<StyleChoice?> showStyleDialog(BuildContext context, NotebookDoc doc,
    {required Storage store, required int sheet, bool forNew = false}) async {
  final cur = doc.sheets[sheet.clamp(0, doc.sheetCount - 1)];
  final mine = await readTemplates(store); // plantillas propias (se leen al abrir)
  if (!context.mounted) return null;
  String? image = cur.image;
  var bg = cur.bg, paper = cur.paper, size = cur.size, spacing = cur.spacing, all = true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
      final cs = Theme.of(ctx).colorScheme;
      Widget paperOpt(String c, String Function(L) label) => Tooltip(
            message: label(ctx.l10n),
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
      Widget bgChip(String v, IconData i, String Function(L) label) => ChoiceChip(
            key: Key('bg-$v'),
            avatar: Icon(i, size: 18, weight: 300),
            label: Text(label(ctx.l10n)),
            selected: bg == v,
            onSelected: (_) => set(() {
              bg = v;
              image = null;
              spacing = validSpacing(v, spacing);
            }),
          );
      Future<void> askDelete(SheetTemplate t) async {
        final del = await showDialog<bool>(
          context: ctx,
          builder: (c) => AlertDialog(
            title: Text(ctx.l10n.styleDeleteTemplate(t.name)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: Text(c.l10n.commonCancel)),
              FilledButton(key: const Key('tplDelete'), onPressed: () => Navigator.pop(c, true), child: Text(c.l10n.commonDelete)),
            ],
          ),
        );
        if (del != true) return;
        await deleteTemplate(store, t.id);
        set(() => mine.removeWhere((x) => x.id == t.id));
      }
      Widget tplTile(SheetTemplate t) {
        final sel = bg == 'image' && image == t.file;
        return Tooltip(
          message: t.name,
          child: InkWell(
            key: Key('tpl-${t.id}'),
            borderRadius: BorderRadius.circular(6),
            onTap: () => set(() {
              bg = 'image';
              image = t.file;
            }),
            onLongPress: () => askDelete(t),
            onSecondaryTap: () => askDelete(t),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: sel ? cs.primary : cs.outlineVariant, width: sel ? 2.5 : 1),
              ),
              child: PaperPreview(bg: 'image', image: store.media(t.file), paper: paper, spacing: spacing, size: size, width: 56),
            ),
          ),
        );
      }
      final title = TextStyle(fontWeight: FontWeight.w500, color: cs.onSurface);
      final options = spacingsFor(bg);
      final mq = MediaQuery.sizeOf(ctx);
      // tablet en horizontal: tres columnas (tamaño y fondos, plantillas, resto) y la vista previa abajo de la tercera, para que entre sin scroll
      final wide = !doc.nb.canvas && mq.width >= 1000 && mq.width > mq.height;
      final colA = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ctx.l10n.styleSize, style: title),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final (v, label) in kPaperSizes)
            ChoiceChip(key: Key('size-$v'), label: Text(label), selected: size == v, onSelected: (_) => set(() => size = v)),
        ]),
        const SizedBox(height: 18),
        Text(ctx.l10n.styleBackground, style: title),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final (v, i, label) in backgrounds) bgChip(v, i, label)]),
      ]);
      final colTpl = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ctx.l10n.styleTemplates, style: title),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final (v, i, label) in templates) bgChip(v, i, label)]),
        const SizedBox(height: 18),
        Text(ctx.l10n.styleMyTemplates, style: title),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final t in mine) tplTile(t),
          OutlinedButton.icon(
            key: const Key('tplFromImage'),
            icon: const Icon(Symbols.image, size: 18, weight: 300),
            label: Text(ctx.l10n.styleFromImage),
            onPressed: () async {
              final t = await templateFromImage(store);
              if (t == null) return;
              set(() {
                mine.add(t);
                bg = 'image';
                image = t.file;
              });
            },
          ),
        ]),
      ]);
      final colB = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(ctx.l10n.menuMorePaperColor, style: title),
        const SizedBox(height: 8),
        Wrap(spacing: 10, children: [for (final (c, label) in papers) paperOpt(c, label)]),
        if (options.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(bg == 'lined' ? ctx.l10n.styleSpacingLined : ctx.l10n.styleSpacingGrid, style: title),
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
        if (!forNew) ...[
          const SizedBox(height: 18),
          Text(ctx.l10n.styleApplyTo, style: title),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            ChoiceChip(
                key: const Key('applySheet'),
                label: Text(ctx.l10n.styleThisSheet),
                selected: !all,
                onSelected: (_) => set(() => all = false)),
            ChoiceChip(
                key: const Key('applyAll'),
                label: Text(ctx.l10n.styleWholeNotebook),
                selected: all,
                onSelected: (_) => set(() => all = true)),
          ]),
        ],
      ]);
      final sheetControls = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        colA,
        const SizedBox(height: 18),
        colTpl,
        const SizedBox(height: 18),
        colB,
      ]);
      // lienzo infinito: solo el color del papel, que vale para todo
      final controls = !doc.nb.canvas
          ? sheetControls
          : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ctx.l10n.menuMorePaperColor, style: title),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 10, children: [for (final (c, label) in papers) paperOpt(c, label)]),
            ]);
      final preview = PaperPreview(
          bg: bg,
          paper: paper,
          spacing: spacing,
          size: size,
          width: 130,
          image: bg == 'image' && image != null ? store.media(image!) : null);
      return AlertDialog(
        insetPadding: wide
            ? const EdgeInsets.symmetric(horizontal: 32, vertical: 16)
            : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        title: Text(doc.nb.canvas ? ctx.l10n.menuMorePaperColor : (forNew ? ctx.l10n.styleTitleNew : ctx.l10n.styleTitle)),
        content: wide
            ? SizedBox(
                width: min(mq.width - 96, 1100),
                child: SingleChildScrollView(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: colA),
                    const SizedBox(width: 24),
                    Expanded(child: colTpl),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        colB,
                        const SizedBox(height: 18),
                        preview,
                      ]),
                    ),
                  ]),
                ),
              )
            : SizedBox(
                width: 560,
                child: SingleChildScrollView(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: controls),
                    const SizedBox(width: 20),
                    preview,
                  ]),
                ),
              ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.l10n.commonCancel)),
          FilledButton(
              key: const Key('styleOk'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(forNew ? ctx.l10n.commonCreate : ctx.l10n.styleApply)),
        ],
      );
    }),
  );
  return ok == true ? (bg: bg, image: bg == 'image' ? image : null, paper: paper, size: size, spacing: spacing, all: all) : null;
}
