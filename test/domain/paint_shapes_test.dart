import 'dart:math';

import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

class Sink implements ShapeSink {
  final pos = <Offset>[], cols = <int>[], idx = <int>[];
  @override
  int get count => pos.length;
  @override
  int v(double x, double y, [int c = 0]) {
    pos.add(Offset(x, y));
    cols.add(c);
    return pos.length - 1;
  }

  @override
  void tri(int a, int b, int c) => idx..add(a)..add(b)..add(c);
}

Sink build(String id, double r, double rot) {
  final s = Sink();
  paintShape(s, id, 100, 50, r, rot, 0xFF123456);
  return s;
}

void main() {
  for (final id in paintShapeIds.where((i) => i != 'none')) {
    group(id, () {
      test('genera triángulos con índices válidos y color en todos los vértices', () {
        final s = build(id, 10, 1.3);
        expect(s.idx, isNotEmpty);
        expect(s.idx.length % 3, 0);
        expect(s.idx.reduce(max), lessThan(s.count));
        expect(s.cols.every((c) => c == 0xFF123456), isTrue);
        expect(s.pos.every((p) => p.dx.isFinite && p.dy.isFinite), isTrue);
      });

      test('es determinística', () {
        final a = build(id, 10, 2.1), b = build(id, 10, 2.1);
        expect(a.pos, b.pos);
        expect(a.idx, b.idx);
      });

      test('todos sus vértices caen dentro del radio, con cualquier rotación y tamaño', () {
        for (final r in [4.0, 10.0, 25.0]) {
          for (var k = 0; k < 24; k++) {
            final s = build(id, r, k * 2 * pi / 24);
            for (final p in s.pos) {
              expect((p - const Offset(100, 50)).distance, lessThanOrEqualTo(r * 1.0001), reason: '$id r=$r rot=$k');
            }
          }
        }
      });

      test('sin triángulos degenerados de área cero en todos (se lee a tamaño chico)', () {
        final s = build(id, 10, 0);
        var area = 0.0;
        for (var i = 0; i < s.idx.length; i += 3) {
          final a = s.pos[s.idx[i]], b = s.pos[s.idx[i + 1]], c = s.pos[s.idx[i + 2]];
          area += ((b - a).dx * (c - a).dy - (b - a).dy * (c - a).dx).abs() / 2;
        }
        expect(area, greaterThan(15)); // de un círculo de radio 10 (314): al menos unos cuantos puntos cuadrados
      });
    });
  }

  test('"none" y un id desconocido no agregan nada', () {
    expect(build('none', 10, 0).count, 0);
    expect(build('inexistente', 10, 0).count, 0);
  });

  test('las formas derechas casi no rotan; las simétricas giran libres', () {
    Offset first(String id, double rot) => build(id, 10, rot).pos[1];
    expect((first('hearts', 0) - first('hearts', 2 * pi)).distance, lessThan(10 * .6)); // ±15° como mucho
    expect((first('stars', 0) - first('stars', pi)).distance, greaterThan(5));
    expect(first('dots', 0), first('dots', 3));
  });
}
