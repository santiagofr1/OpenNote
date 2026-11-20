import 'package:flutter/rendering.dart';

import '../domain/domain.dart';

const _ruleColor = Color(0xFFD5DFEE);
const _marginColor = Color(0xFFF0C9C9);
const _dotColor = Color(0xFFB9C3D3);

/// Renglones / cuadrícula / puntos de una hoja, con origen en su esquina y medidas en mm reales de A4
/// según [spacing] (ver paper_layout.dart). Los grosores van aparte porque dependen de la escala de quien dibuja.
void paintPaperPattern(Canvas c, String bg, double spacing, {required double ruleWidth, required double marginWidth}) {
  final rule = Paint()
    ..color = _ruleColor
    ..strokeWidth = ruleWidth;
  switch (bg) {
    case 'lined':
      for (final y in ruleYs(spacing)) {
        c.drawLine(Offset(0, y), Offset(kW, y), rule);
      }
      final mx = mmToUnits(kMarginMm);
      c.drawLine(Offset(mx, 0), Offset(mx, kSheetH), Paint()
        ..color = _marginColor
        ..strokeWidth = marginWidth);
    case 'grid':
      for (final y in gridYs(spacing)) {
        c.drawLine(Offset(0, y), Offset(kW, y), rule);
      }
      for (final x in gridXs(spacing)) {
        c.drawLine(Offset(x, 0), Offset(x, kSheetH), rule);
      }
    case 'dots':
      final dot = Paint()..color = _dotColor;
      final xs = gridXs(spacing);
      for (final y in gridYs(spacing)) {
        for (final x in xs) {
          c.drawCircle(Offset(x, y), 1.4, dot);
        }
      }
  }
}

/// Fondo del editor: las hojas de [first] a [last] (las que están armadas), cada una con su papel, sombra suave
/// y su patrón (cada una con el suyo). Las demás no se dibujan.
class SheetPainter extends CustomPainter {
  final List<SheetMeta> sheets;
  final double scale;
  final int first, last;
  final String _sig; // cómo estaban los estilos al crearse (la lista se modifica en el lugar)
  SheetPainter(this.sheets, this.scale, this.first, this.last)
      : _sig = [for (var k = first; k <= last && k < sheets.length; k++) '${sheets[k].bg}${sheets[k].paper}${sheets[k].spacing}'].join('|');

  @override
  void paint(Canvas c, Size size) {
    c.scale(scale);
    final shadow = Paint()
      ..color = const Color(0x24000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 / scale);
    for (var k = first; k <= last && k < sheets.length; k++) {
      final r = Rect.fromLTWH(0, k * kSheetStep, kW, kSheetH);
      c.drawRect(r.shift(Offset(0, 4 / scale)), shadow);
      c.drawRect(r, Paint()..color = parseColor(sheets[k].paper));
      c.save();
      c.clipRect(r);
      c.translate(0, r.top);
      // líneas de un píxel de pantalla, sin importar el zoom
      paintPaperPattern(c, sheets[k].bg, sheets[k].spacing, ruleWidth: 1 / scale, marginWidth: 1.2 / scale);
      c.restore();
    }
  }

  @override
  bool shouldRepaint(SheetPainter o) => o._sig != _sig || o.scale != scale || o.first != first || o.last != last;
}
