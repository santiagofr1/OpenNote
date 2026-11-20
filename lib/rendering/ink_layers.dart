import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../domain/domain.dart';
import 'stroke_painter.dart';

/// Todos los trazos guardados. Se repinta solo cuando cambia [version].
/// [hidden]: trazos que no se dibujan acá (los que se están moviendo).
class InkPainter extends CustomPainter {
  final NotebookDoc doc;
  final double scale;
  final ValueNotifier<int> version;
  final Set<String> Function() hidden;
  InkPainter(this.doc, this.scale, this.version, this.hidden) : super(repaint: version);

  @override
  void paint(Canvas c, Size size) {
    c.scale(scale);
    // la tinta solo se ve sobre las hojas, no en el espacio entre ellas
    final clip = Path();
    for (final r in sheetRects(doc.h)) {
      clip.addRect(r);
    }
    c.clipPath(clip);
    final skip = hidden();
    paintStrokes(c, doc.strokes.values.where((s) => !skip.contains(s.id)));
  }

  @override
  bool shouldRepaint(InkPainter o) => o.doc != doc || o.scale != scale;
}

/// Capa de lo que pasa "ahora": trazo en curso, goma, selección.
class LivePainter extends CustomPainter {
  final void Function(Canvas) draw;
  final double scale;
  LivePainter(this.draw, this.scale, Listenable tick) : super(repaint: tick);

  @override
  void paint(Canvas c, Size size) {
    c.scale(scale);
    draw(c);
  }

  @override
  bool shouldRepaint(LivePainter o) => o.scale != scale;
}

/// Rectángulo punteado
void dashedRect(Canvas c, Rect r, Paint p, double dash) {
  void line(Offset a, Offset b) {
    final len = (b - a).distance, dir = (b - a) / len;
    for (double d = 0; d < len; d += dash * 2) {
      c.drawLine(a + dir * d, a + dir * min(d + dash, len), p);
    }
  }

  line(r.topLeft, r.topRight);
  line(r.topRight, r.bottomRight);
  line(r.bottomRight, r.bottomLeft);
  line(r.bottomLeft, r.topLeft);
}
