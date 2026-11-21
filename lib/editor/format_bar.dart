import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../domain/domain.dart';
import 'rich_editing.dart';
import 'text_blocks.dart';

/// Colores de letra de la barra de formato (ARGB). El primero, "automático" (la tinta).
const _textColors = [
  0xFFB91C1C, 0xFFC2410C, 0xFFCA8A04, 0xFF15803D, 0xFF0F766E, 0xFF1D4ED8, 0xFF7E22CE, 0xFFBE185D, 0xFF7A776E,
];
const _hlColors = [0xFFF7D22C, 0xFFFFB347, 0xFF5EE08A, 0xFF5BC8FF, 0xFFFF86C8, 0xFFC79bFF, 0xFFB8F35D];

/// Barra de formato tipo Word sobre el teclado mientras hay un bloque de texto con foco.
/// Los botones no toman el foco (el campo sigue escribiendo y el teclado no se cierra).
class FormatBar extends StatefulWidget {
  final TextFields fields;
  const FormatBar({super.key, required this.fields});

  @override
  State<FormatBar> createState() => _FormatBarState();
}

class _FormatBarState extends State<FormatBar> {
  String? _open; // 'color' | 'hl': paleta desplegada

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextFieldTapRegion(
      child: Material(
        color: cs.surfaceContainerHigh,
        elevation: 6,
        child: ValueListenableBuilder<int>(
          valueListenable: widget.fields.tick,
          builder: (context, _, _) {
            final ed = widget.fields.focused;
            if (ed == null) return const SizedBox(height: 0);
            return Column(mainAxisSize: MainAxisSize.min, children: [
              if (ed.across != null) _acrossBar(ed),
              if (_open != null) _palette(ed, cs),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Row(children: _buttons(ed, cs)),
              ),
            ]);
          },
        ),
      ),
    );
  }

  List<Widget> _buttons(BlockEditor ed, ColorScheme cs) {
    final p = ed.activePara;
    Widget fmt(String k, IconData i, String tip, Fmt f) => _btn(cs, k, i, tip, ed.fmtActive(f), () => ed.toggleFmt(f));
    Widget list(String k, IconData i, String tip, ListKind l) => _btn(cs, k, i, tip, p.list == l, () => ed.setList(l));
    Widget al(String k, IconData i, String tip, ParaAlign a) => _btn(cs, k, i, tip, p.align == a, () => ed.setAlign(a));
    Widget st(String k, String label, ParaStyle s) => _chip(cs, k, label, p.style == s, () => ed.setParaStyle(s));
    final c = ed.currentColor, h = ed.currentHighlight;
    return [
      fmt('fmt-bold', Symbols.format_bold, 'Negrita (Ctrl+B)', Fmt.bold),
      fmt('fmt-italic', Symbols.format_italic, 'Cursiva (Ctrl+I)', Fmt.italic),
      fmt('fmt-underline', Symbols.format_underlined, 'Subrayado (Ctrl+U)', Fmt.underline),
      fmt('fmt-strike', Symbols.format_strikethrough, 'Tachado', Fmt.strike),
      _btn(cs, 'fmt-color', Symbols.format_color_text, 'Color del texto', _open == 'color', () => _toggle('color'),
          dot: c == null ? null : Color(c)),
      _btn(cs, 'fmt-hl', Symbols.format_ink_highlighter, 'Resaltado', _open == 'hl', () => _toggle('hl'),
          dot: h == null ? null : Color(h)),
      _sep(cs),
      st('fmt-normal', 'Normal', ParaStyle.normal),
      st('fmt-title', 'Título', ParaStyle.title),
      st('fmt-subtitle', 'Subtítulo', ParaStyle.subtitle),
      _sep(cs),
      list('fmt-bullet', Symbols.format_list_bulleted, 'Viñetas', ListKind.bullet),
      list('fmt-numbered', Symbols.format_list_numbered, 'Numerada', ListKind.numbered),
      list('fmt-check', Symbols.checklist, 'Lista de tareas', ListKind.checklist),
      _btn(cs, 'fmt-outdent', Symbols.format_indent_decrease, 'Menos sangría (Shift+Tab)', false, () => ed.indentBy(-1)),
      _btn(cs, 'fmt-indent', Symbols.format_indent_increase, 'Más sangría (Tab)', false, () => ed.indentBy(1)),
      _sep(cs),
      al('fmt-left', Symbols.format_align_left, 'Alinear a la izquierda', ParaAlign.left),
      al('fmt-center', Symbols.format_align_center, 'Centrar', ParaAlign.center),
      al('fmt-right', Symbols.format_align_right, 'Alinear a la derecha', ParaAlign.right),
      al('fmt-justify', Symbols.format_align_justify, 'Justificar', ParaAlign.justify),
    ];
  }

  /// Acciones sobre la selección que cruza párrafos (el menú nativo del campo solo ve su párrafo).
  Widget _acrossBar(BlockEditor ed) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          TextButton.icon(
              key: const Key('across-copy'),
              onPressed: ed.copyAcross,
              icon: const Icon(Symbols.content_copy, size: 18),
              label: const Text('Copiar')),
          TextButton.icon(
              key: const Key('across-cut'),
              onPressed: ed.cutAcross,
              icon: const Icon(Symbols.content_cut, size: 18),
              label: const Text('Cortar')),
          TextButton.icon(
              key: const Key('across-delete'),
              onPressed: ed.deleteAcross,
              icon: const Icon(Symbols.delete, size: 18),
              label: const Text('Borrar')),
        ]),
      );

  void _toggle(String k) => setState(() => _open = _open == k ? null : k);

  Widget _palette(BlockEditor ed, ColorScheme cs) {
    final isText = _open == 'color';
    final colors = isText ? _textColors : _hlColors;
    Widget swatch(Key k, Color? c, VoidCallback onTap) => InkWell(
          key: k,
          canRequestFocus: false,
          onTap: () {
            onTap();
            setState(() => _open = null);
          },
          customBorder: const CircleBorder(),
          child: Container(
            width: 30,
            height: 30,
            margin: const EdgeInsets.all(5),
            decoration: BoxDecoration(
                color: c, shape: BoxShape.circle, border: Border.all(color: cs.outline.withValues(alpha: .6))),
            child: c == null ? Icon(Symbols.format_color_reset, size: 18, color: cs.onSurfaceVariant) : null,
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        swatch(Key(isText ? 'color-auto' : 'hl-none'), null, () => isText ? ed.setColor(null) : ed.setHighlight(null)),
        for (final c in colors)
          swatch(Key('${isText ? 'color' : 'hl'}-${c.toRadixString(16)}'), Color(c),
              () => isText ? ed.setColor(c) : ed.setHighlight(c)),
      ]),
    );
  }

  Widget _sep(ColorScheme cs) =>
      Container(width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 6), color: cs.outlineVariant);

  Widget _btn(ColorScheme cs, String key, IconData icon, String tip, bool on, VoidCallback onTap, {Color? dot}) =>
      Tooltip(
        message: tip,
        child: InkWell(
          key: Key(key),
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: on ? cs.secondaryContainer : Colors.transparent, borderRadius: BorderRadius.circular(10)),
            child: Stack(alignment: Alignment.center, children: [
              Icon(icon, size: 22, color: on ? cs.onSecondaryContainer : cs.onSurfaceVariant),
              if (dot != null)
                Positioned(
                    bottom: 5,
                    child: Container(width: 14, height: 3, decoration: BoxDecoration(color: dot, borderRadius: BorderRadius.circular(2)))),
            ]),
          ),
        ),
      );

  Widget _chip(ColorScheme cs, String key, String label, bool on, VoidCallback onTap) => InkWell(
        key: Key(key),
        canRequestFocus: false,
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: on ? cs.secondaryContainer : Colors.transparent, borderRadius: BorderRadius.circular(10)),
          child: Text(label,
              style: TextStyle(fontSize: 14, color: on ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
        ),
      );
}
