import 'dart:math';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../domain/domain.dart';

/// Barra de herramientas del editor. Zonas de tamaño fijo para que nada salte al cambiar de herramienta.
/// Arriba:   [mover][herramientas] | [colores][más colores][grosor] | [deshacer][rehacer][candado]
/// Costado:  lo mismo, en columna.
class EditorToolbar extends StatelessWidget {
  final ToolState ts;
  final bool vertical;
  final Widget grip; // agarradera para mover la barra (la pone DockLayout)
  final bool canUndo, canRedo;
  final ValueChanged<Tool> onToolTap, onToolLongPress;
  final ValueChanged<String> onPickColor;
  final ValueChanged<int> onEditFavorite;
  final VoidCallback onOpenPanel, onUndo, onRedo, onToggleZoomLock;

  const EditorToolbar({
    super.key,
    required this.ts,
    required this.vertical,
    required this.grip,
    required this.canUndo,
    required this.canRedo,
    required this.onToolTap,
    required this.onToolLongPress,
    required this.onPickColor,
    required this.onEditFavorite,
    required this.onOpenPanel,
    required this.onUndo,
    required this.onRedo,
    required this.onToggleZoomLock,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final drawing = ts.drawing;
    final cur = ts.current;
    final axis = vertical ? Axis.vertical : Axis.horizontal;
    return LayoutBuilder(builder: (context, box) {
      final room = vertical ? box.maxHeight : box.maxWidth;
      // Los 4 favoritos fijos: arriba se muestran tantos como entren; al costado, siempre los 4.
      final nColors = vertical ? 4 : ((room - _fixedWidth) / _slot.width).floor().clamp(0, 4);
      final side = BorderSide(color: cs.outlineVariant.withValues(alpha: .6));
      final children = <Widget>[
        grip,
        if (vertical) const SizedBox(height: 4),
        _toolBtn(cs, Tool.pen, Symbols.stylus, 'Lápiz · tocá de nuevo para opciones', ts.pen),
        _toolBtn(cs, Tool.hl, Symbols.ink_highlighter, 'Resaltador · tocá de nuevo para opciones', ts.hl),
        _toolBtn(cs, Tool.paint, Symbols.brush, 'Decorador · tocá de nuevo para opciones', ts.paint),
        _toolBtn(cs, Tool.shape, Symbols.shapes, 'Formas · tocá de nuevo para opciones', ts.pen),
        _toolBtn(cs, Tool.text, Symbols.keyboard, 'Texto con teclado', null),
        _toolBtn(cs, Tool.select, Symbols.highlight_alt, 'Seleccionar', null),
        _toolBtn(cs, Tool.title, Symbols.format_list_numbered, 'Título para el índice', null),
        _divider(cs),
        AnimatedOpacity(
          opacity: drawing ? 1 : .38,
          duration: const Duration(milliseconds: 160),
          child: Flex(direction: axis, mainAxisSize: MainAxisSize.min, children: [
            for (final (i, c) in ts.favorites.take(nColors).indexed) _swatch(cs, c, drawing && cur.color == c, slot: i),
            _moreColors(cs, drawing && !ts.favorites.contains(cur.color), cur.color),
            _widthBtn(cs, cur),
          ]),
        ),
        _divider(cs),
        _icon(cs, Symbols.undo, 'Deshacer', canUndo ? onUndo : null),
        _icon(cs, Symbols.redo, 'Rehacer', canRedo ? onRedo : null),
        _lockBtn(cs),
      ];
      return Container(
        width: vertical ? 60 : null,
        height: vertical ? null : 56,
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          border: Border(
            bottom: ts.dock == 'top' ? side : BorderSide.none,
            right: ts.dock == 'left' ? side : BorderSide.none,
            left: ts.dock == 'right' ? side : BorderSide.none,
          ),
        ),
        padding: vertical ? const EdgeInsets.symmetric(vertical: 6) : const EdgeInsets.symmetric(horizontal: 6),
        child: vertical
            ? SingleChildScrollView(child: Column(children: children))
            // Centrada si sobra lugar; si no entra (pantalla muy angosta) se desplaza en vez de desbordar.
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Container(
                  constraints: BoxConstraints(minWidth: max(0, box.maxWidth - 12)),
                  alignment: Alignment.center,
                  child: Row(mainAxisSize: MainAxisSize.min, children: children),
                ),
              ),
      );
    });
  }

  /// Ancho (dp) de la barra horizontal sin los colores favoritos. Medido: 676 con fondo y pegar, menos 44 de Pegar y 48 del fondo, más 46 de Formas.
  static const _fixedWidth = 632.0;

  Widget _lockBtn(ColorScheme cs) {
    final on = ts.zoomLocked;
    return Tooltip(
      message: on ? 'Zoom fijo (${(ts.zoom * 100).round()}%) · tocá para soltarlo' : 'Fijar el zoom',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onToggleZoomLock,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
              color: on ? cs.secondaryContainer : Colors.transparent, borderRadius: BorderRadius.circular(12)),
          child: Icon(on ? Symbols.lock : Symbols.lock_open,
              size: 21, weight: on ? 400 : 300, color: on ? cs.onSecondaryContainer : cs.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _divider(ColorScheme cs) => Container(
        width: vertical ? 22 : 1,
        height: vertical ? 1 : 22,
        margin: vertical ? const EdgeInsets.symmetric(vertical: 8) : const EdgeInsets.symmetric(horizontal: 8),
        color: cs.outlineVariant,
      );

  Widget _icon(ColorScheme cs, IconData icon, String tip, VoidCallback? onTap) => IconButton(
        onPressed: onTap,
        tooltip: tip,
        icon: Icon(icon, size: 22, weight: 300, opticalSize: 24),
        color: cs.onSurfaceVariant,
        disabledColor: cs.onSurface.withValues(alpha: .28),
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );

  /// [preset]: lápiz o resaltador (muestra su color con un puntito y abre opciones al mantener).
  Widget _toolBtn(ColorScheme cs, Tool t, IconData icon, String tip, PenPreset? preset) {
    final on = ts.tool == t;
    return Tooltip(
      key: ValueKey('tool-${t.name}'),
      message: tip,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onToolTap(t),
        onLongPress: preset == null ? null : () => onToolLongPress(t),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutQuart,
          width: 46,
          height: 44,
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: on ? cs.secondaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(alignment: Alignment.center, children: [
            Icon(icon,
                size: 22, weight: on ? 400 : 300, opticalSize: 24, color: on ? cs.onSecondaryContainer : cs.onSurfaceVariant),
            if (preset != null)
              Positioned(
                bottom: 5,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: parseColor(preset.color).withValues(alpha: max(preset.opacity, .45)),
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.outlineVariant.withValues(alpha: .6), width: .5),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Size get _slot => vertical ? const Size(48, 34) : const Size(32, 44);

  Widget _swatch(ColorScheme cs, String c, bool on, {int? slot}) => InkWell(
        key: slot == null ? null : ValueKey('fav-$slot'),
        customBorder: const CircleBorder(),
        onTap: () => onPickColor(c),
        onLongPress: slot == null ? null : () => onEditFavorite(slot),
        child: SizedBox.fromSize(
          size: _slot,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              width: on ? 21 : 16,
              height: on ? 21 : 16,
              padding: EdgeInsets.all(on ? 2.5 : 0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: on ? Border.all(color: cs.primary, width: 1.5) : null,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: parseColor(c),
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.outline.withValues(alpha: .6), width: .8),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _moreColors(ColorScheme cs, bool on, String color) => Tooltip(
        message: 'Más colores',
        child: InkWell(
          key: const ValueKey('moreColors'),
          customBorder: const CircleBorder(),
          onTap: onOpenPanel,
          child: SizedBox.fromSize(
            size: _slot,
            child: Center(
              // Con un color que no es favorito: anillo de selección y el color actual adentro, rodeado por la ruleta.
              child: on
                  ? Container(
                      width: 21,
                      height: 21,
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: cs.primary, width: 1.5)),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: _wheel),
                        child: DecoratedBox(decoration: BoxDecoration(color: parseColor(color), shape: BoxShape.circle)),
                      ),
                    )
                  : Container(width: 16, height: 16, decoration: const BoxDecoration(shape: BoxShape.circle, gradient: _wheel)),
            ),
          ),
        ),
      );

  static const _wheel = SweepGradient(colors: [
    Color(0xFFD9625B), Color(0xFFDDB24A), Color(0xFF5FAE78), Color(0xFF5B8FD9), Color(0xFF9B78D0), Color(0xFFD9625B),
  ]);

  /// Muestra el grosor actual: punto para el lápiz, barrita para el resaltador.
  Widget _widthBtn(ColorScheme cs, PenPreset p) {
    final hl = ts.tool == Tool.hl || ts.tool == Tool.paint;
    final d = hl ? (p.width / 60 * 18).clamp(5.0, 18.0) : p.width.clamp(2.5, 16.0);
    return Tooltip(
      message: 'Punta, grosor y opacidad',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onOpenPanel,
        child: SizedBox(
          width: vertical ? 48 : 40,
          height: vertical ? 40 : 44,
          child: Center(
            child: Container(
              width: d,
              height: hl ? d * .6 : d,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant,
                shape: hl ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: hl ? BorderRadius.circular(1.5) : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
