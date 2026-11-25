import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../domain/domain.dart';
import '../l10n/l10n.dart';
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
  String? _open; // 'color' | 'hl' | 'size': paleta o lista desplegada

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
              if (_open == 'size')
                _sizeList(ed, cs)
              else if (_open != null)
                _palette(ed, cs),
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
      fmt('fmt-bold', Symbols.format_bold, context.l10n.formatBold, Fmt.bold),
      fmt('fmt-italic', Symbols.format_italic, context.l10n.formatItalic, Fmt.italic),
      fmt('fmt-underline', Symbols.format_underlined, context.l10n.formatUnderline, Fmt.underline),
      fmt('fmt-strike', Symbols.format_strikethrough, context.l10n.formatStrike, Fmt.strike),
      _btn(cs, 'fmt-color', Symbols.format_color_text, context.l10n.formatColor, _open == 'color', () => _toggle('color'),
          dot: c == null ? null : Color(c)),
      _btn(cs, 'fmt-hl', Symbols.format_ink_highlighter, context.l10n.formatHighlight, _open == 'hl', () => _toggle('hl'),
          dot: h == null ? null : Color(h)),
      _sizeControl(ed, cs),
      _sep(cs),
      st('fmt-normal', context.l10n.formatNormal, ParaStyle.normal),
      st('fmt-title', context.l10n.formatTitle, ParaStyle.title),
      st('fmt-subtitle', context.l10n.formatSubtitle, ParaStyle.subtitle),
      _sep(cs),
      list('fmt-bullet', Symbols.format_list_bulleted, context.l10n.formatBullets, ListKind.bullet),
      list('fmt-numbered', Symbols.format_list_numbered, context.l10n.formatNumbered, ListKind.numbered),
      list('fmt-check', Symbols.checklist, context.l10n.formatTodo, ListKind.checklist),
      _btn(cs, 'fmt-outdent', Symbols.format_indent_decrease, context.l10n.formatOutdent, false, () => ed.indentBy(-1)),
      _btn(cs, 'fmt-indent', Symbols.format_indent_increase, context.l10n.formatIndent, false, () => ed.indentBy(1)),
      _sep(cs),
      al('fmt-left', Symbols.format_align_left, context.l10n.formatAlignLeft, ParaAlign.left),
      al('fmt-center', Symbols.format_align_center, context.l10n.formatCenter, ParaAlign.center),
      al('fmt-right', Symbols.format_align_right, context.l10n.formatAlignRight, ParaAlign.right),
      al('fmt-justify', Symbols.format_align_justify, context.l10n.formatJustify, ParaAlign.justify),
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
              label: Text(context.l10n.commonCopy)),
          TextButton.icon(
              key: const Key('across-cut'),
              onPressed: ed.cutAcross,
              icon: const Icon(Symbols.content_cut, size: 18),
              label: Text(context.l10n.formatCut)),
          TextButton.icon(
              key: const Key('across-delete'),
              onPressed: ed.deleteAcross,
              icon: const Icon(Symbols.delete, size: 18),
              label: Text(context.l10n.commonDelete)),
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

  /// A− / tamaño actual / A+. Sin tamaño propio muestra el que da la hoja; vacío si la selección mezcla.
  Widget _sizeControl(BlockEditor ed, ColorScheme cs) {
    final auto = autoPt(ed.line), cur = ed.currentSize;
    final label = cur != null ? _ptText(cur) : (ed.mixedSize ? '' : _ptText(auto));
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _btn(cs, 'fmt-size-down', Symbols.text_decrease, context.l10n.formatSizeDown, false, () => ed.stepSize(-1, auto)),
      InkWell(
        key: const Key('fmt-size'),
        canRequestFocus: false,
        borderRadius: BorderRadius.circular(10),
        onTap: () => _toggle('size'),
        child: Container(
          width: 46,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: _open == 'size' ? cs.secondaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.outlineVariant)),
          child: Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontStyle: cur == null ? FontStyle.italic : null,
                  color: _open == 'size' ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
        ),
      ),
      _btn(cs, 'fmt-size-up', Symbols.text_increase, context.l10n.formatSizeUp, false, () => ed.stepSize(1, auto)),
    ]);
  }

  String _ptText(double pt) => pt == pt.roundToDouble() ? '${pt.round()}' : pt.toStringAsFixed(1);

  Widget _sizeList(BlockEditor ed, ColorScheme cs) {
    final cur = ed.currentSize;
    Widget item(Key k, String label, bool on, double? pt) => InkWell(
          key: k,
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            ed.setSize(pt);
            setState(() => _open = null);
          },
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: on ? cs.secondaryContainer : Colors.transparent, borderRadius: BorderRadius.circular(10)),
            child: Text(label, style: TextStyle(fontSize: 14, color: on ? cs.onSecondaryContainer : cs.onSurfaceVariant)),
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        item(const Key('fmt-size-auto'), context.l10n.formatSizeAuto, cur == null, null),
        for (final n in kSizes) item(Key('fmt-size-${_ptText(n)}'), _ptText(n), cur == n, n),
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
