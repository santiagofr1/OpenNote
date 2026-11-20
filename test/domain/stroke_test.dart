import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Stroke line() => Stroke('s', 'pen', '#000000', 2, [0, 0, .5, 100, 0, .5]);

  test('bounds incluye el grosor y se recalcula al invalidar', () {
    final s = line();
    final b = s.bounds;
    expect([b.left, b.top, b.right, b.bottom], [closeTo(-3.2, 1e-9), closeTo(-3.2, 1e-9), closeTo(103.2, 1e-9), closeTo(3.2, 1e-9)]);
    s.pts[3] = 200;
    expect(s.bounds.right, closeTo(103.2, 1e-9), reason: 'cacheado');
    s.invalidate();
    expect(s.bounds.right, closeTo(203.2, 1e-9));
  });

  test('moved: copia corrida, con id nuevo si se pide', () {
    final s = line();
    final m = s.moved(const Offset(10, 5), id: 'x');
    expect(m.id, 'x');
    expect(m.pts, [10, 5, .5, 110, 5, .5]);
    expect(s.pts, [0, 0, .5, 100, 0, .5], reason: 'el original no cambia');
    expect(s.moved(Offset.zero).id, 's');
  });

  group('goma (hitBy)', () {
    test('toca el segmento según radio + grosor', () {
      final s = line(); // grosor 2 → margen 1.5
      expect(s.hitBy(const Offset(50, 9), 8), isTrue); // 9 < 8 + 1.5
      expect(s.hitBy(const Offset(50, 10), 8), isFalse);
      expect(s.hitBy(const Offset(-9, 0), 8), isTrue, reason: 'pasando la punta también');
      expect(s.hitBy(const Offset(500, 0), 30), isFalse);
    });

    test('trazo de un solo punto', () {
      final dot = Stroke('d', 'pen', '#000000', 2, [10, 10, .5]);
      expect(dot.hitBy(const Offset(15, 10), 8), isTrue);
      expect(dot.hitBy(const Offset(25, 10), 8), isFalse);
    });
  });

  test('smooth: promedia los puntos del medio y deja las puntas y la presión', () {
    final s = Stroke('s', 'pen', '#000000', 2, [0, 0, .1, 10, 10, .2, 20, 0, .3, 30, 10, .4]);
    s.smooth();
    expect(s.pts, [0, 0, .1, 10, 5, .2, 20, 5, .3, 30, 10, .4]);
    final short = Stroke('s', 'pen', '#000000', 2, [0, 0, .1, 10, 10, .2, 20, 0, .3]);
    short.smooth();
    expect(short.pts[4], 10, reason: 'menos de 4 puntos: no se toca');
  });
}
