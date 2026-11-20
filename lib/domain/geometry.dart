import 'dart:math';
import 'dart:ui';

// Medidas lógicas de la hoja. Se escala para entrar en pantalla, así se ve
// igual en cualquier dispositivo (tablet, PC).
const double kW = 1000, kSheetH = 1414, kLine = 40, kFont = 21;
// kLine y kFont son la medida de referencia (renglón y letra de las hojas viejas, ~8,5 mm): la letra es 21/40 del renglón.

// Milímetros reales de A4 (210 x 297 mm): 1 mm = kW / 210 unidades lógicas.
// kSheetH = 1414 ≈ 297 mm (el error es de 0,05 mm), así que al imprimir al 100 % las medidas salen reales.
const double kA4WidthMm = 210, kA4HeightMm = 297, kMm = kW / kA4WidthMm;

/// Milímetros -> unidades lógicas.
double mmToUnits(double mm) => mm * kMm;

/// Unidades lógicas -> milímetros.
double unitsToMm(double u) => u / kMm;

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

/// ¿El segmento [a]-[b] toca el rectángulo [r] (bordes incluidos)? Sirve aunque ninguno de los
/// extremos esté adentro (el segmento lo atraviesa). Recorte de Liang-Barsky.
bool segmentIntersectsRect(Offset a, Offset b, Rect r) {
  var t0 = 0.0, t1 = 1.0;
  final d = b - a;
  bool clip(double p, double q) {
    // p = 0: paralelo a ese borde; q < 0: está del lado de afuera
    if (p == 0) return q >= 0;
    final t = q / p;
    if (p < 0) {
      if (t > t1) return false;
      if (t > t0) t0 = t;
    } else {
      if (t < t0) return false;
      if (t < t1) t1 = t;
    }
    return true;
  }

  return clip(-d.dx, a.dx - r.left) &&
      clip(d.dx, r.right - a.dx) &&
      clip(-d.dy, a.dy - r.top) &&
      clip(d.dy, r.bottom - a.dy);
}
