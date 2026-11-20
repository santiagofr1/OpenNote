import 'dart:math';
import 'dart:ui';

// Medidas lógicas de la hoja. Se escala para entrar en pantalla, así se ve
// igual en cualquier dispositivo (tablet, PC).
const double kW = 1000, kSheetH = 1414, kLine = 40, kFont = 21;

// Entre hoja y hoja queda un espacio. Hoja + espacio = 1480, múltiplo de kLine,
// así los renglones de todas las hojas caen en la misma grilla.
const double kGap = 66, kSheetStep = kSheetH + kGap;

/// Cantidad de hojas de una página de alto [h].
int sheetCount(double h) => max(1, ((h + kGap) / kSheetStep).round());

/// Alto de una página con [sheets] hojas (sin espacio después de la última).
double heightFor(int sheets) => sheets * kSheetH + (sheets - 1) * kGap;

/// Rectángulos de cada hoja dentro de la página.
List<Rect> sheetRects(double h) => [
      for (var k = 0; k < sheetCount(h); k++) Rect.fromLTWH(0, k * kSheetStep, kW, kSheetH),
    ];

/// Lleva la y de un texto al renglón más cercano (el texto va 4 por debajo de la línea).
double snapTextY(double y) => ((y - 4) / kLine).roundToDouble() * kLine + 4;

/// Envuelve todos los rectángulos; null si no hay ninguno.
Rect? unionRects(Iterable<Rect> rects) {
  Rect? r;
  for (final x in rects) {
    r = r == null ? x : r.expandToInclude(x);
  }
  return r;
}

/// Distancia de [p] al segmento [a]-[b].
double distToSegment(Offset p, Offset a, Offset b) {
  final d = b - a, l = d.distanceSquared;
  final t = l == 0 ? 0.0 : (((p - a).dx * d.dx + (p - a).dy * d.dy) / l).clamp(0.0, 1.0);
  return (p - (a + d * t)).distance;
}
