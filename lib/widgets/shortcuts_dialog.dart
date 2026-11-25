import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

List<(String, String)> _typing(L l) => [
  (l.shortcutBold, 'Ctrl+B'),
  (l.shortcutItalic, 'Ctrl+I'),
  (l.shortcutUnderline, 'Ctrl+U'),
  (l.shortcutStrike, 'Alt+Shift+5'),
  (l.shortcutHighlight, 'Ctrl+Shift+H'),
  (l.shortcutFontUp, 'Ctrl+]'),
  (l.shortcutFontDown, 'Ctrl+['),
  (l.shortcutBullets, 'Ctrl+Shift+8'),
  (l.shortcutNumbered, 'Ctrl+Shift+7'),
  (l.shortcutTodo, 'Ctrl+Shift+9'),
  (l.shortcutAlignLeft, 'Ctrl+L'),
  (l.shortcutCenter, 'Ctrl+E'),
  (l.shortcutAlignRight, 'Ctrl+R'),
  (l.shortcutJustify, 'Ctrl+J'),
  (l.shortcutIndent, 'Tab'),
  (l.shortcutOutdent, 'Shift+Tab'),
];

List<(String, String)> _sheet(L l) => [
  (l.shortcutUndo, 'Ctrl+Z'),
  (l.shortcutRedo, 'Ctrl+Y / Ctrl+Shift+Z'),
  (l.shortcutPencil, 'P'),
  (l.shortcutHighlighter, 'H'),
  (l.shortcutText, 'T'),
  (l.shortcutSelect, 'S'),
  (l.shortcutZoom, l.shortcutZoomKeys),
  (l.shortcutHelp, 'Ctrl+/'),
];

/// Lista de atajos de teclado: los que valen escribiendo en un texto y los que valen sobre la hoja.
Future<void> showShortcutsDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        Widget row((String, String) r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(child: Text(r.$1)),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Text(r.$2, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                ),
              ]),
            );
        Widget title(String t) => Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Text(t, style: Theme.of(ctx).textTheme.titleSmall?.copyWith(color: cs.primary)),
            );
        return AlertDialog(
          key: const Key('shortcutsDialog'),
          title: Text(ctx.l10n.shortcutsTitle),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                title(ctx.l10n.shortcutsTyping),
                for (final r in _typing(ctx.l10n)) row(r),
                title(ctx.l10n.shortcutsSheet),
                for (final r in _sheet(ctx.l10n)) row(r),
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.l10n.commonClose))],
        );
      },
    );
