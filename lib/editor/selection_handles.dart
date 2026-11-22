import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'selection.dart';

/// Manijas sobre el recuadro de la selección: una en cada esquina para escalar y, si hay trazos, una arriba del centro
/// del borde de arriba (unida con una rayita) para rotar. Todo en pantalla, del mismo tamaño con cualquier zoom.
/// Las posiciones ([corners]: arriba-izquierda, arriba-derecha, abajo-derecha, abajo-izquierda; [rotateAt]) vienen en
/// coordenadas del widget y siguen a la transformación en curso. El arrastre avisa con la posición GLOBAL del dedo o el
/// lápiz, así no depende de dónde esté dibujada la manija en cada cuadro.
class SelectionHandles extends StatelessWidget {
  /// Zona de toque (cómoda para lápiz y dedo) y círculo que se dibuja adentro.
  static const double hit = 28, dot = 16;
  final List<Offset> corners;
  final Offset? rotateAt, topMid;
  final void Function(Handle h, Offset global) onStart, onUpdate;
  final VoidCallback onEnd;
  const SelectionHandles({
    super.key,
    required this.corners,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    this.rotateAt,
    this.topMid,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget handle(Handle h, Offset at, {IconData? icon}) => Positioned(
          key: ValueKey('selHandle-${h.name}'),
          left: at.dx - hit / 2,
          top: at.dy - hit / 2,
          width: hit,
          height: hit,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onPanStart: (d) => onStart(h, d.globalPosition),
            onPanUpdate: (d) => onUpdate(h, d.globalPosition),
            onPanEnd: (_) => onEnd(),
            onPanCancel: onEnd,
            child: Center(
              child: Container(
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  color: cs.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.primary, width: 2),
                  boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3)],
                ),
                child: icon == null ? null : Icon(icon, size: 10, color: cs.primary),
              ),
            ),
          ),
        );
    return Positioned.fill(
      child: Stack(clipBehavior: Clip.none, children: [
        if (rotateAt != null && topMid != null)
          Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _RodPainter(topMid!, rotateAt!, cs.primary))),
          ),
        for (final (i, h) in const [Handle.tl, Handle.tr, Handle.br, Handle.bl].indexed) handle(h, corners[i]),
        if (rotateAt != null) handle(Handle.rotate, rotateAt!, icon: Symbols.rotate_right),
      ]),
    );
  }
}

class _RodPainter extends CustomPainter {
  final Offset a, b;
  final Color color;
  _RodPainter(this.a, this.b, this.color);

  @override
  void paint(Canvas c, Size size) => c.drawLine(a, b, Paint()..color = color..strokeWidth = 1.5);

  @override
  bool shouldRepaint(_RodPainter o) => o.a != a || o.b != b || o.color != color;
}
