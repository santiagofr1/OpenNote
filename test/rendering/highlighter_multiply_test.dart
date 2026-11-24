import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/rendering/stroke_painter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// El resaltador se compone multiplicando con lo que ya está dibujado: sobre blanco queda el color y sobre negro
/// (el texto de un PDF) sigue negro.
void main() {
  Stroke hl([double o = 1]) => Stroke('h', 'hl', '#f7d22c', 20, [5, 40, .5, 95, 40, .5], o);

  /// Rectángulo blanco arriba y negro abajo, el trazo [draw] encima; devuelve los bytes RGBA de 100 x 100.
  Future<ByteData> render(void Function(ui.Canvas) draw) async {
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    c.drawRect(const ui.Rect.fromLTWH(0, 0, 100, 100), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
    c.drawRect(const ui.Rect.fromLTRB(0, 40, 100, 80), ui.Paint()..color = const ui.Color(0xFF000000));
    draw(c);
    final img = await rec.endRecording().toImage(100, 100);
    final d = (await img.toByteData())!;
    img.dispose();
    return d;
  }

  (int, int, int) px(ByteData d, int x, int y) {
    final i = (y * 100 + x) * 4;
    return (d.getUint8(i), d.getUint8(i + 1), d.getUint8(i + 2));
  }

  void check(ByteData d) {
    // fondo: blanco 0..40, negro 40..80; el trazo (alto 20) cubre y 30..50
    final (r1, g1, b1) = px(d, 50, 35);
    expect(r1, greaterThan(180));
    expect(g1, greaterThan(180));
    expect(b1, lessThan(150));
    final (r2, g2, b2) = px(d, 50, 45);
    expect([r2, g2, b2], everyElement(lessThan(40)));
    final (r3, g3, b3) = px(d, 50, 10);
    expect([r3, g3, b3], everyElement(greaterThan(250)));
  }

  for (final o in [1.0, .5]) {
    test('paintStroke con opacidad $o: amarillo sobre blanco, negro sigue negro', () async {
      final d = await render((c) => paintStroke(c, hl(o)));
      if (o == 1) {
        check(d);
      } else {
        final (r, g, b) = px(d, 50, 35);
        expect(b, lessThan(r));
        expect(px(d, 50, 45).$1, lessThan(40));
      }
    });
  }

  test('paintStrokes con un resaltador: lo mismo', () async {
    check(await render((c) => paintStrokes(c, [hl()])));
  });

  test('un trazo pen negro no cambia: negro sobre el blanco', () async {
    final pen = Stroke('p', 'pen', '#000000', 10, [5, 20, .5, 95, 20, .5]);
    final d = await render((c) => paintStroke(c, pen));
    expect([px(d, 50, 20).$1, px(d, 50, 20).$2, px(d, 50, 20).$3], everyElement(lessThan(40)));
    expect(px(d, 50, 5).$1, greaterThan(250));
  });

  testWidgets('un RepaintBoundary entre el trazo y el fondo no corta la mezcla', (t) async {
    final key = GlobalKey();
    await t.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
        key: key,
        child: SizedBox(
          width: 100,
          height: 100,
          child: Stack(children: [
            Positioned.fill(child: Column(children: [
              Expanded(child: Container(color: const Color(0xFFFFFFFF))),
              Expanded(child: Container(color: const Color(0xFF000000))),
            ])),
            Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _HlPainter(Stroke('h', 'hl', '#f7d22c', 20, [5, 50, .5, 95, 50, .5]))))),
          ]),
        ),
      )),
    ));
    final d = (await t.runAsync(() async {
      final b = t.renderObject<RenderRepaintBoundary>(find.byKey(key));
      final img = await b.toImage();
      final d = (await img.toByteData())!;
      img.dispose();
      return d;
    }))!;
    // blanco 0..50, negro 50..100
    // el trazo (y = 50, alto 20) cubre 40..60: mitad sobre blanco (amarillo) y mitad sobre negro (sigue negro)
    final (r, g, b) = px(d, 50, 45);
    expect(r, greaterThan(180));
    expect(g, greaterThan(180));
    expect(b, lessThan(150));
    expect(px(d, 50, 55), (0, 0, 0));
  });
}

class _HlPainter extends CustomPainter {
  final Stroke s;
  const _HlPainter(this.s);
  @override
  void paint(Canvas c, Size size) => paintStroke(c, s);
  @override
  bool shouldRepaint(_HlPainter o) => false;
}
