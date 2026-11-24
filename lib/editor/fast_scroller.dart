import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

/// Ancho tocable del pulgar del scroll rápido (el dibujo es más finito).
const kFastThumbW = 40.0;

/// Alto tocable del pulgar del scroll rápido.
const kFastThumbH = 72.0;

/// Margen arriba y abajo del recorrido del pulgar.
const kFastTrackPad = 8.0;

/// Cuánto espera el pulgar para esconderse solo después del último scroll.
const kFastHideAfter = Duration(milliseconds: 1500);

/// Barra de scroll rápido al costado derecho: aparece al scrollear, se agarra y se arrastra para recorrer todo el
/// cuaderno, y se esconde sola. Solo el pulgar recibe toques: el resto del borde queda libre para el lápiz.
class FastScroller extends StatefulWidget {
  final ScrollController controller;

  /// Texto de la burbuja mientras se arrastra (null, o que devuelva null: sin burbuja).
  final String? Function()? label;

  const FastScroller({super.key, required this.controller, this.label});

  @override
  State<FastScroller> createState() => _FastScrollerState();
}

class _FastScrollerState extends State<FastScroller> {
  bool _visible = false;
  bool _dragging = false;
  Timer? _hide;
  double _frac = 0;
  double _travel = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(FastScroller old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    _hide?.cancel();
    super.dispose();
  }

  /// Solo vale la pena con un cuaderno largo (más de una vez y media la pantalla).
  bool get _worth {
    final c = widget.controller;
    return c.hasClients &&
        c.position.hasContentDimensions &&
        c.position.maxScrollExtent > 1.5 * c.position.viewportDimension;
  }

  void _onScroll() {
    if (!mounted) return;
    if (_worth) _show();
    // reubica el pulgar (y la burbuja) con el scroll
    if (_visible) setState(() {});
  }

  void _show() {
    _visible = true;
    _hide?.cancel();
    if (!_dragging) {
      _hide = Timer(kFastHideAfter, () {
        if (mounted && !_dragging) setState(() => _visible = false);
      });
    }
  }

  void _dragStart(DragStartDetails d) {
    final pos = widget.controller.position;
    setState(() {
      _dragging = true;
      _frac = pos.maxScrollExtent > 0 ? (pos.pixels / pos.maxScrollExtent).clamp(0.0, 1.0) : 0;
      _hide?.cancel();
    });
  }

  void _dragUpdate(DragUpdateDetails d) {
    if (!widget.controller.hasClients) return;
    final pos = widget.controller.position;
    if (_travel > 0) _frac = (_frac + d.delta.dy / _travel).clamp(0.0, 1.0);
    widget.controller.jumpTo(_frac * pos.maxScrollExtent);
    setState(() {});
  }

  void _dragEnd() {
    setState(() {
      _dragging = false;
      _show();
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      if (!_worth) return const SizedBox.shrink();
      final cs = Theme.of(context).colorScheme;
      final pos = widget.controller.position;
      _travel = max(0.0, box.maxHeight - 2 * kFastTrackPad - kFastThumbH);
      final frac = _dragging ? _frac : (pos.pixels / pos.maxScrollExtent).clamp(0.0, 1.0);
      final top = kFastTrackPad + frac * _travel;
      final text = _dragging ? widget.label?.call() : null;
      return IgnorePointer(
        ignoring: !_visible,
        child: AnimatedOpacity(
          opacity: _visible ? 1 : 0,
          duration: Duration(milliseconds: _visible ? 180 : 300),
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(
              key: const Key('fastScrollThumb'),
              right: 0,
              top: top,
              width: kFastThumbW,
              height: kFastThumbH,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: _dragStart,
                onVerticalDragUpdate: _dragUpdate,
                onVerticalDragEnd: (_) => _dragEnd(),
                onVerticalDragCancel: _dragEnd,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: _dragging ? 12 : 8,
                      height: 56,
                      decoration: BoxDecoration(
                        color: _dragging ? cs.primary : cs.onSurfaceVariant.withValues(alpha: .45),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (text != null)
              Positioned(
                key: const Key('fastScrollLabel'),
                right: kFastThumbW + 4,
                top: top + kFastThumbH / 2 - 18,
                child: IgnorePointer(
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2))],
                    ),
                    child: Text(text,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: cs.onSurface)),
                  ),
                ),
              ),
          ]),
        ),
      );
    });
  }
}
