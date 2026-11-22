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
  Rect? visible, // zona que se ve (más margen): los trazos arrastrados de afuera no se dibujan
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
  final xf = drag?.xf ?? const Xform();
  // transforma el lienzo como la selección: mover, escalar y rotar alrededor del pivote
  void withXform(void Function() draw) {
    c.save();
    c.translate(xf.pivot.dx + xf.shift.dx, xf.pivot.dy + xf.shift.dy);
    c.rotate(xf.angle);
    c.scale(xf.scale * xf.kx, xf.scale * xf.ky);
    c.translate(-xf.pivot.dx, -xf.pivot.dy);
    draw();
    c.restore();
  }

  if (drag != null) {
    withXform(() {
      for (final s in sel.strokesOf(doc)) {
        if (visible != null && !xf.applyRect(s.bounds).overlaps(visible)) continue;
        paintStroke(c, s);
      }
    });
  }
  final r = sel.bounds(doc);
  if (r != null) {
    withXform(() {
      c.drawRect(r, Paint()..color = const Color(0x0F2F5BD3));
      dashedRect(c, r, border..strokeWidth = 1.5 / scale / xf.scale, 6 / scale / xf.scale);
    });
  }
}
