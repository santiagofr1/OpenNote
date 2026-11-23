/// Figuras inteligentes: reconoce si un trazo a mano es una recta, círculo, elipse, rectángulo, triángulo o
/// polígono, y arma el contorno limpio. Puro (sin widgets): se prueba en la PC.
library;

import 'dart:math';
import 'dart:ui' show Offset;

import 'geometry.dart';

const _minPoints = 8; // menos puntos que esto: no es una figura
const _minDiag = 30.0; // diagonal mínima del trazo (unidades de hoja)
const _resampleN = 64; // puntos con los que se analiza el trazo
const _closedFrac = .22; // cerrada si el hueco entre extremos < esta fracción del largo
const _lineDevMin = 3.0; // desvío máximo de una recta: al menos esto...
const _lineDevFrac = .06; // ...o esta fracción de la cuerda
const _lineStraight = .85; // cuerda / largo mínimo para ser recta
final _lineSnap = 5 * pi / 180; // imán de la recta a horizontal/vertical
const _circleRatio = .75; // min(rx, ry) / max(rx, ry) mínimo para ser círculo
final _ellipseSnap = 8 * pi / 180; // imán del eje de la elipse
const _ellipseSamples = 128; // puntos con los que se mide la distancia a la elipse
const _rdpFrac = .025; // tolerancia de Ramer-Douglas-Peucker sobre el largo
const _mergeFrac = .08; // vértices más cerca que esto (sobre el largo) se fusionan
final _flatAngle = 155 * pi / 180; // ángulo interior mayor: vértice casi colineal
const _minVerts = 3, _maxVerts = 6;
final _rectSnap = 8 * pi / 180; // imán de la orientación del rectángulo
const _polyMaxErr = .045; // error máximo del polígono (sobre la diagonal)
const _polyBeat = .5; // el polígono gana si su error < esto * min(elipse, rect)
const _triMaxErr = .045; // error máximo del triángulo
const _triBeat = .7; // el triángulo gana si su error < esto * min(elipse, rect)
const _rectMaxErr = .06; // error máximo del rectángulo
const _rectBeat = .9; // el rectángulo gana a la elipse si su error < esto * el de la elipse
const _squareRatio = .85; // lado menor / mayor mínimo para igualar los lados
const _ellipseMaxErr = .045; // error máximo de la elipse

enum ShapeKind { line, circle, ellipse, rect, triangle, polygon }

/// Figura reconocida. Contorno en coordenadas de la página.
class ShapeFit {
  final ShapeKind kind;

  /// line: [a, b]; rect/triangle/polygon: esquinas en orden (cerrado implícito); circle/ellipse: vacío.
  final List<Offset> vertices;

  /// line: punto medio; ellipse/circle: centro; polígonos: promedio de los vértices.
  final Offset center;

  /// Solo circle/ellipse (circle: rx == ry, angle 0).
  final double rx, ry, angle;

  const ShapeFit(this.kind, this.vertices, this.center, {this.rx = 0, this.ry = 0, this.angle = 0});

  bool get closed => kind != ShapeKind.line;

  /// Copia escalada [k] alrededor de [center] (vértices, rx, ry).
  ShapeFit scaled(double k) => ShapeFit(kind, [for (final v in vertices) center + (v - center) * k], center,
      rx: rx * k, ry: ry * k, angle: angle);

  /// Copia de una recta con el extremo b movido a [b] (con imán de ángulo a horizontal/vertical).
  ShapeFit withLineEnd(Offset b) {
    assert(kind == ShapeKind.line);
    final a = vertices.first, d = b - a;
    final ang = snapAngle(atan2(d.dy, d.dx), tol: _lineSnap);
    final nb = a + Offset(cos(ang), sin(ang)) * d.distance;
    return ShapeFit(kind, [a, nb], (a + nb) / 2);
  }

  /// Contorno denso para un Stroke: [x, y, presión] planos cada ~[step] unidades, con las esquinas exactas;
  /// las figuras cerradas terminan repitiendo el primer punto.
  List<double> toPoints(double pressure, {double step = 2}) {
    final out = <double>[];
    void add(Offset o) => out.addAll([o.dx, o.dy, pressure]);
    if (kind == ShapeKind.circle || kind == ShapeKind.ellipse) {
      final n = max(24, (2 * pi * max(rx, ry) / step).ceil());
      final c = cos(angle), s = sin(angle);
      Offset at(double t) {
        final u = rx * cos(t), v = ry * sin(t);
        return center + Offset(u * c - v * s, u * s + v * c);
      }

      for (var i = 0; i < n; i++) {
        add(at(2 * pi * i / n));
      }
      add(at(0));
      return out;
    }
    final vs = closed ? [...vertices, vertices.first] : vertices;
    add(vs.first);
    for (var i = 1; i < vs.length; i++) {
      final a = vs[i - 1], b = vs[i];
      final n = max(1, ((b - a).distance / step).ceil());
      for (var j = 1; j <= n; j++) {
        add(j == n ? b : a + (b - a) * (j / n));
      }
    }
    return out;
  }
}

/// Reconoce la figura de los puntos planos [pts] ([x, y, presión, ...] como Stroke.pts). null si no es clara.
ShapeFit? recognizeShape(List<double> pts) {
  final raw = [for (var i = 0; i + 1 < pts.length; i += 3) Offset(pts[i], pts[i + 1])];
  if (raw.length < _minPoints) return null;
  var len = 0.0;
  var x0 = raw.first.dx, x1 = x0, y0 = raw.first.dy, y1 = y0;
  for (var i = 0; i < raw.length; i++) {
    if (i > 0) len += (raw[i] - raw[i - 1]).distance;
    x0 = min(x0, raw[i].dx);
    x1 = max(x1, raw[i].dx);
    y0 = min(y0, raw[i].dy);
    y1 = max(y1, raw[i].dy);
  }
  final diag = Offset(x1 - x0, y1 - y0).distance;
  if (diag < _minDiag || len <= 0) return null;
  final p = _resample(raw, len, _resampleN);
  final closed = (p.first - p.last).distance < _closedFrac * len;
  if (!closed) return _asLine(p, len);

  final ell = _fitEllipse(p);
  final ellErr = _meanDist(p, _ellipsePoly(ell), false) / diag;
  final rect = _fitRectAny(p, diag);
  final rectErr = rect.$2;
  final pol = _fitPolygon(p, len);
  final polErr = pol == null ? double.infinity : _meanDist(p, pol.vertices, true) / diag;
  final other = min(ellErr, rectErr);
  if (pol != null && pol.kind == ShapeKind.triangle && polErr < _triMaxErr && polErr < _triBeat * other) return pol;
  if (rectErr < _rectMaxErr && rectErr < _rectBeat * ellErr) return rect.$1;
  if (pol != null && pol.kind == ShapeKind.polygon && polErr < _polyMaxErr && polErr < _polyBeat * other) return pol;
  if (ellErr < _ellipseMaxErr) return ell;
  return null;
}

ShapeFit? _asLine(List<Offset> p, double len) {
  final a = p.first, b = p.last, chord = (b - a).distance;
  if (chord <= _lineStraight * len) return null;
  var dev = 0.0;
  for (final q in p) {
    dev = max(dev, distToSegment(q, a, b));
  }
  // la desviación se mide a la recta (la cuerda es larga, da lo mismo que al segmento)
  if (dev >= max(_lineDevMin, _lineDevFrac * chord)) return null;
  return ShapeFit(ShapeKind.line, [a, b], (a + b) / 2).withLineEnd(b);
}

/// [n] puntos equiespaciados por longitud de arco (incluye el primero y el último).
List<Offset> _resample(List<Offset> r, double len, int n) {
  final out = [r.first];
  final step = len / (n - 1);
  var acc = 0.0, next = step, i = 1;
  while (out.length < n - 1 && i < r.length) {
    final seg = (r[i] - r[i - 1]).distance;
    if (seg > 0 && acc + seg >= next) {
      out.add(r[i - 1] + (r[i] - r[i - 1]) * ((next - acc) / seg));
      next += step;
    } else {
      acc += seg;
      i++;
    }
  }
  while (out.length < n - 1) {
    out.add(r.last);
  }
  out.add(r.last);
  return out;
}

Offset _centroid(List<Offset> p) => p.fold(Offset.zero, (a, b) => a + b) / p.length.toDouble();

ShapeFit _fitEllipse(List<Offset> p) {
  final c = _centroid(p);
  var sxx = 0.0, syy = 0.0, sxy = 0.0;
  for (final q in p) {
    final d = q - c;
    sxx += d.dx * d.dx;
    syy += d.dy * d.dy;
    sxy += d.dx * d.dy;
  }
  final th = .5 * atan2(2 * sxy, sxx - syy);
  final co = cos(th), si = sin(th);
  var minU = double.infinity, maxU = -double.infinity, minV = double.infinity, maxV = -double.infinity;
  for (final q in p) {
    final d = q - c;
    final u = d.dx * co + d.dy * si, v = -d.dx * si + d.dy * co;
    minU = min(minU, u);
    maxU = max(maxU, u);
    minV = min(minV, v);
    maxV = max(maxV, v);
  }
  final rx = (maxU - minU) / 2, ry = (maxV - minV) / 2;
  final mu = (maxU + minU) / 2, mv = (maxV + minV) / 2;
  final center = c + Offset(mu * co - mv * si, mu * si + mv * co);
  if (min(rx, ry) / max(rx, ry) > _circleRatio) {
    final r = p.fold(0.0, (a, q) => a + (q - center).distance) / p.length;
    return ShapeFit(ShapeKind.circle, const [], center, rx: r, ry: r);
  }
  return ShapeFit(ShapeKind.ellipse, const [], center, rx: rx, ry: ry, angle: snapAngle(th, tol: _ellipseSnap));
}

List<Offset> _ellipsePoly(ShapeFit e) {
  final c = cos(e.angle), s = sin(e.angle);
  return [
    for (var i = 0; i < _ellipseSamples; i++)
      e.center + Offset(e.rx * cos(2 * pi * i / _ellipseSamples) * c - e.ry * sin(2 * pi * i / _ellipseSamples) * s,
          e.rx * cos(2 * pi * i / _ellipseSamples) * s + e.ry * sin(2 * pi * i / _ellipseSamples) * c),
  ];
}

/// Distancia promedio de [p] al contorno [c]: a sus lados si [asPoly], si no a sus puntos.
double _meanDist(List<Offset> p, List<Offset> c, bool asPoly) {
  var sum = 0.0;
  for (final q in p) {
    var m = double.infinity;
    if (asPoly) {
      for (var i = 0; i < c.length; i++) {
        m = min(m, distToSegment(q, c[i], c[(i + 1) % c.length]));
      }
    } else {
      for (final v in c) {
        m = min(m, (q - v).distance);
      }
    }
    sum += m;
  }
  return sum / p.length;
}

List<Offset> _rdp(List<Offset> l, double eps) {
  if (l.length < 3) return l;
  var worst = 0.0, at = 0;
  for (var i = 1; i < l.length - 1; i++) {
    final d = distToSegment(l[i], l.first, l.last);
    if (d > worst) {
      worst = d;
      at = i;
    }
  }
  if (worst <= eps) return [l.first, l.last];
  final a = _rdp(l.sublist(0, at + 1), eps), b = _rdp(l.sublist(at), eps);
  return [...a, ...b.skip(1)];
}

/// Ángulo interior en [b] entre [a] y [c].
double _interior(Offset a, Offset b, Offset c) {
  final u = a - b, v = c - b;
  final l = u.distance * v.distance;
  if (l == 0) return pi;
  return acos(((u.dx * v.dx + u.dy * v.dy) / l).clamp(-1.0, 1.0));
}

ShapeFit? _fitPolygon(List<Offset> p, double len) {
  final c = _centroid(p);
  var far = 0;
  for (var i = 1; i < p.length; i++) {
    if ((p[i] - c).distance > (p[far] - c).distance) far = i;
  }
  final line = [...p.sublist(far), ...p.sublist(0, far), p[far]];
  var v = _rdp(line, _rdpFrac * len)..removeLast();
  var changed = true;
  while (changed && v.length >= 3) {
    changed = false;
    for (var i = 0; i < v.length; i++) {
      final j = (i + 1) % v.length;
      if ((v[i] - v[j]).distance < _mergeFrac * len) {
        final m = (v[i] + v[j]) / 2;
        v = [for (var k = 0; k < v.length; k++) if (k == i) m else if (k != j) v[k]];
        changed = true;
        break;
      }
    }
    if (changed) continue;
    for (var i = 0; i < v.length; i++) {
      if (_interior(v[(i + v.length - 1) % v.length], v[i], v[(i + 1) % v.length]) > _flatAngle) {
        v = [...v.sublist(0, i), ...v.sublist(i + 1)];
        changed = true;
        break;
      }
    }
  }
  final k = v.length;
  if (k < _minVerts || k > _maxVerts) return null;
  if (k == 3) return ShapeFit(ShapeKind.triangle, v, _centroid(v));
  return ShapeFit(ShapeKind.polygon, v, _centroid(v));
}

/// Mejor rectángulo (orientado en φ de -45° a 44°) para [p] y su error sobre la diagonal [diag].
(ShapeFit, double) _fitRectAny(List<Offset> p, double diag) {
  List<Offset> corners(double phi) {
    final co = cos(phi), si = sin(phi);
    var minU = double.infinity, maxU = -double.infinity, minV = double.infinity, maxV = -double.infinity;
    for (final o in p) {
      final u = o.dx * co + o.dy * si, w = -o.dx * si + o.dy * co;
      minU = min(minU, u);
      maxU = max(maxU, u);
      minV = min(minV, w);
      maxV = max(maxV, w);
    }
    Offset back(double u, double w) => Offset(u * co - w * si, u * si + w * co);
    return [back(minU, minV), back(maxU, minV), back(maxU, maxV), back(minU, maxV)];
  }

  var bestPhi = 0.0, bestErr = double.infinity;
  for (var d = -45; d < 45; d++) {
    final phi = d * pi / 180;
    final e = _meanDist(p, corners(phi), true);
    if (e < bestErr) {
      bestErr = e;
      bestPhi = phi;
    }
  }
  final phi = snapAngle(bestPhi, tol: _rectSnap);
  var c = corners(phi);
  final err = _meanDist(p, c, true) / diag;
  final w = (c[1] - c[0]).distance, h = (c[3] - c[0]).distance;
  if (min(w, h) / max(w, h) > _squareRatio) {
    final m = _centroid(c), side = (w + h) / 2;
    final ex = (c[1] - c[0]) / w * (side / 2), ey = (c[3] - c[0]) / h * (side / 2);
    c = [m - ex - ey, m + ex - ey, m + ex + ey, m - ex + ey];
  }
  return (ShapeFit(ShapeKind.rect, c, _centroid(c)), err);
}
