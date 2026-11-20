import 'dart:ui';

import '../domain/domain.dart';
import '../rendering/ink_layers.dart';
import '../rendering/stroke_painter.dart';
import '../theme/colors.dart';
import 'selection.dart';

/// Capa "en vivo", en coordenadas de la página: trazo en curso, goma, rectángulo de selección
/// y los trazos seleccionados mientras se arrastran (en la capa fija quedan ocultos).
void paintLiveLayer(
  Canvas c, {
  required PageData page,
  required double scale,
  required Selection sel,
  Stroke? live,
  Offset? eraserAt,
  double eraserRadius = 0,
}) {
  if (live != null) paintStroke(c, live);
  if (eraserAt != null) {
    c.drawCircle(
      eraserAt,
      eraserRadius,
      Paint()
        ..color = kMuted
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 / scale,
    );
  }
  final border = Paint()
    ..color = kAccent
    ..strokeWidth = 1.5 / scale;
  final band = sel.band;
  if (band != null) {
    c.drawRect(band, Paint()..color = const Color(0x142F5BD3));
    dashedRect(c, band, border, 6 / scale);
  }
  final drag = sel.drag;
  if (drag != null) {
    c.save();
    c.translate(drag.delta.dx, drag.delta.dy);
    for (final s in sel.strokesOf(page)) {
      paintStroke(c, s);
    }
    c.restore();
  }
  final r = sel.bounds(page);
  if (r != null) {
    final rr = r.shift(drag?.delta ?? Offset.zero);
    c.drawRect(rr, Paint()..color = const Color(0x0F2F5BD3));
    dashedRect(c, rr, border, 6 / scale);
  }
}
