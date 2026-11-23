import 'dart:math';

import 'geometry.dart';

// Medidas del fondo de una hoja en milímetros reales de A4. Todo puro: lo usan el dibujo del
// papel (miniaturas, PNG, PDF y editor) y el acomodo del texto con teclado.

/// Interlineados del rayado y paso de la cuadrícula / puntos, en mm.
const kLinedSpacings = [7.0, 8.0, 10.0], kGridSpacings = [5.0, 7.0];

/// Margen rojo del rayado (desde el borde izquierdo) y altura aproximada del primer renglón, en mm.
const double kMarginMm = 25, kTopMarginMm = 25;

/// Interlineado de los textos de una hoja lisa, en mm.
const double kBlankLineMm = 8;

/// Opciones de [spacing] (mm) según el fondo; vacío si no tiene (liso).
List<double> spacingsFor(String bg) => switch (bg) {
      'lined' => kLinedSpacings,
      'grid' || 'dots' => kGridSpacings,
      _ => const [],
    };

/// Espaciado por defecto del fondo: rayado 8 mm, cuadriculado y puntos 5 mm.
double defaultSpacing(String bg) => switch (bg) {
      'grid' || 'dots' => 5,
      _ => 8,
    };

/// [spacing] si es una opción del fondo [bg]; si no, el por defecto (al cambiar de fondo).
double validSpacing(String bg, double spacing) => spacingsFor(bg).contains(spacing) ? spacing : defaultSpacing(bg);

/// Cantidad de milímetros como texto corto ("8", "7.5").
String fmtMm(double mm) => mm == mm.roundToDouble() ? mm.round().toString() : mm.toString();

/// Altura (mm, desde el borde de arriba de la hoja) de la primera línea horizontal del fondo.
/// Rayado: múltiplo del interlineado cercano a 25 mm. Cuadriculado y puntos: centrada, sobra lo mismo arriba y abajo.
double gridOriginMm(String bg, double spacing) => switch (bg) {
      'grid' || 'dots' => (kA4HeightMm % spacing) / 2,
      _ => 0,
    };

/// Alturas (unidades lógicas, locales a la hoja) de los renglones del rayado.
List<double> ruleYs(double spacing) {
  final first = max(1, (kTopMarginMm / spacing).round());
  return [for (var n = first; n * spacing < kA4HeightMm - 0.01; n++) mmToUnits(n * spacing)];
}

/// Alturas de las líneas horizontales de la cuadrícula / puntos, centradas en la hoja.
List<double> gridYs(double spacing) {
  final o = gridOriginMm('grid', spacing);
  return [for (var n = 0; o + n * spacing <= kA4HeightMm - o + 0.01; n++) mmToUnits(o + n * spacing)];
}

/// Posiciones x de las líneas verticales de la cuadrícula (sin los bordes de la hoja).
List<double> gridXs(double spacing) => [for (var n = 1; n * spacing < kA4WidthMm - 0.01; n++) mmToUnits(n * spacing)];

/// Alto de un renglón de texto en mm: el interlineado del rayado; en cuadrícula y puntos,
/// la cantidad de cuadritos que más se acerque a 8 mm (así cae sobre las líneas); liso, 8 mm.
double textLineMm(String bg, double spacing) => switch (bg) {
      'lined' => spacing,
      'grid' || 'dots' => max(1, (kBlankLineMm / spacing).round()) * spacing,
      _ => kBlankLineMm,
    };

/// Alto de un renglón de texto en unidades lógicas.
double textLine(String bg, double spacing) => mmToUnits(textLineMm(bg, spacing));

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
double snapTextY(double localY, String bg, double spacing, {bool floor = false}) {
  final line = textLine(bg, spacing), o = mmToUnits(gridOriginMm(bg, spacing)), inset = textInset(line);
  final r = (localY - inset - o) / line;
  // renglones "virtuales" hacia arriba (con el mismo interlineado) mientras queden dentro de la hoja
  final minN = ((-(o + inset)) / line).ceil();
  final n = max(minN, (floor ? r.floorToDouble() : r.roundToDouble()).toInt());
  return o + n * line + inset;
}
