import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../domain/domain.dart';
import 'stroke_painter.dart';

/// Una tanda de trazos seguidos en el orden de dibujo (ver [ZRun]) DE UNA HOJA. Se repinta solo cuando cambia
/// [version] (la de esa hoja) o la lista de trazos; el resto del tiempo queda en caché. Cada tanda es su propia
/// capa del tamaño de la hoja: una hoja normal tiene una sola (toda su tinta), y se parte en más solo si hay
/// una imagen, nota o texto en el medio del orden.
/// [sheet]: rectángulo de la hoja en la tira (coordenadas globales); la tinta se recorta a él, así un trazo
/// que cruza de una hoja a la otra se ve en las dos.
/// [hidden]: trazos que no se dibujan acá (los que se están moviendo).
/// Los trazos borrados desde que se armó la lista se saltean (se mira [doc]), así borrar con la goma
/// repinta sin rearmar los widgets.
class InkPainter extends CustomPainter {
  final NotebookDoc doc;
  final List<Stroke> strokes;
  final Rect sheet;
  final double scale;
  final ValueNotifier<int> version;
  final Set<String> Function() hidden;
  InkPainter(this.doc, this.strokes, this.sheet, this.scale, this.version, this.hidden) : super(repaint: version);

  @override
  void paint(Canvas c, Size size) {
    c.scale(scale);
    c.translate(0, -sheet.top);
    c.clipRect(sheet);
    final skip = hidden();
    paintStrokes(c, strokes.where((s) => identical(doc.strokes[s.id], s) && !skip.contains(s.id)));
  }

  @override
  bool shouldRepaint(InkPainter o) =>
      o.doc != doc || o.scale != scale || o.sheet != sheet || !_same(o.strokes, strokes);

  static bool _same(List<Stroke> a, List<Stroke> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }
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
