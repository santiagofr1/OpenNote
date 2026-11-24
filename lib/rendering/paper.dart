import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../domain/domain.dart';

const _ruleColor = Color(0xFFD5DFEE);
const _marginColor = Color(0xFFF0C9C9);
const _dotColor = Color(0xFFB9C3D3);
const _boxColor = Color(0xFFAEB9CC);
const _labelColor = Color(0xFF8A96AB);
const _axisColor = Color(0xFF7D8BA3);
const _staffColor = Color(0xFF9AA6BA);

/// Renglones / cuadrícula / puntos de una hoja, con origen en su esquina y medidas en mm reales del tamaño [size]
/// según [spacing] (ver paper_layout.dart). Los grosores van aparte porque dependen de la escala de quien dibuja.
void paintPaperPattern(Canvas c, String bg, double spacing,
    {String size = 'a4', required double ruleWidth, required double marginWidth}) {
  final rule = Paint()
    ..color = _ruleColor
    ..strokeWidth = ruleWidth;
  switch (bg) {
    case 'lined' || 'todo':
      for (final y in ruleYs(spacing, size: size)) {
        c.drawLine(Offset(0, y), Offset(kW, y), rule);
      }
      final mx = marginUnits(size);
      c.drawLine(Offset(mx, 0), Offset(mx, kSheetH), Paint()
        ..color = _marginColor
        ..strokeWidth = marginWidth);
      if (bg == 'todo') _paintTodoBoxes(c, spacing, size, ruleWidth);
    case 'cornell':
      for (final y in ruleYs(spacing, size: size)) {
        c.drawLine(Offset(0, y), Offset(kW, y), rule);
      }
      final u = unitsPerMm(size), h = paperHeightMm(size);
      c.drawLine(Offset(63 * u, 0), Offset(63 * u, (h - 50) * u), Paint()
        ..color = _marginColor
        ..strokeWidth = marginWidth);
      c.drawLine(Offset(0, (h - 50) * u), Offset(kW, (h - 50) * u), Paint()
        ..color = _boxColor
        ..strokeWidth = ruleWidth * 2);
    case 'staff':
      _paintStaff(c, size, ruleWidth);
    case 'weekly':
      _paintWeekly(c, size, ruleWidth);
    case 'monthly':
      _paintMonthly(c, size, ruleWidth);
    case 'mm':
      final ws = [
        for (final w in [0, 1, 2])
          Paint()
            ..color = const [Color(0xFFE8EDF5), Color(0xFFC9D4E5), Color(0xFFA6B6CF)][w]
            ..strokeWidth = ruleWidth * const [0.6, 1.0, 1.4][w]
      ];
      final ys = mmYs(size: size), xs = mmXs(size: size);
      for (final w in [0, 1, 2]) {
        for (final (y, p) in ys) {
          if (p == w) c.drawLine(Offset(0, y), Offset(kW, y), ws[w]);
        }
        for (final (x, p) in xs) {
          if (p == w) c.drawLine(Offset(x, 0), Offset(x, kSheetH), ws[w]);
        }
      }
    case 'axes':
      for (final y in gridYs(spacing, size: size)) {
        c.drawLine(Offset(0, y), Offset(kW, y), rule);
      }
      for (final x in gridXs(spacing, size: size)) {
        c.drawLine(Offset(x, 0), Offset(x, kSheetH), rule);
      }
      _paintAxes(c, spacing, size, ruleWidth);
    case 'grid':
      for (final y in gridYs(spacing, size: size)) {
        c.drawLine(Offset(0, y), Offset(kW, y), rule);
      }
      for (final x in gridXs(spacing, size: size)) {
        c.drawLine(Offset(x, 0), Offset(x, kSheetH), rule);
      }
    case 'dots':
      final dot = Paint()..color = _dotColor;
      final xs = gridXs(spacing, size: size);
      for (final y in gridYs(spacing, size: size)) {
        for (final x in xs) {
          c.drawCircle(Offset(x, y), 1.4 * unitsPerMm(size) / kMm, dot);
        }
      }
  }
}

/// Cuadradito de cada renglón de la lista de tareas.
void _paintTodoBoxes(Canvas c, double spacing, String size, double ruleWidth) {
  final u = unitsPerMm(size), side = 0.55 * spacing * u, left = (kMarginMm - 4) * u - side;
  final p = Paint()
    ..color = _boxColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = ruleWidth * 1.2;
  for (final y in ruleYs(spacing, size: size)) {
    final bottom = y - 0.15 * spacing * u;
    if (bottom - side < 0) continue;
    c.drawRect(Rect.fromLTWH(left, bottom - side, side, side), p);
  }
}

/// Pentagramas de 5 líneas (2,5 mm entre líneas), uno cada 24 mm desde los 25 mm.
void _paintStaff(Canvas c, String size, double ruleWidth) {
  final u = unitsPerMm(size), h = paperHeightMm(size), w = paperWidthMm(size);
  final p = Paint()
    ..color = _staffColor
    ..strokeWidth = ruleWidth;
  for (var top = 25.0; top + 10 <= h - 15 + 0.001; top += 24) {
    for (var i = 0; i < 5; i++) {
      final y = (top + i * 2.5) * u;
      c.drawLine(Offset(15 * u, y), Offset((w - 15) * u, y), p);
    }
  }
}

TextPainter _label(String text, double fontUnits, Color color, {bool italic = false}) => TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(fontSize: fontUnits, color: color, fontStyle: italic ? FontStyle.italic : FontStyle.normal)),
      textDirection: TextDirection.ltr,
    )..layout();

/// Agenda semanal: 2 columnas x 4 filas de cajas con renglones y rótulo del día.
void _paintWeekly(Canvas c, String size, double ruleWidth) {
  final u = unitsPerMm(size), h = paperHeightMm(size), w = paperWidthMm(size);
  const names = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo', 'Notas'];
  final box = Paint()
    ..color = _boxColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = ruleWidth * 1.2;
  final rule = Paint()
    ..color = _ruleColor
    ..strokeWidth = ruleWidth;
  final x0 = 12.0, y0 = 25.0, cw = (w - 24) / 2, ch = (h - 25 - 12) / 4;
  for (var i = 0; i < 8; i++) {
    final bx = x0 + (i % 2) * cw, by = y0 + (i ~/ 2) * ch;
    for (var y = by + 10; y < by + ch - 0.01; y += 8) {
      c.drawLine(Offset((bx + 2) * u, y * u), Offset((bx + cw - 2) * u, y * u), rule);
    }
    _label(names[i], 3.2 * u, _labelColor).paint(c, Offset((bx + 2) * u, (by + 2) * u));
  }
  c.drawRect(Rect.fromLTWH(x0 * u, y0 * u, cw * 2 * u, ch * 4 * u), box);
  c.drawLine(Offset((x0 + cw) * u, y0 * u), Offset((x0 + cw) * u, (y0 + ch * 4) * u), box);
  for (var r = 1; r < 4; r++) {
    c.drawLine(Offset(x0 * u, (y0 + r * ch) * u), Offset((x0 + cw * 2) * u, (y0 + r * ch) * u), box);
  }
}

/// Calendario mensual: fila de días y 7 x 6 cajas, sin números.
void _paintMonthly(Canvas c, String size, double ruleWidth) {
  final u = unitsPerMm(size), h = paperHeightMm(size), w = paperWidthMm(size);
  const days = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
  final box = Paint()
    ..color = _boxColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = ruleWidth * 1.2;
  const x0 = 12.0, y0 = 30.0, hd = 8.0;
  final cw = (w - 24) / 7, ch = (h - 12 - y0 - hd) / 6;
  for (var i = 0; i < 7; i++) {
    final tp = _label(days[i], 3.2 * u, _labelColor);
    tp.paint(c, Offset((x0 + (i + .5) * cw) * u - tp.width / 2, (y0 + hd / 2) * u - tp.height / 2));
  }
  c.drawRect(Rect.fromLTWH(x0 * u, y0 * u, cw * 7 * u, hd * u), box);
  c.drawRect(Rect.fromLTWH(x0 * u, (y0 + hd) * u, cw * 7 * u, ch * 6 * u), box);
  for (var i = 1; i < 7; i++) {
    c.drawLine(Offset((x0 + i * cw) * u, y0 * u), Offset((x0 + i * cw) * u, (y0 + hd + ch * 6) * u), box);
  }
  for (var r = 1; r < 6; r++) {
    c.drawLine(Offset(x0 * u, (y0 + hd + r * ch) * u), Offset((x0 + cw * 7) * u, (y0 + hd + r * ch) * u), box);
  }
}

/// Ejes cartesianos con flechas y numeración cada 2 cuadritos.
void _paintAxes(Canvas c, double spacing, String size, double ruleWidth) {
  final u = unitsPerMm(size), step = spacing * u;
  final (x0, y0) = axesOrigin(spacing, size: size);
  final p = Paint()
    ..color = _axisColor
    ..strokeWidth = ruleWidth * 1.8;
  c.drawLine(Offset(0, y0), Offset(kW, y0), p);
  c.drawLine(Offset(x0, 0), Offset(x0, kSheetH), p);
  // flechitas: dos segmentos de 2,5 mm a +-30 grados del eje
  final a = 2.5 * u, d = math.pi / 6;
  for (final s in [-1, 1]) {
    c.drawLine(Offset(kW, y0), Offset(kW - a * math.cos(d), y0 + s * a * math.sin(d)), p);
    c.drawLine(Offset(x0, 0), Offset(x0 + s * a * math.sin(d), a * math.cos(d)), p);
  }
  final tick = 1.2 * u, fs = 2.6 * u;
  final inside = const Rect.fromLTWH(0, 0, kW, kSheetH);
  for (final sgn in [-1, 1]) {
    for (var n = 2;; n += 2) {
      final x = x0 + sgn * n * step, y = y0 - sgn * n * step;
      final inX = x >= 0 && x <= kW, inY = y >= 0 && y <= kSheetH;
      if (!inX && !inY) break;
      final text = '${sgn * n}';
      if (inX) {
        c.drawLine(Offset(x, y0 - tick), Offset(x, y0 + tick), p);
        final tp = _label(text, fs, _axisColor);
        final r = Rect.fromLTWH(x - tp.width / 2, y0 + tick, tp.width, tp.height);
        if (inside.contains(r.topLeft) && inside.contains(r.bottomRight)) tp.paint(c, r.topLeft);
      }
      if (inY) {
        c.drawLine(Offset(x0 - tick, y), Offset(x0 + tick, y), p);
        final tp = _label(text, fs, _axisColor);
        final r = Rect.fromLTWH(x0 - tick - tp.width, y - tp.height / 2, tp.width, tp.height);
        if (inside.contains(r.topLeft) && inside.contains(r.bottomRight)) tp.paint(c, r.topLeft);
      }
    }
  }
  final z = _label('0', fs, _axisColor);
  z.paint(c, Offset(x0 - tick - z.width, y0 + tick));
  final lx = _label('x', fs, _axisColor, italic: true);
  lx.paint(c, Offset(kW - 3 * u - lx.width, y0 - tick - lx.height));
  final ly = _label('y', fs, _axisColor, italic: true);
  ly.paint(c, Offset(x0 + tick, 3 * u));
}

/// Fondo del editor: las hojas de [first] a [last] (las que están armadas), cada una con su papel, sombra suave
/// y su patrón (cada una con el suyo). Las demás no se dibujan.
class SheetPainter extends CustomPainter {
  final List<SheetMeta> sheets;
  final double scale;
  final int first, last;
  final String _sig; // cómo estaban los estilos al crearse (la lista se modifica en el lugar)
  SheetPainter(this.sheets, this.scale, this.first, this.last)
      : _sig = [for (var k = first; k <= last && k < sheets.length; k++) '${sheets[k].bg}${sheets[k].image}${sheets[k].paper}${sheets[k].spacing}${sheets[k].size}'].join('|');

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
      paintPaperPattern(c, sheets[k].bg, sheets[k].spacing, size: sheets[k].size, ruleWidth: 1 / scale, marginWidth: 1.2 / scale);
      c.restore();
    }
  }

  @override
  bool shouldRepaint(SheetPainter o) => o._sig != _sig || o.scale != scale || o.first != first || o.last != last;
}
