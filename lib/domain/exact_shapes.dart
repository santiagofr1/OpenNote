/// Formas exactas (herramienta Formas): contorno, medidas, manijas e imanes a partir de dos puntos A y B. Puro.
library;

import 'dart:math';
import 'dart:ui' show Offset, Rect;

import 'shape_recognizer.dart';

const _lineKinds = {'line', 'arrow'};

/// ¿La forma [kind] se puede rellenar? (la recta y la flecha no)
bool shapeFillable(String kind) => !_lineKinds.contains(kind);

/// Lleva el extremo [b] a un múltiplo de 15 grados alrededor de [a] si queda a menos de [tol] (5 grados por defecto).
Offset snapAngle15(Offset a, Offset b, {double tol = 5 * pi / 180}) {
  final d = b - a, len = d.distance;
  if (len < 1e-9) return b;
  const step = 15 * pi / 180;
  final ang = atan2(d.dy, d.dx), k = (ang / step).round();
  if ((ang - k * step).abs() >= tol) return b;
  final s = k * step;
  return a + Offset(cos(s), sin(s)) * len;
}

/// ¿El triángulo de A-B va con la base arriba? (B arriba de A)
bool triangleInverted(Offset a, Offset b) => b.dy < a.dy;

/// La forma como figura (sin la punta de la flecha, que es solo recta).
ShapeFit exactShapeFit(String kind, Offset a, Offset b) {
  final r = Rect.fromPoints(a, b);
  switch (kind) {
    case 'rect':
      return ShapeFit(ShapeKind.rect, [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft], r.center);
    case 'circle':
      final rad = (b - a).distance;
      return ShapeFit(ShapeKind.circle, const [], a, rx: rad, ry: rad);
    case 'ellipse':
      return ShapeFit(ShapeKind.ellipse, const [], r.center, rx: r.width / 2, ry: r.height / 2);
    case 'triangle':
      final inv = triangleInverted(a, b);
      final base = inv ? r.top : r.bottom, apex = Offset(r.center.dx, inv ? r.bottom : r.top);
      return ShapeFit(ShapeKind.triangle, [apex, Offset(r.right, base), Offset(r.left, base)], r.center);
    default:
      return ShapeFit(ShapeKind.line, [a, b], (a + b) / 2);
  }
}

/// Puntos planos [x, y, presión] del trazo de la forma (presión fija .5). La flecha lleva A, B, punta 1, B, punta 2.
List<double> exactShapePoints(String kind, Offset a, Offset b) {
  if (kind == 'arrow') {
    final len = (b - a).distance;
    if (len < 1e-9) return exactShapeFit('line', a, b).toPoints(.5);
    final h = min(18.0, .3 * len), back = (a - b) / len, k = 28 * pi / 180;
    Offset rot(double t) => Offset(back.dx * cos(t) - back.dy * sin(t), back.dx * sin(t) + back.dy * cos(t));
    final h1 = b + rot(k) * h, h2 = b + rot(-k) * h;
    return ShapeFit(ShapeKind.line, [a, b, h1, b, h2], (a + b) / 2).toPoints(.5);
  }
  return exactShapeFit(kind, a, b).toPoints(.5);
}

String _n1(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

/// Texto con las medidas de la forma en mm reales ([unitsPerMm] de la hoja).
String shapeMeasure(String kind, Offset a, Offset b, double unitsPerMm) {
  final d = b - a, w = d.dx.abs() / unitsPerMm, h = d.dy.abs() / unitsPerMm;
  switch (kind) {
    case 'line' || 'arrow':
      var deg = (atan2(-d.dy, d.dx) * 180 / pi).round() % 360;
      if (deg < 0) deg += 360;
      return '${_n1(d.distance / unitsPerMm)} mm · $deg°';
    case 'circle':
      return 'r ${_n1(d.distance / unitsPerMm)} mm';
    case 'triangle':
      return 'base ${_n1(w)} · alto ${_n1(h)} mm';
    default:
      return '${_n1(w)} × ${_n1(h)} mm';
  }
}

/// Rectángulo que contiene la forma.
Rect shapeBox(String kind, Offset a, Offset b) {
  if (kind == 'circle') return Rect.fromCircle(center: a, radius: (b - a).distance);
  return Rect.fromPoints(a, b);
}

/// Posición de las manijas: recta y flecha, A y B; círculo, el centro y el punto del borde (B); las demás, las 4
/// esquinas del rectángulo A-B (arriba izquierda, arriba derecha, abajo derecha, abajo izquierda).
List<Offset> shapeHandlePoints(String kind, Offset a, Offset b) {
  if (_lineKinds.contains(kind) || kind == 'circle') return [a, b];
  final r = Rect.fromPoints(a, b);
  return [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
}

/// Nuevos A y B al llevar la manija [i] a [p]. Recta y flecha: mueve ese extremo. Círculo: el centro mueve todo, el borde
/// cambia el radio. Las demás: esa esquina se mueve y la opuesta queda fija (el triángulo conserva su sentido).
(Offset, Offset) dragShapeHandle(String kind, Offset a, Offset b, int i, Offset p) {
  if (_lineKinds.contains(kind)) return i == 0 ? (p, b) : (a, p);
  if (kind == 'circle') return i == 0 ? (p, b + (p - a)) : (a, p);
  final r = Rect.fromPoints(a, b);
  final corners = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
  final fixed = corners[(i + 2) % 4];
  var na = fixed, nb = p;
  if (kind == 'triangle' && triangleInverted(na, nb) != triangleInverted(a, b)) {
    na = Offset(na.dx, p.dy);
    nb = Offset(p.dx, fixed.dy);
  }
  return (na, nb);
}
