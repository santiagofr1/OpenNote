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
    case 'iso':
      _paintIso(c, spacing, size, ruleWidth);
    case 'hex':
      _paintHex(c, spacing, size, ruleWidth);
    case 'polar':
      _paintPolar(c, size, ruleWidth);
    case 'semilog':
      _paintSemilog(c, size, ruleWidth);
    case 'calli':
      _paintCalli(c, size, ruleWidth);
    case 'storyboard':
      _paintStoryboard(c, size, ruleWidth);
    case 'guitartab':
      _paintTab(c, size, ruleWidth);
    case 'daily':
      _paintDaily(c, size, ruleWidth);
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

/// Fondo del lienzo infinito: un solo papel liso de [width] x [height] unidades, sin sombras, bordes ni patrón.
class CanvasPainter extends CustomPainter {
  final String paper;
  final double height, width, scale;
  CanvasPainter(this.paper, this.height, this.width, this.scale);

  @override
  void paint(Canvas c, Size size) {
    c.scale(scale);
    c.drawRect(Rect.fromLTWH(0, 0, width, height), Paint()..color = parseColor(paper));
  }

  @override
  bool shouldRepaint(CanvasPainter o) => o.paper != paper || o.height != height || o.width != width || o.scale != scale;
}

/// Isométrico: triángulos equiláteros de lado [spacing] (horizontales y dos familias de diagonales a +-60 grados).
void _paintIso(Canvas c, double spacing, String size, double ruleWidth) {
  final u = unitsPerMm(size), h = paperHeightMm(size) * u, w = paperWidthMm(size) * u;
  final p = Paint()
    ..color = _ruleColor
    ..strokeWidth = ruleWidth;
  c.save();
  c.clipRect(Rect.fromLTWH(0, 0, w, h));
  for (final y in isoYsMm(spacing, size: size)) {
    c.drawLine(Offset(0, y * u), Offset(w, y * u), p);
  }
  final run = h / math.sqrt(3);
  for (final x in isoDiagonalXsMm(spacing, size: size)) {
    c.drawLine(Offset(x * u, 0), Offset(x * u + run, h), p);
    c.drawLine(Offset(x * u, 0), Offset(x * u - run, h), p);
  }
  c.restore();
}

/// Panal: hexágonos de lado [spacing].
void _paintHex(Canvas c, double spacing, String size, double ruleWidth) {
  final u = unitsPerMm(size), r = spacing * u;
  final p = Paint()
    ..color = _ruleColor
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = ruleWidth;
  final path = Path();
  for (final ctr in hexCentersMm(spacing, size: size)) {
    for (var k = 0; k < 6; k++) {
      final a = k * math.pi / 3;
      final x = ctr.dx * u + r * math.cos(a), y = ctr.dy * u + r * math.sin(a);
      k == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    path.close();
  }
  c.save();
  c.clipRect(Rect.fromLTWH(0, 0, paperWidthMm(size) * u, paperHeightMm(size) * u));
  c.drawPath(path, p);
  c.restore();
}

/// Polar: centro en la hoja, círculos cada 10 mm, radios cada 15 grados y rótulos cada 30 al borde del círculo mayor.
void _paintPolar(Canvas c, String size, double ruleWidth) {
  final u = unitsPerMm(size), center = Offset(paperWidthMm(size) / 2 * u, paperHeightMm(size) / 2 * u);
  final rmax = polarMaxRadiusMm(size);
  final rule = Paint()
    ..color = _ruleColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = ruleWidth;
  final axis = Paint()
    ..color = _axisColor
    ..strokeWidth = ruleWidth * 1.6;
  for (var r = kPolarRingMm; r <= rmax + 0.001; r += kPolarRingMm) {
    c.drawCircle(center, r * u, rule);
  }
  for (var deg = 0; deg < 360; deg += kPolarSpokeDeg) {
    final a = deg * math.pi / 180, d = Offset(math.cos(a), -math.sin(a));
    c.drawLine(center, center + d * rmax * u, deg % 90 == 0 ? axis : rule);
  }
  final fs = 2.6 * u;
  for (var deg = 0; deg < 360; deg += kPolarLabelDeg) {
    final a = deg * math.pi / 180, tp = _label('$deg°', fs, _axisColor);
    final at = center + Offset(math.cos(a), -math.sin(a)) * (rmax + 4) * u;
    tp.paint(c, at - Offset(tp.width / 2, tp.height / 2));
  }
}

/// Semilogarítmico: eje x lineal cada 5 mm (marcada cada 10) y eje y logarítmico de 3 décadas.
void _paintSemilog(Canvas c, String size, double ruleWidth) {
  final u = unitsPerMm(size), a = semilogAreaMm(size);
  final minor = Paint()
    ..color = _ruleColor
    ..strokeWidth = ruleWidth;
  final major = Paint()
    ..color = _boxColor
    ..strokeWidth = ruleWidth * 1.4;
  for (final (x, w) in semilogXsMm(size)) {
    c.drawLine(Offset(x * u, a.top * u), Offset(x * u, a.bottom * u), w == 1 ? major : minor);
  }
  final right = semilogXsMm(size).last.$1;
  for (final (y, w) in semilogYsMm(size)) {
    c.drawLine(Offset(a.left * u, y * u), Offset(right * u, y * u), w == 1 ? major : minor);
  }
}

/// Caligrafía: grupos de ascendente / altura x / base / descendente con guías inclinadas a 55 grados, finas y claras.
void _paintCalli(Canvas c, String size, double ruleWidth) {
  final u = unitsPerMm(size), w = paperWidthMm(size);
  final guide = Paint()
    ..color = _ruleColor
    ..strokeWidth = ruleWidth;
  final base = Paint()
    ..color = _staffColor
    ..strokeWidth = ruleWidth;
  final slant = Paint()
    ..color = _ruleColor.withValues(alpha: 0.7)
    ..strokeWidth = ruleWidth * 0.6;
  const x0 = 15.0, step = kCalliStepMm, height = 3 * step;
  final dx = height / math.tan(kCalliSlantDeg * math.pi / 180);
  for (final top in calliTopsMm(size)) {
    for (var i = 0; i < 4; i++) {
      final y = (top + i * step) * u;
      c.drawLine(Offset(x0 * u, y), Offset((w - 15) * u, y), i == 2 ? base : guide);
    }
    for (var x = x0; x + dx <= w - 15 + 0.001; x += 10) {
      c.drawLine(Offset(x * u, (top + height) * u), Offset((x + dx) * u, top * u), slant);
    }
  }
}

/// Storyboard: 2 x 3 recuadros 16:9 con 3 renglones cortos debajo de cada uno.
void _paintStoryboard(Canvas c, String size, double ruleWidth) {
  final u = unitsPerMm(size);
  final box = Paint()
    ..color = _boxColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = ruleWidth * 1.2;
  final rule = Paint()
    ..color = _ruleColor
    ..strokeWidth = ruleWidth;
  for (final f in storyboardFramesMm(size)) {
    c.drawRect(Rect.fromLTWH(f.left * u, f.top * u, f.width * u, f.height * u), box);
    for (var i = 1; i <= 3; i++) {
      final y = (f.bottom + i * kStoryLineMm) * u;
      c.drawLine(Offset(f.left * u, y), Offset(f.right * u, y), rule);
    }
  }
}

/// Tablatura: grupos de 6 líneas a 3 mm con "TAB" al inicio de cada uno (misma lógica que el pentagrama).
void _paintTab(Canvas c, String size, double ruleWidth) {
  final u = unitsPerMm(size), w = paperWidthMm(size);
  final p = Paint()
    ..color = _staffColor
    ..strokeWidth = ruleWidth;
  const x0 = 24.0;
  for (final top in tabTopsMm(size)) {
    for (var i = 0; i < 6; i++) {
      final y = (top + i * kTabStepMm) * u;
      c.drawLine(Offset(x0 * u, y), Offset((w - 15) * u, y), p);
    }
    c.drawLine(Offset(x0 * u, top * u), Offset(x0 * u, (top + 5 * kTabStepMm) * u), p);
    c.drawLine(Offset((w - 15) * u, top * u), Offset((w - 15) * u, (top + 5 * kTabStepMm) * u), p);
    for (var i = 0; i < 3; i++) {
      final tp = _label('TAB'[i], 3.4 * u, _labelColor);
      tp.paint(c, Offset(19.5 * u - tp.width / 2, (top + 3 + i * 4.5) * u - tp.height / 2 + 0.5 * u));
    }
  }
}

/// Planificador diario: horas de 7 a 22 con renglón por media hora, y a la derecha Prioridades y Notas.
void _paintDaily(Canvas c, String size, double ruleWidth) {
  final u = unitsPerMm(size), l = dailyLayoutMm(size);
  final box = Paint()
    ..color = _boxColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = ruleWidth * 1.2;
  final rule = Paint()
    ..color = _ruleColor
    ..strokeWidth = ruleWidth;
  Rect r(Rect m) => Rect.fromLTWH(m.left * u, m.top * u, m.width * u, m.height * u);
  c.drawRect(r(l.hours), box);
  c.drawRect(r(l.priorities), box);
  c.drawRect(r(l.notes), box);
  final hours = kDailyLastHour - kDailyFirstHour + 1, gutter = 11.0;
  for (var i = 0; i < hours; i++) {
    final y = l.hours.top + i * l.hourH;
    if (i > 0) c.drawLine(Offset(l.hours.left * u, y * u), Offset(l.hours.right * u, y * u), box);
    c.drawLine(Offset((l.hours.left + gutter) * u, (y + l.hourH / 2) * u), Offset((l.hours.right - 2) * u, (y + l.hourH / 2) * u), rule);
    _label('${kDailyFirstHour + i}:00', 3.0 * u, _labelColor).paint(c, Offset((l.hours.left + 1.5) * u, (y + 1.2) * u));
  }
  c.drawLine(Offset((l.hours.left + gutter) * u, l.hours.top * u), Offset((l.hours.left + gutter) * u, l.hours.bottom * u), rule);
  // prioridades: 3 casilleros con su renglón
  final pr = l.priorities;
  _label('Prioridades', 3.2 * u, _labelColor).paint(c, Offset((pr.left + 2) * u, (pr.top + 2) * u));
  final side = 4.5, sq = Paint()
    ..color = _boxColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = ruleWidth * 1.2;
  final rowH = (pr.height - 10) / 3;
  for (var i = 0; i < 3; i++) {
    final bottom = pr.top + 10 + (i + 1) * rowH - 1.5;
    c.drawRect(Rect.fromLTWH((pr.left + 2) * u, (bottom - side) * u, side * u, side * u), sq);
    c.drawLine(Offset((pr.left + 2 + side + 2) * u, bottom * u), Offset((pr.right - 2) * u, bottom * u), rule);
  }
  // notas: renglones cada 8 mm
  final nt = l.notes;
  _label('Notas', 3.2 * u, _labelColor).paint(c, Offset((nt.left + 2) * u, (nt.top + 2) * u));
  for (var y = nt.top + 10; y < nt.bottom - 0.01; y += 8) {
    c.drawLine(Offset((nt.left + 2) * u, y * u), Offset((nt.right - 2) * u, y * u), rule);
  }
}
