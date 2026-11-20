import 'package:flutter/rendering.dart';

import '../domain/domain.dart';

const _ruleColor = Color(0xFFD5DFEE);
const _marginColor = Color(0xFFF0C9C9);
const _dotColor = Color(0xFFB9C3D3);

/// Renglones / cuadrícula / puntos de una hoja, con origen en su esquina.
/// Los grosores van aparte porque dependen de la escala de quien dibuja.
void paintPaperPattern(Canvas c, String bg, {required double ruleWidth, required double marginWidth}) {
  final rule = Paint()
    ..color = _ruleColor
    ..strokeWidth = ruleWidth;
  switch (bg) {
    case 'lined':
      for (double y = kLine; y < kSheetH; y += kLine) {
        c.drawLine(Offset(0, y), Offset(kW, y), rule);
      }
      c.drawLine(const Offset(70, 0), const Offset(70, kSheetH), Paint()
        ..color = _marginColor
        ..strokeWidth = marginWidth);
    case 'grid':
      const g = kLine / 2;
      for (double y = g; y < kSheetH; y += g) {
        c.drawLine(Offset(0, y), Offset(kW, y), rule);
      }
      for (double x = g; x < kW; x += g) {
        c.drawLine(Offset(x, 0), Offset(x, kSheetH), rule);
      }
    case 'dots':
      const g = kLine / 2;
      final dot = Paint()..color = _dotColor;
      for (double y = g; y < kSheetH; y += g) {
        for (double x = g; x < kW; x += g) {
          c.drawCircle(Offset(x, y), 1.4, dot);
        }
      }
  }
}

/// Fondo del editor: cada hoja con su papel, sombra suave y su patrón.
class SheetPainter extends CustomPainter {
  final String bg, paperColor;
  final double h, scale;
  SheetPainter(this.bg, this.h, this.scale, [this.paperColor = '#fffefb']);

  @override
  void paint(Canvas c, Size size) {
    c.scale(scale);
    final paper = Paint()..color = parseColor(paperColor);
    final shadow = Paint()
      ..color = const Color(0x24000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 / scale);
    for (final r in sheetRects(h)) {
      c.drawRect(r.shift(Offset(0, 4 / scale)), shadow);
      c.drawRect(r, paper);
      c.save();
      c.clipRect(r);
      c.translate(0, r.top);
      // líneas de un píxel de pantalla, sin importar el zoom
      paintPaperPattern(c, bg, ruleWidth: 1 / scale, marginWidth: 1.2 / scale);
      c.restore();
    }
  }

  @override
  bool shouldRepaint(SheetPainter o) => o.bg != bg || o.h != h || o.scale != scale || o.paperColor != paperColor;
}
