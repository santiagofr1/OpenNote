import 'dart:math';

import 'package:flutter/painting.dart';

import '../domain/domain.dart';

/// Color de la letra de los textos (y del lápiz por defecto).
const kInk = Color(0xFF22211E);

/// Interlineado fijo = un renglón de [line] unidades, así el texto cae siempre sobre las líneas.
StrutStyle textStrut(double line, {double scale = 1}) =>
    StrutStyle(fontSize: fontForLine(line) * scale, height: line / fontForLine(line), forceStrutHeight: true);

/// Estilo de letra de un texto en un renglón de [line] unidades (a [scale] píxeles por unidad).
TextStyle textStyle(double line, {double scale = 1, Color? color}) =>
    TextStyle(fontSize: fontForLine(line) * scale, height: line / fontForLine(line), color: color);

/// Rectángulo que ocupa un bloque de texto en la página (mínimo un renglón de [line] unidades).
Rect textRect(TextBlock t, [double line = kLine]) {
  final tp = TextPainter(
    text: TextSpan(text: t.text.isEmpty ? ' ' : t.text, style: textStyle(line)),
    strutStyle: textStrut(line),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: t.w);
  return Offset(t.x, t.y) & Size(max(tp.width, 20), max(tp.height, line));
}
