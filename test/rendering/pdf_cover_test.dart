import 'dart:typed_data';

import 'package:apuntes/rendering/pdf_cover.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List solid(int w, int h, int r, int g, int b) {
  final px = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    px[i * 4] = r;
    px[i * 4 + 1] = g;
    px[i * 4 + 2] = b;
    px[i * 4 + 3] = 255;
  }
  return px;
}

void paintRect(Uint8List px, int w, int x0, int y0, int x1, int y1, int r, int g, int b) {
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final i = (y * w + x) * 4;
      px[i] = r;
      px[i + 1] = g;
      px[i + 2] = b;
    }
  }
}

void main() {
  test('imagen blanca con una letra negra en el centro: blanco', () {
    final px = solid(100, 100, 255, 255, 255);
    paintRect(px, 100, 45, 45, 55, 55, 0, 0, 0);
    expect(coverColorFromRgba(px, 100, 100, 50, 50, 10), 0xFFFFFFFF);
  });

  test('fondo amarillo parejo: ese amarillo', () {
    final px = solid(100, 100, 250, 240, 120);
    expect(coverColorFromRgba(px, 100, 100, 50, 50, 10), 0xFFFAF078);
  });

  test('anillo fuera de la imagen: blanco', () {
    final px = solid(20, 20, 10, 20, 30);
    expect(coverColorFromRgba(px, 20, 20, 500, 500, 10), 0xFFFFFFFF);
  });

  test('fondo de dos colores: gana el mayoritario', () {
    final px = solid(100, 100, 255, 255, 255);
    paintRect(px, 100, 0, 0, 100, 30, 200, 60, 60); // franja de arriba, minoría
    expect(coverColorFromRgba(px, 100, 100, 50, 50, 12), 0xFFFFFFFF);
    final px2 = solid(100, 100, 200, 60, 60);
    paintRect(px2, 100, 0, 0, 100, 30, 255, 255, 255);
    expect(coverColorFromRgba(px2, 100, 100, 50, 50, 12), 0xFFC83C3C);
  });
}
