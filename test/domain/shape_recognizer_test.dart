import 'dart:math';

import 'package:apuntes/domain/domain.dart';
import 'package:flutter/painting.dart' show Offset, Rect;
import 'package:flutter_test/flutter_test.dart';

/// Trazo sintético: recorre [path] (puntos a lo largo de la curva) con ruido de ±1.5 y presión .5.
List<double> _stroke(List<Offset> path, int seed, {double noise = 1.5}) {
  final r = Random(seed);
  double n() => (r.nextDouble() * 2 - 1) * noise;
  return [for (final o in path) ...[o.dx + n(), o.dy + n(), .5]];
}

/// Puntos cada ~3 unidades sobre la polilínea [v] (cerrada si [close]).
List<Offset> _poly(List<Offset> v, {bool close = true}) {
  final vs = close ? [...v, v.first] : v;
  final out = <Offset>[];
  for (var i = 1; i < vs.length; i++) {
    final n = max(1, ((vs[i] - vs[i - 1]).distance / 3).ceil());
    for (var j = 0; j < n; j++) {
      out.add(vs[i - 1] + (vs[i] - vs[i - 1]) * (j / n));
    }
  }
  out.add(vs.last);
  return out;
}

/// Arco de elipse de [t0] a [t1] (radianes), con puntos cada ~3 unidades.
List<Offset> _arc(Offset c, double rx, double ry, double rot, double t0, double t1) {
  final n = ((t1 - t0).abs() * max(rx, ry) / 3).ceil();
  return [
    for (var i = 0; i <= n; i++)
      () {
        final t = t0 + (t1 - t0) * i / n;
        final u = rx * cos(t), v = ry * sin(t);
        return c + Offset(u * cos(rot) - v * sin(rot), u * sin(rot) + v * cos(rot));
      }(),
  ];
}

List<Offset> _regular(Offset c, double r, int k, [double a0 = -pi / 2]) =>
    [for (var i = 0; i < k; i++) c + Offset(cos(a0 + 2 * pi * i / k), sin(a0 + 2 * pi * i / k)) * r];

/// Rectángulo [w]x[h] con esquinas redondeadas de radio [r], centrado en (300, 300), puntos cada ~3 unidades.
List<Offset> _rounded(double w, double h, double r) {
  const c = Offset(300, 300);
  final hw = w / 2, hh = h / 2;
  final out = <Offset>[];
  void line(Offset a, Offset b) {
    final n = max(1, ((b - a).distance / 3).ceil());
    for (var j = 0; j < n; j++) {
      out.add(a + (b - a) * (j / n));
    }
  }

  void corner(Offset m, double a0) => out.addAll(_arc(m, r, r, 0, a0, a0 + pi / 2));
  line(c + Offset(-hw + r, -hh), c + Offset(hw - r, -hh));
  corner(c + Offset(hw - r, -hh + r), -pi / 2);
  line(c + Offset(hw, -hh + r), c + Offset(hw, hh - r));
  corner(c + Offset(hw - r, hh - r), 0);
  line(c + Offset(hw - r, hh), c + Offset(-hw + r, hh));
  corner(c + Offset(-hw + r, hh - r), pi / 2);
  line(c + Offset(-hw, hh - r), c + Offset(-hw, -hh + r));
  corner(c + Offset(-hw + r, -hh + r), pi);
  out.add(out.first);
  return out;
}

double _deg(double r) => r * 180 / pi;

void main() {
  const c = Offset(300, 300);

  group('reconoce', () {
    test('recta inclinada 30 grados', () {
      final a = c, b = c + Offset(cos(pi / 6), sin(pi / 6)) * 300;
      final f = recognizeShape(_stroke(_poly([a, b], close: false), 1))!;
      expect(f.kind, ShapeKind.line);
      expect((f.vertices.first - a).distance, lessThan(4));
      expect((f.vertices.last - b).distance, lessThan(4));
    });

    test('recta casi horizontal queda exactamente horizontal', () {
      final b = c + Offset(cos(2 * pi / 180), sin(2 * pi / 180)) * 300;
      final f = recognizeShape(_stroke(_poly([c, b], close: false), 2))!;
      expect(f.kind, ShapeKind.line);
      expect(f.vertices.last.dy - f.vertices.first.dy, closeTo(0, 1e-6));
    });

    test('círculo (con solape y con hueco)', () {
      for (final (i, end) in [(1, 2 * pi * 1.05), (2, 2 * pi * .92)]) {
        final f = recognizeShape(_stroke(_arc(c, 80, 80, 0, 0, end), 10 + i))!;
        expect(f.kind, ShapeKind.circle, reason: 'caso $i');
        expect((f.center - c).distance, lessThan(5));
        expect(f.rx, closeTo(80, 6));
        expect(f.ry, f.rx);
      }
    });

    test('elipse 150x60 rotada 30 grados', () {
      final f = recognizeShape(_stroke(_arc(c, 150, 60, pi / 6, 0, 2 * pi * 1.03), 3))!;
      expect(f.kind, ShapeKind.ellipse);
      expect(f.rx, closeTo(150, 10));
      expect(f.ry, closeTo(60, 10));
      expect(_deg(f.angle), closeTo(30, 5));
    });

    test('rectángulo alineado: lados exactos', () {
      final v = [c, c + const Offset(240, 0), c + const Offset(240, 140), c + const Offset(0, 140)];
      final f = recognizeShape(_stroke(_poly(v), 4))!;
      expect(f.kind, ShapeKind.rect);
      expect(f.vertices.length, 4);
      for (var i = 0; i < 4; i++) {
        final d = f.vertices[(i + 1) % 4] - f.vertices[i];
        expect(min(d.dx.abs(), d.dy.abs()), lessThan(1e-9));
      }
      final b = Rect.fromPoints(f.vertices[0], f.vertices[2]);
      expect(b.width, closeTo(240, 6));
      expect(b.height, closeTo(140, 6));
    });

    test('rectángulo rotado 25 grados', () {
      final rot = 25 * pi / 180;
      final v = [for (final o in [Offset.zero, const Offset(240, 0), const Offset(240, 140), const Offset(0, 140)]) c + Offset(o.dx * cos(rot) - o.dy * sin(rot), o.dx * sin(rot) + o.dy * cos(rot))];
      final f = recognizeShape(_stroke(_poly(v), 5))!;
      expect(f.kind, ShapeKind.rect);
      final d = f.vertices[1] - f.vertices[0];
      expect(_deg(atan2(d.dy, d.dx)), closeTo(25, 4));
    });

    test('triángulo y pentágono', () {
      final t = recognizeShape(_stroke(_poly([const Offset(300, 200), const Offset(450, 430), const Offset(150, 410)]), 6))!;
      expect(t.kind, ShapeKind.triangle);
      expect(t.vertices.length, 3);
      final p = recognizeShape(_stroke(_poly(_regular(c, 100, 5)), 7))!;
      expect(p.kind, ShapeKind.polygon);
      expect(p.vertices.length, 5);
    });

    test('círculo desprolijo (aplastado, radio oscilante, hueco)', () {
      final path = [
        for (var i = 0; i <= 120; i++)
          () {
            final a = 2 * pi * .88 * i / 120;
            final k = 1 + .06 * sin(3 * a) + .06 * sin(5 * a) * .5;
            return c + Offset(100 * cos(a), 80 * sin(a)) * k;
          }(),
      ];
      final f = recognizeShape(_stroke(path, 20, noise: 2))!;
      expect(f.kind, ShapeKind.circle);
    });

    test('cuadrado con esquinas redondeadas: rect de lados iguales y alineado', () {
      final f = recognizeShape(_stroke(_rounded(200, 200, 35), 21, noise: 3))!;
      expect(f.kind, ShapeKind.rect);
      final w = (f.vertices[1] - f.vertices[0]).distance, h = (f.vertices[3] - f.vertices[0]).distance;
      expect((w - h).abs(), lessThan(1e-6));
      expect((f.vertices[1] - f.vertices[0]).dy.abs(), lessThan(1e-6));
    });

    test('rectángulo 260x150 con esquinas redondeadas no es cuadrado', () {
      final f = recognizeShape(_stroke(_rounded(260, 150, 25), 22))!;
      expect(f.kind, ShapeKind.rect);
      final w = (f.vertices[1] - f.vertices[0]).distance, h = (f.vertices[3] - f.vertices[0]).distance;
      expect((w - h).abs(), greaterThan(50));
    });

    test('cuadrilátero torcido sale como rect alineado', () {
      final v = [const Offset(0, 0), const Offset(250, 12), const Offset(240, 160), const Offset(-8, 150)];
      final f = recognizeShape(_stroke(_poly([for (final o in v) c + o]), 23))!;
      expect(f.kind, ShapeKind.rect);
      expect((f.vertices[1] - f.vertices[0]).dy.abs(), lessThan(1e-6));
    });

    test('rombo (cuadrado rotado 45) sale rect a ~45 grados', () {
      final v = _regular(c, 100, 4, -pi / 2);
      final f = recognizeShape(_stroke(_poly(v), 24))!;
      expect(f.kind, ShapeKind.rect);
      final d = f.vertices[1] - f.vertices[0];
      expect((_deg(atan2(d.dy, d.dx)).abs() - 45).abs(), lessThan(4));
    });

    test('elipse 200x80 sigue siendo elipse', () {
      final f = recognizeShape(_stroke(_arc(c, 100, 40, 0, 0, 2 * pi * 1.03), 25))!;
      expect(f.kind, ShapeKind.ellipse);
    });
  });

  group('no reconoce', () {
    test('zigzag abierto', () {
      final z = [for (var i = 0; i < 6; i++) Offset(100.0 + i * 50, i.isEven ? 100 : 200)];
      expect(recognizeShape(_stroke(_poly(z, close: false), 8)), isNull);
    });

    test('espiral', () {
      final s = [for (var i = 0; i <= 200; i++) c + Offset(cos(i * .08), sin(i * .08)) * (10 + i * .5)];
      expect(recognizeShape(_stroke(s, 9)), isNull);
    });

    test('letra S', () {
      final s = [..._arc(const Offset(300, 250), 50, 50, 0, -pi / 4, 3 * pi / 2), ..._arc(const Offset(300, 350), 50, 50, 0, -pi / 2, pi * .75).reversed];
      expect(recognizeShape(_stroke(s, 12)), isNull);
    });

    test('garabato cerrado tipo estrella de 8 puntas', () {
      final v = [for (var i = 0; i < 16; i++) c + Offset(cos(2 * pi * i / 16), sin(2 * pi * i / 16)) * (i.isEven ? 100 : 45)];
      expect(recognizeShape(_stroke(_poly(v), 13, noise: 6)), isNull);
    });

    test('trazos chicos o con pocos puntos', () {
      expect(recognizeShape(_stroke(_poly([c, c + const Offset(20, 15)], close: false), 14, noise: 0)), isNull);
      expect(recognizeShape([0, 0, .5, 100, 0, .5, 200, 0, .5]), isNull);
    });
  });

  group('ShapeFit', () {
    void checkSpacing(List<double> p, double step) {
      for (var i = 3; i < p.length; i += 3) {
        expect(Offset(p[i] - p[i - 3], p[i + 1] - p[i - 2]).distance, lessThanOrEqualTo(step + 1e-6));
      }
    }

    test('toPoints: cerradas terminan en el primer punto y el espaciado respeta step', () {
      final fits = [
        ShapeFit(ShapeKind.circle, const [], c, rx: 50, ry: 50),
        ShapeFit(ShapeKind.ellipse, const [], c, rx: 90, ry: 30, angle: .4),
        ShapeFit(ShapeKind.rect, [c, c + const Offset(100, 0), c + const Offset(100, 60), c + const Offset(0, 60)], c),
        ShapeFit(ShapeKind.triangle, [c, c + const Offset(100, 0), c + const Offset(50, 80)], c),
      ];
      for (final f in fits) {
        final p = f.toPoints(.7);
        expect(p.length % 3, 0);
        expect([p[p.length - 3], p[p.length - 2]], [p[0], p[1]], reason: '${f.kind}');
        expect(p[2], .7);
        checkSpacing(p, 2);
        checkSpacing(f.toPoints(.7, step: 5), 5);
      }
      final r = fits[2].toPoints(.5);
      final xy = [for (var i = 0; i < r.length; i += 3) Offset(r[i], r[i + 1])];
      for (final v in fits[2].vertices) {
        expect(xy.any((o) => (o - v).distance < 1e-9), isTrue, reason: 'esquina exacta');
      }
    });

    test('toPoints de una recta va de a a b', () {
      final f = ShapeFit(ShapeKind.line, [c, c + const Offset(0, 50)], c + const Offset(0, 25));
      final p = f.toPoints(.5);
      expect([p[0], p[1]], [c.dx, c.dy]);
      expect([p[p.length - 3], p[p.length - 2]], [c.dx, c.dy + 50]);
    });

    test('scaled(2) duplica rx y ry y se aleja del centro', () {
      final e = ShapeFit(ShapeKind.ellipse, const [], c, rx: 90, ry: 30, angle: .4).scaled(2);
      expect([e.rx, e.ry, e.angle], [180, 60, .4]);
      final t = ShapeFit(ShapeKind.triangle, [c, c + const Offset(100, 0), c + const Offset(50, 80)], c + const Offset(50, 27));
      final s = t.scaled(2);
      expect((s.vertices[1] - s.center).distance, closeTo(2 * (t.vertices[1] - t.center).distance, 1e-9));
    });

    test('withLineEnd con imán', () {
      final f = ShapeFit(ShapeKind.line, [c, c + const Offset(100, 0)], c + const Offset(50, 0));
      final h = f.withLineEnd(c + const Offset(200, 6)); // ~1.7 grados: se pega a la horizontal
      expect(h.vertices.last.dy, closeTo(c.dy, 1e-6));
      expect((h.vertices.last - c).distance, closeTo(Offset(200, 6).distance, 1e-6));
      final d = f.withLineEnd(c + const Offset(100, 100)); // 45 grados: no se toca
      expect(d.vertices.last.dx, closeTo(c.dx + 100, 1e-6));
      expect(d.vertices.last.dy, closeTo(c.dy + 100, 1e-6));
      expect(h.center, (h.vertices.first + h.vertices.last) / 2);
    });
  });
}
