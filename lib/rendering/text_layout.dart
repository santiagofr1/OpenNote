import 'dart:math';

import 'package:flutter/painting.dart';

import '../domain/domain.dart';

/// Color de la letra de los textos (y del lápiz por defecto).
const kInk = Color(0xFF22211E);

/// Interlineado fijo = un renglón, así el texto cae siempre sobre las líneas.
const kTextStrut = StrutStyle(fontSize: kFont, height: kLine / kFont, forceStrutHeight: true);

/// Rectángulo que ocupa un bloque de texto en la página (mínimo un renglón).
Rect textRect(TextBlock t) {
  final tp = TextPainter(
    text: TextSpan(text: t.text.isEmpty ? ' ' : t.text, style: const TextStyle(fontSize: kFont, height: kLine / kFont)),
    strutStyle: kTextStrut,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: t.w);
  return Offset(t.x, t.y) & Size(max(tp.width, 20), max(tp.height, kLine));
}
