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

/// La hoja con MÁS área visible en la vista que va de [viewTop] a [viewBottom] (coordenadas de la página); en un
/// empate, la de arriba. Si la vista cae toda en un hueco entre hojas, la que tiene el centro más cerca.
int mostVisibleSheetFor(double viewTop, double viewBottom, int sheetCount) {
  var best = 0, bestArea = -1.0;
  for (var k = 0; k < sheetCount; k++) {
    final top = k * kSheetStep;
    final area = min(viewBottom, top + kSheetH) - max(viewTop, top);
    if (area > bestArea + 1e-9) {
      best = k;
      bestArea = area;
    }
  }
  if (bestArea > 0) return best;
  final mid = (viewTop + viewBottom) / 2;
  return (mid / kSheetStep).round().clamp(0, max(0, sheetCount - 1));
}

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

/// Transformación de la selección: se escala [scale] y se rota [angle] (radianes) alrededor de [pivot], y después
/// se corre [shift]. Mover es solo [shift]; escalar desde una esquina es [pivot] = la esquina opuesta; rotar,
/// [pivot] = el centro del recuadro. [kx] y [ky] estiran cada eje por separado (manijas del medio de cada lado):
/// se aplican ANTES de escalar y girar, y en la práctica se usan solos (sin giro).
class Xform {
  final Offset pivot;
  final double scale, angle, kx, ky;
  final Offset shift;
  const Xform({this.pivot = Offset.zero, this.scale = 1, this.angle = 0, this.kx = 1, this.ky = 1, this.shift = Offset.zero});

  /// Solo trasladar [d].
  const Xform.move(Offset d) : this(shift: d);

  /// No escala ni rota: es una traslación (y se calcula exacta, sin pasar por senos y cosenos).
  bool get isMove => scale == 1 && angle == 0 && kx == 1 && ky == 1;
  bool get isIdentity => isMove && shift == Offset.zero;

  Offset apply(Offset p) {
    if (isMove) return p + shift;
    final d = p - pivot, v = Offset(d.dx * kx, d.dy * ky) * scale, c = cos(angle), s = sin(angle);
    return pivot + shift + Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
  }

  /// Cuánto se corre [p] (para lo que solo cambia de lugar, como los textos).
  Offset displacement(Offset p) => isMove ? shift : apply(p) - p;

  /// Rectángulo que envuelve a [r] ya transformado.
  Rect applyRect(Rect r) {
    final q = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft].map(apply);
    return unionRects(q.map((p) => Rect.fromPoints(p, p)))!;
  }
}

/// Imán de la rotación: a menos de [tol] radianes (~4°) de 0, 90, 180 o 270° queda justo en ese ángulo.
double snapAngle(double a, {double tol = 4 * pi / 180}) {
  final q = pi / 2, k = (a / q).round();
  return (a - k * q).abs() < tol ? k * q : a;
}
