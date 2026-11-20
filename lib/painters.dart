import 'dart:math';

import 'package:flutter/material.dart';

import 'model.dart';

void paintStroke(Canvas c, Stroke s) {
  if (s.n == 0) return;
  switch (s.k) {
    case 'hl':
      _pathStroke(c, s, s.color.withValues(alpha: s.o), StrokeCap.butt);
      return;
    case 'fine':
      _pathStroke(c, s, s.color.withValues(alpha: s.o), StrokeCap.round);
      return;
    case 'pencil':
      _pencil(c, s);
      return;
  }
  // con opacidad: se dibuja en una capa para que no se oscurezcan las uniones
  final layered = s.o < .999;
  if (layered) c.saveLayer(s.bounds, Paint()..color = Color.fromRGBO(0, 0, 0, s.o));
  if (s.k == 'calli') {
    _calli(c, s);
  } else if (s.k == 'fountain') {
    _variable(c, s, .15, 1.7, true);
  } else {
    _variable(c, s, .35, 1.3, false);
  }
  if (layered) c.restore();
}

/// trazo de grosor constante (fibra, resaltador), suavizado con curvas
void _pathStroke(Canvas c, Stroke s, Color color, StrokeCap cap) {
  final p = s.pts, n = s.n;
  final path = Path()..moveTo(p[0], p[1]);
  if (n == 1) path.lineTo(p[0] + .1, p[1]);
  for (var i = 1; i < n - 1; i++) {
    path.quadraticBezierTo(p[i * 3], p[i * 3 + 1], (p[i * 3] + p[i * 3 + 3]) / 2, (p[i * 3 + 1] + p[i * 3 + 4]) / 2);
  }
  if (n > 1) path.lineTo(p[n * 3 - 3], p[n * 3 - 2]);
  c.drawPath(
    path,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.w
      ..strokeCap = cap
      ..strokeJoin = StrokeJoin.round,
  );
}

/// grosor según presión (bolígrafo) y además según velocidad (pluma)
void _variable(Canvas c, Stroke s, double minF, double rangeF, bool speed) {
  final p = s.pts, n = s.n;
  final paint = Paint()
    ..color = s.color
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  if (n == 1) {
    c.drawCircle(Offset(p[0], p[1]), s.w * (minF + rangeF * p[2]) / 2, paint..style = PaintingStyle.fill);
    return;
  }
  double f = 1;
  for (var i = 1; i < n; i++) {
    final a = Offset(p[i * 3 - 3], p[i * 3 - 2]), b = Offset(p[i * 3], p[i * 3 + 1]);
    if (speed) {
      final target = (1.25 - (b - a).distance / (s.w * 3 + 3)).clamp(.45, 1.15);
      f = f * .7 + target * .3;
    }
    paint.strokeWidth = s.w * (minF + rangeF * p[i * 3 + 2]) * f;
    c.drawLine(a, b, paint);
  }
}

/// lápiz: más claro con poca presión, con algo de grano
void _pencil(Canvas c, Stroke s) {
  final p = s.pts, n = s.n;
  final paint = Paint()
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  final grain = Paint()
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  if (n == 1) {
    c.drawCircle(Offset(p[0], p[1]), s.w * .4, paint..color = s.color.withValues(alpha: s.o * .6));
    return;
  }
  for (var i = 1; i < n; i++) {
    final pr = p[i * 3 + 2];
    final a = Offset(p[i * 3 - 3], p[i * 3 - 2]), b = Offset(p[i * 3], p[i * 3 + 1]);
    paint
      ..color = s.color.withValues(alpha: s.o * (.28 + .6 * pr))
      ..strokeWidth = s.w * (.55 + .6 * pr);
    c.drawLine(a, b, paint);
    // grano: una línea fina corrida, pseudoaleatoria pero estable
    final j = ((i * 7919) % 13 - 6) / 6 * s.w * .3;
    grain
      ..color = s.color.withValues(alpha: s.o * (.12 + .25 * pr))
      ..strokeWidth = s.w * .35;
    c.drawLine(a + Offset(j, -j), b + Offset(j, -j), grain);
  }
}

/// caligrafía: punta plana a 45°, gruesa o fina según la dirección
void _calli(Canvas c, Stroke s) {
  final p = s.pts, n = s.n;
  final fill = Paint()..color = s.color;
  final line = Paint()
    ..color = s.color
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke
    ..strokeWidth = s.w * .22;
  const dir = Offset(.7071, -.7071);
  for (var i = 0; i < n; i++) {
    final b = Offset(p[i * 3], p[i * 3 + 1]);
    final a = i == 0 ? b : Offset(p[i * 3 - 3], p[i * 3 - 2]);
    final nb = dir * (s.w * (.55 + .9 * p[i * 3 + 2]));
    final path = Path()
      ..moveTo((a + nb).dx, (a + nb).dy)
      ..lineTo((b + nb).dx, (b + nb).dy)
      ..lineTo((b - nb).dx, (b - nb).dy)
      ..lineTo((a - nb).dx, (a - nb).dy)
      ..close();
    c.drawPath(path, fill);
    c.drawLine(a, b, line);
  }
}

/// Rectángulos de cada hoja dentro de la página (con espacio entre hojas).
List<Rect> sheetRects(double h) => [
      for (var k = 0; k < sheetCount(h); k++) Rect.fromLTWH(0, k * kSheetStep, kW, kSheetH),
    ];

/// Fondo: cada hoja con su papel, sombra suave, renglones/cuadrícula/puntos y margen.
class SheetPainter extends CustomPainter {
  final String bg;
  final double h, scale;
  SheetPainter(this.bg, this.h, this.scale);

  @override
  void paint(Canvas c, Size size) {
    c.scale(scale);
    final paper = Paint()..color = const Color(0xFFFFFEFB);
    final shadow = Paint()
      ..color = const Color(0x24000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 / scale);
    final rule = Paint()
      ..color = const Color(0xFFD5DFEE)
      ..strokeWidth = 1 / scale;
    final dot = Paint()..color = const Color(0xFFB9C3D3);
    for (final r in sheetRects(h)) {
      c.drawRect(r.shift(Offset(0, 4 / scale)), shadow);
      c.drawRect(r, paper);
      c.save();
      c.clipRect(r);
      c.translate(0, r.top);
      switch (bg) {
        case 'lined':
          for (double y = kLine; y < kSheetH; y += kLine) {
            c.drawLine(Offset(0, y), Offset(kW, y), rule);
          }
          c.drawLine(const Offset(70, 0), const Offset(70, kSheetH), Paint()..color = const Color(0xFFF0C9C9)..strokeWidth = 1.2 / scale);
        case 'grid':
          const g = kLine / 2;
          for (double y = g; y < kSheetH; y += g) {
            c.drawLine(Offset(0, y), Offset(kW, y), rule);
          }
          for (double x = g; x < kW; x += g) {
            c.drawLine(Offset(x, 0), Offset(x, kSheetH), rule);
          }
        case 'dots':
          const g = kLine / 2;
          for (double y = g; y < kSheetH; y += g) {
            for (double x = g; x < kW; x += g) {
              c.drawCircle(Offset(x, y), 1.4, dot);
            }
          }
      }
      c.restore();
    }
  }

  @override
  bool shouldRepaint(SheetPainter o) => o.bg != bg || o.h != h || o.scale != scale;
}

/// Todos los trazos guardados. Se repinta solo cuando cambia [version].
/// [hidden]: trazos que no se dibujan acá (los que se están moviendo).
class InkPainter extends CustomPainter {
  final PageData page;
  final double scale;
  final ValueNotifier<int> version;
  final Set<String> Function() hidden;
  InkPainter(this.page, this.scale, this.version, this.hidden) : super(repaint: version);

  @override
  void paint(Canvas c, Size size) {
    c.scale(scale);
    // la tinta solo se ve sobre las hojas, no en el espacio entre ellas
    final clip = Path();
    for (final r in sheetRects(page.h)) {
      clip.addRect(r);
    }
    c.clipPath(clip);
    final skip = hidden();
    final all = page.strokes.values.where((s) => !skip.contains(s.id));
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

/// Dibuja la hoja [sheet] de una página, completa (papel, renglones, tinta y texto),
/// en coordenadas lógicas con origen en la esquina de esa hoja. Para miniaturas y PDF.
void paintSheet(Canvas c, PageData page, int sheet, double pxPerUnit) {
  final top = sheet * kSheetStep;
  c.save();
  c.clipRect(const Rect.fromLTWH(0, 0, kW, kSheetH));
  c.drawRect(const Rect.fromLTWH(0, 0, kW, kSheetH), Paint()..color = const Color(0xFFFFFEFB));
  final rule = Paint()
    ..color = const Color(0xFFD5DFEE)
    ..strokeWidth = max(.6, 1 / pxPerUnit);
  switch (page.bg) {
    case 'lined':
      for (double y = kLine; y < kSheetH; y += kLine) {
        c.drawLine(Offset(0, y), Offset(kW, y), rule);
      }
      c.drawLine(const Offset(70, 0), const Offset(70, kSheetH), Paint()..color = const Color(0xFFF0C9C9)..strokeWidth = max(.8, 1.2 / pxPerUnit));
    case 'grid':
      const g = kLine / 2;
      for (double y = g; y < kSheetH; y += g) {
        c.drawLine(Offset(0, y), Offset(kW, y), rule);
      }
      for (double x = g; x < kW; x += g) {
        c.drawLine(Offset(x, 0), Offset(x, kSheetH), rule);
      }
    case 'dots':
      const g = kLine / 2;
      final dot = Paint()..color = const Color(0xFFB9C3D3);
      for (double y = g; y < kSheetH; y += g) {
        for (double x = g; x < kW; x += g) {
          c.drawCircle(Offset(x, y), 1.4, dot);
        }
      }
  }
  c.translate(0, -top);
  final visible = Rect.fromLTWH(0, top, kW, kSheetH);
  final all = page.strokes.values.where((s) => s.bounds.overlaps(visible)).toList();
  for (final s in all) {
    if (s.k == 'hl') paintStroke(c, s);
  }
  for (final s in all) {
    if (s.k != 'hl') paintStroke(c, s);
  }
  for (final t in page.texts.values) {
    if (t.text.trim().isEmpty || t.y > top + kSheetH || t.y + kLine * 40 < top) continue;
    final tp = TextPainter(
      text: TextSpan(text: t.text, style: const TextStyle(fontSize: kFont, height: kLine / kFont, color: Color(0xFF22211E))),
      strutStyle: const StrutStyle(fontSize: kFont, height: kLine / kFont, forceStrutHeight: true),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: t.w);
    tp.paint(c, Offset(t.x, t.y));
  }
  c.restore();
}

/// Miniatura de la primera hoja de una página
class SheetThumbPainter extends CustomPainter {
  final PageData page;
  SheetThumbPainter(this.page);
  @override
  void paint(Canvas c, Size size) {
    final k = size.width / kW;
    c.scale(k);
    paintSheet(c, page, 0, k);
  }

  @override
  bool shouldRepaint(SheetThumbPainter o) => o.page != page || o.page.rev != page.rev;
}
