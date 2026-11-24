import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/rendering/stroke_painter.dart';
import 'package:flutter_test/flutter_test.dart';

/// El relleno de las formas exactas: polígono a 35 % de opacidad debajo del borde; sin relleno, todo igual que antes.
void main() {
  const size = 120;

  Future<ByteData> render(List<Stroke> strokes) async {
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    c.drawRect(const ui.Rect.fromLTWH(0, 0, 120, 120), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
    paintStrokes(c, strokes);
    final img = await rec.endRecording().toImage(size, size);
    final d = (await img.toByteData())!;
    img.dispose();
    return d;
  }

  List<int> px(ByteData d, int x, int y) => [for (var k = 0; k < 4; k++) d.getUint8((y * size + x) * 4 + k)];

  Stroke rect(String? fill, {double o = 1}) => Stroke('r', 'fine', '#000000', 2,
      exactShapePoints('rect', const ui.Offset(10, 10), const ui.Offset(60, 60)), o, null, fill);

  testWidgets('el interior lleva el color de relleno mezclado al 35 %; sin relleno queda blanco', (t) async {
    await t.runAsync(() async {
      final con = await render([rect('#93c5fd')]);
      final sin = await render([rect(null)]);
      final p = px(con, 35, 35);
      // #93c5fd = (147, 197, 253) sobre blanco a .35
      expect(p[0], closeTo(255 + (147 - 255) * .35, 2));
      expect(p[1], closeTo(255 + (197 - 255) * .35, 2));
      expect(p[2], closeTo(255 + (253 - 255) * .35, 2));
      expect(px(sin, 35, 35), [255, 255, 255, 255]);
      expect(px(con, 100, 100), [255, 255, 255, 255], reason: 'afuera no se pinta');
      // el borde (negro) queda por encima del relleno
      expect(px(con, 10, 35)[0], lessThan(80));
    });
  });

  testWidgets('la opacidad del trazo multiplica la del relleno', (t) async {
    await t.runAsync(() async {
      final p = px(await render([rect('#93c5fd', o: .5)]), 35, 35);
      expect(p[0], closeTo(255 + (147 - 255) * .35 * .5, 2));
    });
  });

  testWidgets('un trazo sin relleno se pinta igual con o sin una forma rellena al lado', (t) async {
    await t.runAsync(() async {
      final pen = Stroke('p', 'pen', '#000000', 3, [for (var i = 0; i < 10; i++) ...[70.0 + i * 4, 90.0, .5]]);
      final alone = await render([pen]);
      final mixed = await render([rect('#fde68a'), pen]);
      // la franja de abajo (donde está el trazo) es idéntica
      for (var y = 80; y < 100; y++) {
        for (var x = 60; x < 120; x++) {
          expect(px(mixed, x, y), px(alone, x, y), reason: '($x, $y)');
        }
      }
    });
  });
}
