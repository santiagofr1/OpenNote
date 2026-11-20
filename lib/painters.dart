import 'package:flutter/material.dart';

import 'model.dart';

void paintStroke(Canvas c, Stroke s) {
  final p = s.pts, n = s.n;
  if (n == 0) return;
  if (s.k == 'hl') {
    final path = Path()..moveTo(p[0], p[1]);
    if (n == 1) path.lineTo(p[0] + .1, p[1]);
    for (var i = 1; i < n; i++) {
      path.lineTo(p[i * 3], p[i * 3 + 1]);
    }
    c.drawPath(
      path,
      Paint()
        ..color = s.color.withAlpha(100)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.w
        ..strokeCap = StrokeCap.butt
        ..strokeJoin = StrokeJoin.round,
    );
    return;
  }
  final paint = Paint()
    ..color = s.color
    ..isAntiAlias = true
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  double width(double pr) => s.w * (.35 + 1.3 * pr);
  if (n == 1) {
    c.drawCircle(Offset(p[0], p[1]), width(p[2]) / 2, paint..style = PaintingStyle.fill);
    return;
  }
  for (var i = 1; i < n; i++) {
    paint.strokeWidth = width(p[i * 3 + 2]);
    c.drawLine(Offset(p[i * 3 - 3], p[i * 3 - 2]), Offset(p[i * 3], p[i * 3 + 1]), paint);
  }
}

/// Fondo de la hoja: papel, renglones/cuadrícula/puntos, margen y cortes de hoja.
class SheetPainter extends CustomPainter {
  final String bg;
  final double h, scale;
  SheetPainter(this.bg, this.h, this.scale);

  @override
  void paint(Canvas c, Size size) {
    c.scale(scale);
    c.drawRect(Rect.fromLTWH(0, 0, kW, h), Paint()..color = const Color(0xFFFFFEFB));
    final rule = Paint()
      ..color = const Color(0xFFD5DFEE)
      ..strokeWidth = 1 / scale;
    switch (bg) {
      case 'lined':
        for (double y = kLine; y < h; y += kLine) {
          c.drawLine(Offset(0, y), Offset(kW, y), rule);
        }
        c.drawLine(const Offset(70, 0), Offset(70, h), Paint()..color = const Color(0xFFF0C9C9)..strokeWidth = 1.2 / scale);
      case 'grid':
        const g = kLine / 2;
        for (double y = g; y < h; y += g) {
          c.drawLine(Offset(0, y), Offset(kW, y), rule);
        }
        for (double x = g; x < kW; x += g) {
          c.drawLine(Offset(x, 0), Offset(x, h), rule);
        }
      case 'dots':
        const g = kLine / 2;
        final dot = Paint()..color = const Color(0xFFB9C3D3);
        for (double y = g; y < h; y += g) {
          for (double x = g; x < kW; x += g) {
            c.drawCircle(Offset(x, y), 1.4, dot);
          }
        }
    }
    final sep = Paint()
      ..color = const Color(0xFFC9C4B8)
      ..strokeWidth = 1.5 / scale;
    for (double y = kSheetH; y < h; y += kSheetH) {
      for (double x = 0; x < kW; x += 14) {
        c.drawLine(Offset(x, y), Offset(x + 7, y), sep);
      }
    }
  }

  @override
  bool shouldRepaint(SheetPainter o) => o.bg != bg || o.h != h || o.scale != scale;
}

/// Todos los trazos guardados. Se repinta solo cuando cambia [version].
class InkPainter extends CustomPainter {
  final PageData page;
  final double scale;
  final ValueNotifier<int> version;
  InkPainter(this.page, this.scale, this.version) : super(repaint: version);

  @override
  void paint(Canvas c, Size size) {
    c.clipRect(Offset.zero & size);
    c.scale(scale);
    final all = page.strokes.values;
    for (final s in all) {
      if (s.k == 'hl') paintStroke(c, s);
    }
    for (final s in all) {
      if (s.k != 'hl') paintStroke(c, s);
    }
  }

  @override
  bool shouldRepaint(InkPainter o) => o.page != page || o.scale != scale;
}

/// El trazo que se está dibujando ahora (y el círculo de la goma).
class LivePainter extends CustomPainter {
  final Stroke? Function() stroke;
  final Offset? Function() eraser;
  final double Function() eraserR;
  final double scale;
  LivePainter(this.stroke, this.eraser, this.eraserR, this.scale, Listenable tick) : super(repaint: tick);

  @override
  void paint(Canvas c, Size size) {
    c.scale(scale);
    final s = stroke();
    if (s != null) paintStroke(c, s);
    final e = eraser();
    if (e != null) {
      c.drawCircle(
        e,
        eraserR(),
        Paint()
          ..color = const Color(0xFF7A776E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 / scale,
      );
    }
  }

  @override
  bool shouldRepaint(LivePainter o) => o.scale != scale;
}
