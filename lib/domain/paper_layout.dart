import 'dart:math';
import 'dart:ui' show Offset, Rect;

import 'geometry.dart';

// Medidas del fondo de una hoja en milímetros reales del tamaño de la hoja (A5, A4 o A3). Todo puro: lo usan el dibujo del
// papel (miniaturas, PNG, PDF y editor) y el acomodo del texto con teclado.

/// Tamaños de hoja: (id guardado, nombre en pantalla). Los tres tienen la misma proporción, así la hoja lógica
/// (kW x kSheetH) es la misma y solo cambia cuántas unidades vale un milímetro.
const kPaperSizes = [('a5', 'A5'), ('a4', 'A4'), ('a3', 'A3')];

double paperWidthMm(String size) => switch (size) { 'a5' => 148, 'a3' => 297, _ => 210 };

double paperHeightMm(String size) => switch (size) { 'a5' => 210, 'a3' => 420, _ => 297 };

/// Unidades lógicas por milímetro real en una hoja de tamaño [size].
double unitsPerMm(String size) => kW / paperWidthMm(size);

/// [v] si es un tamaño conocido; si no, A4.
String validPaperSize(Object? v) => v == 'a5' || v == 'a3' ? v as String : 'a4';

/// Interlineados del rayado y paso de la cuadrícula / puntos, en mm.
const kLinedSpacings = [7.0, 8.0, 10.0], kGridSpacings = [5.0, 7.0];

/// Margen rojo del rayado (desde el borde izquierdo) y altura aproximada del primer renglón, en mm.
const double kMarginMm = 25, kTopMarginMm = 25;

/// Margen izquierdo y altura del primer renglón en unidades lógicas, según el tamaño de la hoja.
double marginUnits(String size) => kMarginMm * unitsPerMm(size);

double topMarginUnits(String size) => kTopMarginMm * unitsPerMm(size);

/// Interlineado de los textos de una hoja lisa, en mm.
const double kBlankLineMm = 8;

/// Opciones de [spacing] (mm) según el fondo; vacío si no tiene (liso).
List<double> spacingsFor(String bg) => switch (bg) {
      'lined' || 'cornell' || 'todo' => kLinedSpacings,
      'grid' || 'dots' || 'axes' || 'iso' || 'hex' => kGridSpacings,
      _ => const [],
    };

/// Espaciado por defecto del fondo: rayado 8 mm, cuadriculado y puntos 5 mm.
double defaultSpacing(String bg) => switch (bg) {
      'grid' || 'dots' || 'axes' || 'iso' || 'hex' => 5,
      _ => 8,
    };

/// [spacing] si es una opción del fondo [bg]; si no, el por defecto (al cambiar de fondo).
double validSpacing(String bg, double spacing) => spacingsFor(bg).contains(spacing) ? spacing : defaultSpacing(bg);

/// Cantidad de milímetros como texto corto ("8", "7.5").
String fmtMm(double mm) => mm == mm.roundToDouble() ? mm.round().toString() : mm.toString();

/// Altura (mm, desde el borde de arriba de la hoja) de la primera línea horizontal del fondo.
/// Rayado: múltiplo del interlineado cercano a 25 mm. Cuadriculado y puntos: centrada, sobra lo mismo arriba y abajo.
double gridOriginMm(String bg, double spacing, {String size = 'a4'}) => switch (bg) {
      'grid' || 'dots' || 'axes' => (paperHeightMm(size) % spacing) / 2,
      'mm' => (paperHeightMm(size) % 10) / 2,
      _ => 0,
    };

// ---- fondos de red: isométrico y hexagonal ----

/// Distancia (mm) entre las horizontales del isométrico: la altura de un triángulo equilátero de lado [spacing].
double isoRowMm(double spacing) => spacing * sqrt(3) / 2;

/// Alturas (mm, desde arriba) de las horizontales del isométrico, de borde a borde de la hoja.
List<double> isoYsMm(double spacing, {String size = 'a4'}) {
  final h = paperHeightMm(size), r = isoRowMm(spacing);
  return [for (var n = 0; n * r <= h + 0.001; n++) n * r];
}

/// Posiciones x (mm) donde las diagonales del isométrico cruzan el borde de arriba, cada [spacing]. Las de una familia
/// bajan hacia la derecha (a 60 grados) y las de la otra hacia la izquierda; arrancan fuera de la hoja para cubrirla entera.
List<double> isoDiagonalXsMm(double spacing, {String size = 'a4'}) {
  final w = paperWidthMm(size), h = paperHeightMm(size), run = h / sqrt(3);
  return [for (var x = -(run / spacing).ceil() * spacing; x < w + run + spacing; x += spacing) x];
}

/// Centros (mm) de los hexágonos de lado [spacing] (con dos lados horizontales) que tocan la hoja.
List<Offset> hexCentersMm(double spacing, {String size = 'a4'}) {
  final w = paperWidthMm(size), h = paperHeightMm(size), hh = spacing * sqrt(3);
  final out = <Offset>[];
  for (var i = 0;; i++) {
    final cx = i * 1.5 * spacing;
    if (cx - spacing > w) break;
    final off = i.isOdd ? hh / 2 : 0.0;
    for (var cy = off - hh; cy - hh / 2 <= h; cy += hh) {
      if (cy + hh / 2 >= 0) out.add(Offset(cx, cy));
    }
  }
  return out;
}

// ---- polar ----

/// Cada cuántos mm va un círculo concéntrico y cada cuántos grados un radio (y un rótulo de ángulo cada 30).
const double kPolarRingMm = 10;
const int kPolarSpokeDeg = 15, kPolarLabelDeg = 30;

/// Radio (mm) del círculo más grande: múltiplo de 10 que deja lugar a los rótulos de ángulo dentro de la hoja.
double polarMaxRadiusMm(String size) => ((paperWidthMm(size) / 2 - 8) / kPolarRingMm).floor() * kPolarRingMm;

// ---- semilogarítmico ----

const double kSemilogMarginMm = 12;
const int kSemilogDecades = 3;

/// Rectángulo (mm) del papel semilogarítmico: márgenes de 12 mm; el ancho es múltiplo de 5 mm (eje x lineal cada 5 mm).
Rect semilogAreaMm(String size) {
  final w = ((paperWidthMm(size) - 2 * kSemilogMarginMm) / 5).floor() * 5.0;
  return Rect.fromLTWH(kSemilogMarginMm, kSemilogMarginMm, w, paperHeightMm(size) - 2 * kSemilogMarginMm);
}

/// Posiciones x (mm) y peso (1 cada 10 mm, 0 el resto) del eje lineal, incluidos los bordes del área.
List<(double, int)> semilogXsMm(String size) {
  final a = semilogAreaMm(size);
  return [for (var n = 0; n * 5 <= a.width + 0.001; n++) (a.left + n * 5, n.isEven ? 1 : 0)];
}

/// Alturas (mm desde arriba) del eje logarítmico: 3 décadas ajustadas al alto del área, con las líneas del 1 al 10 de
/// cada década. Peso 1 para los límites de década. De arriba hacia abajo.
List<(double, int)> semilogYsMm(String size) {
  final a = semilogAreaMm(size), dh = a.height / kSemilogDecades;
  final out = <(double, int)>[(a.top, 1)];
  for (var d = kSemilogDecades - 1; d >= 0; d--) {
    for (var k = 9; k >= 1; k--) {
      out.add((a.bottom - (d + log(k.toDouble()) / ln10) * dh, k == 1 ? 1 : 0));
    }
  }
  return out;
}

// ---- plantillas de guías ----

/// Grupos de caligrafía: cada uno con ascendente, altura x, línea de base y descendente a 5 mm entre sí; inclinación
/// de las guías en grados.
const double kCalliStepMm = 5, kCalliPitchMm = 25, kCalliTopMm = 20, kCalliSlantDeg = 55;

/// Alturas (mm) del borde de arriba de cada grupo de caligrafía.
List<double> calliTopsMm(String size) {
  final h = paperHeightMm(size);
  return [for (var t = kCalliTopMm; t + 3 * kCalliStepMm <= h - 15 + 0.001; t += kCalliPitchMm) t];
}

/// Tablatura: 6 líneas a 3 mm; un grupo cada 30 mm desde los 25 mm.
const double kTabStepMm = 3, kTabPitchMm = 30, kTabTopMm = 25;

List<double> tabTopsMm(String size) {
  final h = paperHeightMm(size);
  return [for (var t = kTabTopMm; t + 5 * kTabStepMm <= h - 15 + 0.001; t += kTabPitchMm) t];
}

/// Storyboard: 2 x 3 recuadros 16:9 con 3 renglones de 7 mm debajo de cada uno.
const double kStoryMarginMm = 12, kStoryTopMm = 20, kStoryGapMm = 8, kStoryLineMm = 7, kStoryRowGapMm = 6;

/// Recuadros (mm) del storyboard, por filas de izquierda a derecha.
List<Rect> storyboardFramesMm(String size) {
  final w = paperWidthMm(size), cw = (w - 2 * kStoryMarginMm - kStoryGapMm) / 2, fh = cw * 9 / 16;
  final pitch = fh + 3 * kStoryLineMm + kStoryRowGapMm;
  return [
    for (var r = 0; r < 3; r++)
      for (var c = 0; c < 2; c++) Rect.fromLTWH(kStoryMarginMm + c * (cw + kStoryGapMm), kStoryTopMm + r * pitch, cw, fh),
  ];
}

/// Planificador diario (mm): horas de [kDailyFirstHour] a [kDailyLastHour], un tramo por hora con renglón cada media.
const int kDailyFirstHour = 7, kDailyLastHour = 22;

class DailyLayout {
  final Rect hours, priorities, notes; // columna de horas y cajas de la derecha
  final double hourH; // alto de cada hora
  const DailyLayout(this.hours, this.priorities, this.notes, this.hourH);
}

DailyLayout dailyLayoutMm(String size) {
  final w = paperWidthMm(size), h = paperHeightMm(size);
  const x0 = 12.0, y0 = 25.0, gap = 6.0, bottom = 12.0;
  final lw = (w - 2 * x0) * 2 / 3 - gap / 2, rx = x0 + lw + gap, rw = w - x0 - rx;
  final hourH = (h - y0 - bottom) / (kDailyLastHour - kDailyFirstHour + 1), th = h - y0 - bottom;
  final ph = th * 0.3;
  return DailyLayout(Rect.fromLTWH(x0, y0, lw, th), Rect.fromLTWH(rx, y0, rw, ph),
      Rect.fromLTWH(rx, y0 + ph + gap, rw, th - ph - gap), hourH);
}

/// Alturas (unidades lógicas, locales a la hoja) de los renglones del rayado.
List<double> ruleYs(double spacing, {String size = 'a4'}) {
  final first = max(1, (kTopMarginMm / spacing).round()), h = paperHeightMm(size), u = unitsPerMm(size);
  return [for (var n = first; n * spacing < h - 0.01; n++) n * spacing * u];
}

/// Alturas de las líneas horizontales de la cuadrícula / puntos, centradas en la hoja.
List<double> gridYs(double spacing, {String size = 'a4'}) {
  final o = gridOriginMm('grid', spacing, size: size), h = paperHeightMm(size), u = unitsPerMm(size);
  return [for (var n = 0; o + n * spacing <= h - o + 0.01; n++) (o + n * spacing) * u];
}

/// Posiciones x de las líneas verticales de la cuadrícula (sin los bordes de la hoja).
List<double> gridXs(double spacing, {String size = 'a4'}) =>
    [for (var n = 1; n * spacing < paperWidthMm(size) - 0.01; n++) n * spacing * unitsPerMm(size)];

/// Líneas horizontales del milimetrado: (altura en unidades, peso) cada 1 mm desde [gridOriginMm] hacia arriba y abajo.
/// Peso 2 cada 10 mm contados desde el origen, 1 cada 5, 0 el resto.
List<(double, int)> mmYs({String size = 'a4'}) {
  final o = gridOriginMm('mm', 10, size: size), h = paperHeightMm(size), u = unitsPerMm(size);
  final n0 = -o.floor(); // primera línea con y >= 0
  final out = <(double, int)>[];
  for (var n = n0; o + n <= h + 0.001; n++) {
    out.add(((o + n) * u, n % 10 == 0 ? 2 : (n % 5 == 0 ? 1 : 0)));
  }
  return out;
}

/// Líneas verticales del milimetrado (sin los bordes): (x en unidades, peso). Peso 2 cada 10 mm desde el borde izquierdo.
List<(double, int)> mmXs({String size = 'a4'}) {
  final w = paperWidthMm(size), u = unitsPerMm(size);
  return [for (var n = 1; n < w - 0.001; n++) (n * u, n % 10 == 0 ? 2 : (n % 5 == 0 ? 1 : 0))];
}

/// Punto (unidades, local a la hoja) donde se cruzan los ejes: sobre la cuadrícula, lo más cerca del centro.
(double, double) axesOrigin(double spacing, {String size = 'a4'}) {
  double nearest(List<double> l, double t) => l.reduce((a, b) => (a - t).abs() <= (b - t).abs() ? a : b);
  return (nearest(gridXs(spacing, size: size), kW / 2), nearest(gridYs(spacing, size: size), kSheetH / 2));
}

/// Alto de un renglón de texto en mm: el interlineado del rayado; en cuadrícula y puntos,
/// la cantidad de cuadritos que más se acerque a 8 mm (así cae sobre las líneas); liso, 8 mm.
double textLineMm(String bg, double spacing) => switch (bg) {
      'lined' || 'cornell' || 'todo' => spacing,
      'grid' || 'dots' || 'axes' => max(1, (kBlankLineMm / spacing).round()) * spacing,
      'mm' => 10,
      _ => kBlankLineMm,
    };

/// Alto de un renglón de texto en unidades lógicas.
double textLine(String bg, double spacing, {String size = 'a4'}) => textLineMm(bg, spacing) * unitsPerMm(size);

/// Tamaño de letra para un renglón de [line] unidades (a 8 mm queda como antes).
double fontForLine(double line) => line * kFont / kLine;

/// Un punto tipográfico (1/72 de pulgada) en unidades lógicas: 25,4/72 mm por kMm.
const kPtUnits = 25.4 / 72 * 1000 / 210;

/// Puntos -> unidades lógicas (12 pt salen de 4,23 mm reales al imprimir).
double ptToUnits(double pt) => pt * kPtUnits;

/// Los puntos equivalentes a la letra automática de un renglón de [line] unidades, redondeados a 0,5.
double autoPt(double line) => (fontForLine(line) / kPtUnits * 2).round() / 2;

/// El texto va un poco por debajo del renglón: 4 de 40 unidades en las hojas viejas.
double textInset(double line) => line * 4 / kLine;

/// Lleva la y [localY] de un texto (local a la hoja) al renglón más cercano ([floor]: al de arriba).
/// La y de un texto queda [textInset] por debajo de la línea donde se apoya.
double snapTextY(double localY, String bg, double spacing, {bool floor = false, String size = 'a4'}) {
  final line = textLine(bg, spacing, size: size), o = gridOriginMm(bg, spacing, size: size) * unitsPerMm(size), inset = textInset(line);
  final r = (localY - inset - o) / line;
  // renglones "virtuales" hacia arriba (con el mismo interlineado) mientras queden dentro de la hoja
  final minN = ((-(o + inset)) / line).ceil();
  final n = max(minN, (floor ? r.floorToDouble() : r.roundToDouble()).toInt());
  return o + n * line + inset;
}

/// Lleva [localPoint] (unidades, local a la hoja) a la intersección más cercana de la cuadrícula del fondo [bg]:
/// cuadriculado, puntos y ejes con su paso [spacing] (mm); milimetrado cada 5 mm. Otros fondos: el mismo punto.
Offset snapToGrid(Offset localPoint, String bg, double spacing, String size) {
  double nearest(List<double> l, double t) => l.reduce((a, b) => (a - t).abs() <= (b - t).abs() ? a : b);
  switch (bg) {
    case 'grid' || 'dots' || 'axes':
      return Offset(nearest(gridXs(spacing, size: size), localPoint.dx), nearest(gridYs(spacing, size: size), localPoint.dy));
    case 'mm':
      final u = unitsPerMm(size), o = gridOriginMm('mm', 10, size: size), step = 5 * u;
      final x = (localPoint.dx / step).round() * step;
      final y = (o * u) + ((localPoint.dy - o * u) / step).round() * step;
      return Offset(x.clamp(0.0, paperWidthMm(size) * u), y.clamp(0.0, paperHeightMm(size) * u));
    default:
      return localPoint;
  }
}
