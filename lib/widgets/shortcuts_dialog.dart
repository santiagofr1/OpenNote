import 'package:flutter/material.dart';

const _typing = <(String, String)>[
  ('Negrita', 'Ctrl+B'),
  ('Cursiva', 'Ctrl+I'),
  ('Subrayado', 'Ctrl+U'),
  ('Tachado', 'Alt+Shift+5'),
  ('Resaltado (poner / sacar)', 'Ctrl+Shift+H'),
  ('Agrandar letra', 'Ctrl+]'),
  ('Achicar letra', 'Ctrl+['),
  ('Viñetas', 'Ctrl+Shift+8'),
  ('Lista numerada', 'Ctrl+Shift+7'),
  ('Lista de tareas', 'Ctrl+Shift+9'),
  ('Alinear a la izquierda', 'Ctrl+L'),
  ('Centrar', 'Ctrl+E'),
  ('Alinear a la derecha', 'Ctrl+R'),
  ('Justificar', 'Ctrl+J'),
  ('Más sangría', 'Tab'),
  ('Menos sangría', 'Shift+Tab'),
];

const _sheet = <(String, String)>[
  ('Deshacer', 'Ctrl+Z'),
  ('Rehacer', 'Ctrl+Y / Ctrl+Shift+Z'),
  ('Lápiz', 'P'),
  ('Resaltador', 'H'),
  ('Texto (abre un bloque)', 'T'),
  ('Seleccionar', 'S'),
  ('Ver estos atajos', 'Ctrl+/'),
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
          title: const Text('Atajos de teclado'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                title('Escribiendo'),
                for (final r in _typing) row(r),
                title('En la hoja'),
                for (final r in _sheet) row(r),
              ]),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
        );
      },
    );
