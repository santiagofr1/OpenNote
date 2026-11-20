import 'dart:ui';

import '../domain/domain.dart';

/// Dibuja un trazo según su punta (ver [tips]; 'hl' es el resaltador).
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

/// Dibuja varios trazos: primero los resaltadores, así quedan debajo de la tinta.
void paintStrokes(Canvas c, Iterable<Stroke> strokes) {
  for (final s in strokes) {
    if (s.k == 'hl') paintStroke(c, s);
  }
  for (final s in strokes) {
    if (s.k != 'hl') paintStroke(c, s);
  }
}
