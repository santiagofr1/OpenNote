import 'dart:math';
import 'dart:ui' show Offset;

import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stress.dart';

/// Figuras inteligentes y herramienta de Formas: entradas degeneradas y al azar. Propiedades: nada tira, todo lo que sale
/// es finito, el contorno tiene el formato de un trazo (x, y, presión), las manijas llevan la esquina adonde se la arrastra,
/// y reconocer una figura perfecta no depende de dónde está ni de qué tan grande es.
void main() {
  bool finito(Iterable<double> v) => v.every((x) => x.isFinite);

  List<double> aplanar(List<Offset> pts) => [for (final p in pts) ...[p.dx, p.dy, .5]];

  /// Puntos cada ~3 unidades sobre la polilínea [v] (cerrada si [close]).
  List<Offset> poli(List<Offset> v, {bool close = true}) {
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

  group('recognizeShape con basura', () {
    for (final seed in kSeeds) {
      test('puntos al azar y degenerados (semilla $seed): no tira y lo que reconoce es finito', () {
        final r = Random(seed);
        for (var it = 0; it < 400; it++) {
          final n = switch (r.nextInt(6)) { 0 => 0, 1 => 1, 2 => 2, 3 => 7, 4 => 8, _ => r.nextInt(400) };
          final modo = r.nextInt(6);
          var x = r.nextDouble() * 1000, y = r.nextDouble() * 1000;
          final pts = <double>[];
          for (var i = 0; i < n; i++) {
            switch (modo) {
              case 0: // todos iguales
                break;
              case 1: // caminata
                x += r.nextDouble() * 20 - 10;
                y += r.nextDouble() * 20 - 10;
              case 2: // todo en una recta
                x += 3;
              case 3: // ruido puro
                x = r.nextDouble() * 1500;
                y = r.nextDouble() * 1500;
              case 4: // diminuto
                x += r.nextDouble() - .5;
                y += r.nextDouble() - .5;
              default: // valores grandes
                x = (r.nextDouble() - .5) * 1e6;
                y = (r.nextDouble() - .5) * 1e6;
            }
            pts.addAll([x, y, r.nextDouble()]);
          }
          if (r.nextInt(5) == 0 && pts.isNotEmpty) pts.removeLast(); // largo que no es múltiplo de 3
          final f = recognizeShape(pts);
          if (f != null) {
            expect(finito([f.center.dx, f.center.dy, f.rx, f.ry, f.angle, for (final v in f.vertices) ...[v.dx, v.dy]]), isTrue, reason: 'it $it modo $modo n $n');
            if (f.kind == ShapeKind.circle) expect(f.rx, f.ry);
            if (f.kind == ShapeKind.line) expect(f.vertices.length, 2);
            if (f.kind == ShapeKind.rect) expect(f.vertices.length, 4);
            if (f.kind == ShapeKind.triangle) expect(f.vertices.length, 3);
            if (modo != 5) {
              // (con coordenadas de millones el contorno tendría millones de puntos: no es el caso a probar)
              final out = f.toPoints(.5);
              expect(out.length % 3, 0, reason: 'it $it: el contorno es una lista de (x, y, presión)');
              expect(out, isNotEmpty);
              expect(finito(out), isTrue);
            }
          }
        }
      });
    }

    test('menos de 8 puntos, o un garabato diminuto, nunca es una figura', () {
      expect(recognizeShape([]), isNull);
      expect(recognizeShape([0, 0, .5]), isNull);
      expect(recognizeShape(aplanar([for (var i = 0; i < 7; i++) Offset(i * 50.0, 0)])), isNull);
      expect(recognizeShape(aplanar([for (var i = 0; i < 50; i++) Offset(i * .1, 0)])), isNull, reason: 'diagonal < 30');
      expect(recognizeShape(aplanar([for (var i = 0; i < 50; i++) const Offset(10, 10)])), isNull, reason: 'un solo punto repetido');
    });
  });

  group('figuras perfectas se reconocen en cualquier lugar y a cualquier tamaño', () {
    for (final seed in kSeeds) {
      test('recta, rectángulo y círculo (semilla $seed)', () {
        final r = Random(seed);
        for (var it = 0; it < 60; it++) {
          final c = Offset(100 + r.nextDouble() * 800, 100 + r.nextDouble() * 1200);
          final w = 80 + r.nextDouble() * 500, h = w * (1.3 + r.nextDouble() * 2);
          final ang = r.nextDouble() * 2 * pi;

          final b = c + Offset(cos(ang), sin(ang)) * w;
          final recta = recognizeShape(aplanar(poli([c, b], close: false)));
          expect(recta?.kind, ShapeKind.line, reason: 'it $it recta $c -> $b');

          final rect = recognizeShape(aplanar(poli([c, c + Offset(w, 0), c + Offset(w, h), c + Offset(0, h)])));
          expect(rect?.kind, ShapeKind.rect, reason: 'it $it rectángulo ${w.round()} x ${h.round()} en $c');

          final circulo = recognizeShape(aplanar([for (var i = 0; i <= 120; i++) c + Offset(cos(2 * pi * i / 120), sin(2 * pi * i / 120)) * w * .5]));
          expect([ShapeKind.circle, ShapeKind.ellipse], contains(circulo?.kind), reason: 'it $it círculo de radio ${w / 2} en $c');
        }
      });
    }
  });

  group('formas exactas (A y B)', () {
    final ids = [for (final k in shapeKinds) k.$1];

    for (final seed in kSeeds) {
      test('para cada forma y puntos al azar (también A == B): contorno finito, en ternas, y las manijas llevan la esquina al punto (semilla $seed)', () {
        final r = Random(seed);
        for (var it = 0; it < 150; it++) {
          final a = Offset(r.nextDouble() * 1000, r.nextDouble() * 1400);
          final b = switch (r.nextInt(5)) {
            0 => a,
            1 => Offset(a.dx, r.nextDouble() * 1400), // vertical
            2 => Offset(r.nextDouble() * 1000, a.dy), // horizontal
            _ => Offset(r.nextDouble() * 1000, r.nextDouble() * 1400),
          };
          for (final kind in ids) {
            final donde = '$kind it $it a=$a b=$b';
            final pts = exactShapePoints(kind, a, b);
            expect(pts.length % 3, 0, reason: donde);
            expect(pts, isNotEmpty, reason: donde);
            expect(finito(pts), isTrue, reason: donde);
            expect(shapeMeasure(kind, a, b, 4.76), isNot(contains('NaN')), reason: donde);
            final caja = shapeBox(kind, a, b);
            expect(finito([caja.left, caja.top, caja.right, caja.bottom]), isTrue, reason: donde);

            final hs = shapeHandlePoints(kind, a, b);
            expect(hs.length, anyOf(2, 4), reason: donde);
            for (var i = 0; i < hs.length; i++) {
              final p = Offset(r.nextDouble() * 1000, r.nextDouble() * 1400);
              final (na, nb) = dragShapeHandle(kind, a, b, i, p);
              expect(finito([na.dx, na.dy, nb.dx, nb.dy]), isTrue, reason: '$donde manija $i');
              final nuevas = shapeHandlePoints(kind, na, nb);
              expect(nuevas.length, hs.length, reason: '$donde: arrastrar una manija no cambia la cantidad de manijas');
              expect(nuevas.any((q) => (q - p).distance < 1e-6), isTrue, reason: '$donde manija $i: el punto $p no quedó en ninguna manija: $nuevas');
              if (kind == 'line' || kind == 'arrow') expect(nuevas[i], p, reason: '$donde: en la recta la manija $i va exacto adonde se la lleva');
            }
          }
        }
      });
    }

    test('A == B: no hay NaN en la flecha ni en el círculo (largo cero)', () {
      for (final kind in ids) {
        final pts = exactShapePoints(kind, const Offset(50, 50), const Offset(50, 50));
        expect(finito(pts), isTrue, reason: kind);
      }
    });

    test('snapAngle15: conserva el largo, es idempotente y cae en múltiplos de 15 grados cuando mueve', () {
      final r = Random(11);
      for (var i = 0; i < 2000; i++) {
        final a = Offset(r.nextDouble() * 1000, r.nextDouble() * 1000);
        final b = a + Offset.fromDirection(r.nextDouble() * 2 * pi, 1 + r.nextDouble() * 500);
        final s = snapAngle15(a, b);
        expect((s - a).distance, closeTo((b - a).distance, 1e-6));
        expect((snapAngle15(a, s) - s).distance, lessThan(1e-6), reason: 'idempotente');
        if ((s - b).distance > 1e-9) {
          final grados = (s - a).direction * 180 / pi / 15;
          expect(grados, closeTo(grados.roundToDouble(), 1e-6));
        }
      }
      expect(snapAngle15(const Offset(5, 5), const Offset(5, 5)), const Offset(5, 5));
    });
  });
}
