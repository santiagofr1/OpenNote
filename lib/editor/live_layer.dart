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
  required NotebookDoc doc,
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
    if (sel.capture) {
      // captura (derecha a izquierda): punteado y verde
      final green = Paint()
        ..color = kCapture
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / scale;
      c.drawRect(band, Paint()..color = const Color(0x1A2E9E5B));
      dashedRect(c, band, green, 6 / scale);
    } else {
      // ventana (izquierda a derecha): línea continua y azul
      c.drawRect(band, Paint()..color = const Color(0x142F5BD3));
      c.drawRect(
          band,
          Paint()
            ..color = kAccent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 / scale);
    }
  }
  final drag = sel.drag;
  if (drag != null) {
    c.save();
    c.translate(drag.delta.dx, drag.delta.dy);
    for (final s in sel.strokesOf(doc)) {
      paintStroke(c, s);
    }
    c.restore();
  }
  final r = sel.bounds(doc);
  if (r != null) {
    final rr = r.shift(drag?.delta ?? Offset.zero);
    c.drawRect(rr, Paint()..color = const Color(0x0F2F5BD3));
    dashedRect(c, rr, border, 6 / scale);
  }
}
