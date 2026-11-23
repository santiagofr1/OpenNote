import 'dart:math';

import 'package:flutter/painting.dart';

import '../domain/domain.dart';

/// Color de la letra de los textos (y del lápiz por defecto).
const kInk = Color(0xFF22211E);

/// Interlineado fijo = un renglón de [line] unidades, así el texto cae siempre sobre las líneas.
StrutStyle textStrut(double line, {double scale = 1, int lines = 1}) =>
    StrutStyle(fontSize: fontForLine(line) * scale, height: lines * line / fontForLine(line), forceStrutHeight: true);

/// Estilo de letra de un texto en un renglón de [line] unidades (a [scale] píxeles por unidad).
TextStyle textStyle(double line, {double scale = 1, Color? color}) =>
    TextStyle(fontSize: fontForLine(line) * scale, height: line / fontForLine(line), color: color);

// ---------------------------------------------------------------------------------------------
// Texto con formato. Lo comparten el editor (campos) y el dibujo (miniaturas, PNG, PDF): los dos
// parten de [paraLayout], así lo que se ve al escribir es lo que sale impreso.
// ---------------------------------------------------------------------------------------------

/// Sangría de cada nivel y ancho del marcador de lista, en renglones.
const kIndentLines = 1.1, kMarkerLines = 1.1;

/// Tamaño de letra relativo de cada estilo de párrafo.
double paraFontFactor(ParaStyle s) => switch (s) {
      ParaStyle.normal => 1,
      ParaStyle.title => 1.6,
      ParaStyle.subtitle => 1.25,
    };

TextAlign textAlignOf(ParaAlign a) => switch (a) {
      ParaAlign.left => TextAlign.left,
      ParaAlign.center => TextAlign.center,
      ParaAlign.right => TextAlign.right,
      ParaAlign.justify => TextAlign.justify,
    };

/// Estilo de un tramo, para sumar al del párrafo. Un tramo con tamaño en pt usa ese tamaño real
/// (absoluto, a [scale] píxeles por unidad); sin tamaño hereda el del párrafo.
TextStyle runStyle(RunStyle r, {double scale = 1}) => TextStyle(
      fontSize: r.size == null ? null : ptToUnits(r.size!) * scale,
      fontWeight: r.bold ? FontWeight.bold : null,
      fontStyle: r.italic ? FontStyle.italic : null,
      decoration: r.underline || r.strike
          ? TextDecoration.combine([if (r.underline) TextDecoration.underline, if (r.strike) TextDecoration.lineThrough])
          : null,
      color: r.color == null ? null : Color(r.color!),
      backgroundColor: r.highlight == null ? null : Color(r.highlight!),
    );

/// Color con el que se pinta la selección que cruza párrafos.
const kSelectionPaint = Color(0x663B82F6);

/// Un párrafo ya medido en cuanto a estilo: lo que hace falta para dibujarlo o armar su campo.
class ParaLayout {
  final Para para;
  final TextStyle base; // letra del párrafo (tamaño según su estilo)
  final StrutStyle strut;
  final double indent, markerWidth; // ya multiplicados por la escala
  final String? marker; // "•" o "1."; null en tareas y sin lista
  final int lines; // renglones enteros que ocupa cada línea del párrafo (más de 1 si tiene letra grande)
  final double scale;
  const ParaLayout(this.para, this.base, this.strut, this.indent, this.markerWidth, this.marker,
      {this.lines = 1, this.scale = 1});

  /// Dónde empieza el texto del párrafo (sangría + marcador).
  double get textLeft => indent + markerWidth;

  TextAlign get align => textAlignOf(para.align);

  /// Los tramos como hijos de un [TextSpan]; [lead] va antes (el campo lo usa para su carácter guía).
  /// [sel] es un rango local [inicio, fin) que se pinta como seleccionado (selección entre párrafos).
  TextSpan span({String lead = '', (int, int)? sel}) {
    final kids = <InlineSpan>[if (lead.isNotEmpty) TextSpan(text: lead)];
    var pos = 0;
    for (final r in para.runs) {
      final a = pos, b = pos + r.text.length;
      pos = b;
      final st = runStyle(r.style, scale: scale);
      final from = sel == null ? b : max(sel.$1, a), to = sel == null ? b : min(sel.$2, b);
      if (from >= to) {
        kids.add(TextSpan(text: r.text, style: st));
        continue;
      }
      final hl = st.merge(const TextStyle(backgroundColor: kSelectionPaint));
      if (from > a) kids.add(TextSpan(text: r.text.substring(0, from - a), style: st));
      kids.add(TextSpan(text: r.text.substring(from - a, to - a), style: hl));
      if (to < b) kids.add(TextSpan(text: r.text.substring(to - a), style: st));
    }
    return TextSpan(style: base, children: kids);
  }
}

/// Mide el párrafo [p] (con [number] si es numerado) en un renglón de [line] unidades a [scale] px por unidad.
ParaLayout paraLayout(Para p, int number, double line, {double scale = 1, Color color = kInk}) {
  final font = fontForLine(line) * paraFontFactor(p.style) * scale;
  final weight = switch (p.style) {
    ParaStyle.title => FontWeight.bold,
    ParaStyle.subtitle => FontWeight.w600,
    ParaStyle.normal => null,
  };
  final k = paraLines(p, line);
  final base = TextStyle(fontSize: font, height: k * line * scale / font, color: color, fontWeight: weight);
  return ParaLayout(
    p,
    base,
    textStrut(line, scale: scale, lines: k),
    p.indent * kIndentLines * line * scale,
    p.list == ListKind.none ? 0 : kMarkerLines * line * scale,
    switch (p.list) {
      ListKind.bullet => '•',
      ListKind.numbered => '$number.',
      _ => null,
    },
    lines: k,
    scale: scale,
  );
}

/// Renglones enteros que ocupa cada línea del párrafo [p] en un renglón de [line] unidades: uno, o más
/// si tiene letra con tamaño en pt que no entra (la letra más grande por 1,2 de interlineado, redondeado
/// para arriba), así el texto sigue cayendo sobre las líneas del rayado. La letra automática (también la
/// del título) sigue en un renglón.
int paraLines(Para p, double line) {
  var big = 0.0;
  for (final r in p.runs) {
    if (r.style.size != null) big = max(big, ptToUnits(r.style.size!));
  }
  return max(1, (big * 1.2 / line - 1e-6).ceil());
}

/// Casilla de una lista de tareas, dibujada con trazos (no depende de ninguna fuente).
void paintCheckbox(Canvas c, Rect r, bool checked, Color color) {
  final box = RRect.fromRectAndRadius(r, Radius.circular(r.width * .18));
  c.drawRRect(
      box,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, r.width * .1)
        ..color = color);
  if (checked) {
    final path = Path()
      ..moveTo(r.left + r.width * .22, r.top + r.height * .52)
      ..lineTo(r.left + r.width * .44, r.top + r.height * .74)
      ..lineTo(r.left + r.width * .80, r.top + r.height * .26);
    c.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = max(1.2, r.width * .13)
          ..color = color);
  }
}

/// Lado de la casilla de tareas dentro de un renglón de [line] (en las mismas unidades).
double checkboxSide(double line) => line * .55;

/// El bloque entero medido: un [TextPainter] por párrafo, uno sobre otro.
class BlockLayout {
  final List<_ParaBox> _boxes;
  final Size size;
  BlockLayout._(this._boxes, this.size);

  /// Dibuja el bloque con su esquina de arriba a la izquierda en [origin].
  void paint(Canvas c, Offset origin, {Color color = kInk}) {
    for (final b in _boxes) {
      b.tp.paint(c, origin + b.at);
      final m = b.marker;
      if (m != null) m.paint(c, origin + b.markerAt);
      if (b.box != null) paintCheckbox(c, b.box!.shift(origin), b.checked, color);
    }
  }
}

class _ParaBox {
  final TextPainter tp;
  final Offset at;
  final TextPainter? marker;
  final Offset markerAt;
  final Rect? box;
  final bool checked;
  _ParaBox(this.tp, this.at, this.marker, this.markerAt, this.box, this.checked);
}

/// Acomoda los párrafos de [t] en un ancho [t.w * scale], con renglones de [line] unidades.
BlockLayout layoutBlock(TextBlock t, double line, {double scale = 1}) {
  final numbers = t.body.numbering();
  final w = t.w * scale, boxes = <_ParaBox>[];
  var y = 0.0, maxW = 0.0;
  for (var i = 0; i < t.body.paras.length; i++) {
    final pl = paraLayout(t.body.paras[i], numbers[i], line, scale: scale);
    final avail = max(10.0, w - pl.textLeft);
    final tp = TextPainter(
      text: pl.para.isEmpty ? TextSpan(text: ' ', style: pl.base) : pl.span(),
      strutStyle: pl.strut,
      textAlign: pl.align,
      textDirection: TextDirection.ltr,
    );
    pl.align == TextAlign.left ? tp.layout(maxWidth: avail) : tp.layout(minWidth: avail, maxWidth: avail);
    final h = max(tp.height, line * scale);
    TextPainter? marker;
    Rect? box;
    if (pl.marker != null) {
      marker = TextPainter(
        text: TextSpan(text: pl.marker, style: pl.base),
        strutStyle: pl.strut,
        textDirection: TextDirection.ltr,
      )..layout();
    } else if (pl.para.list == ListKind.checklist) {
      final side = checkboxSide(line) * scale;
      box = Rect.fromLTWH(pl.indent, y + (line * scale - side) / 2, side, side);
    }
    boxes.add(_ParaBox(tp, Offset(pl.textLeft, y), marker, Offset(pl.indent, y), box, pl.para.checked));
    maxW = max(maxW, pl.textLeft + tp.width);
    y += h;
  }
  return BlockLayout._(boxes, Size(maxW, y));
}

/// Rectángulo que ocupa un bloque de texto en la página (mínimo un renglón de [line] unidades), ya con su escala y SIN el giro:
/// la esquina de arriba a la izquierda es (x, y) y el tamaño el del bloque por [TextBlock.scale].
Rect textRect(TextBlock t, [double line = kLine]) {
  final s = layoutBlock(t, line).size;
  return Offset(t.x, t.y) & Size(max(s.width, 20) * t.scale, max(s.height, line) * t.scale);
}

/// Las 4 esquinas de [textRect] giradas [TextBlock.angle] alrededor de su centro (arriba-izq, arriba-der, abajo-der, abajo-izq).
List<Offset> textCorners(TextBlock t, [double line = kLine]) {
  final r = textRect(t, line);
  if (t.angle == 0) return [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft];
  final c = r.center, ca = cos(t.angle), sa = sin(t.angle);
  Offset rot(Offset p) {
    final v = p - c;
    return c + Offset(v.dx * ca - v.dy * sa, v.dx * sa + v.dy * ca);
  }

  return [for (final p in [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]) rot(p)];
}

/// Rectángulo que envuelve al texto ya girado (lo que se ve ocupar en la hoja).
Rect textBounds(TextBlock t, [double line = kLine]) {
  if (t.angle == 0) return textRect(t, line);
  return unionRects([for (final p in textCorners(t, line)) Rect.fromPoints(p, p)])!;
}

/// Si el punto [p] cae sobre el texto (con margen [tol]), teniendo en cuenta el giro.
bool textHit(TextBlock t, Offset p, double tol, [double line = kLine]) {
  final r = textRect(t, line);
  if (t.angle == 0) return r.inflate(tol).contains(p);
  final v = p - r.center, ca = cos(-t.angle), sa = sin(-t.angle);
  return r.inflate(tol).contains(r.center + Offset(v.dx * ca - v.dy * sa, v.dx * sa + v.dy * ca));
}

/// Dibuja el bloque [t] con su escala y giro (esquina de arriba a la izquierda en (x, y)).
void paintTextBlock(Canvas c, TextBlock t, double line, {Color color = kInk}) {
  final layout = layoutBlock(t, line);
  if (!t.transformed) return layout.paint(c, Offset(t.x, t.y), color: color);
  final r = textRect(t, line);
  c.save();
  c.translate(r.center.dx, r.center.dy);
  c.rotate(t.angle);
  c.translate(-r.center.dx, -r.center.dy);
  c.translate(t.x, t.y);
  c.scale(t.scale);
  layout.paint(c, Offset.zero, color: color);
  c.restore();
}
