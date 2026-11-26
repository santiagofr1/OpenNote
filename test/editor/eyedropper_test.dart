import 'dart:typed_data';

import 'package:apuntes/editor/eyedropper.dart';
import 'package:flutter_test/flutter_test.dart';

/// El lector de píxeles del cuentagotas: posición lógica × pixelRatio, con tope en los bordes.
void main() {
  // 4 x 2 píxeles: la fila de arriba es rojo, verde, azul, blanco; la de abajo, grises
  PixelBuffer buf({double ratio = 1}) {
    final d = Uint8List.fromList([
      255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255, //
      0, 0, 0, 255, 16, 32, 48, 255, 128, 128, 128, 255, 17, 34, 51, 128,
    ]);
    return PixelBuffer(4, 2, d, ratio);
  }

  test('lee el píxel de la posición', () {
    final b = buf();
    expect(b.hexAt(const Offset(0.5, 0.5)), '#ff0000');
    expect(b.hexAt(const Offset(1.5, 0.5)), '#00ff00');
    expect(b.hexAt(const Offset(2.2, 0.9)), '#0000ff');
    expect(b.hexAt(const Offset(1.0, 1.0)), '#102030', reason: 'el borde izquierdo del píxel pertenece a ese píxel');
  });

  test('multiplica por el pixelRatio', () {
    final b = buf(ratio: 2); // la captura tiene 2 píxeles por cada lógico
    expect(b.hexAt(const Offset(0.4, 0.2)), '#ff0000');
    expect(b.hexAt(const Offset(0.6, 0.2)), '#00ff00');
    expect(b.hexAt(const Offset(1.0, 0.6)), '#808080');
    expect(b.pixelOf(const Offset(1.99, 0.99)), (x: 3, y: 1));
  });

  test('con el punto fuera de la captura toma el borde', () {
    final b = buf();
    expect(b.hexAt(const Offset(-30, -5)), '#ff0000');
    expect(b.hexAt(const Offset(99, -5)), '#ffffff');
    expect(b.hexAt(const Offset(-1, 50)), '#000000');
    expect(b.pixelOf(const Offset(99, 99)), (x: 3, y: 1));
  });

  test('el color sale siempre opaco, aunque el píxel no lo sea', () {
    final b = buf();
    final c = b.colorAt(const Offset(3.5, 1.5));
    expect(c.a, 1.0);
    expect(hexOfColor(c), '#112233');
  });
}
