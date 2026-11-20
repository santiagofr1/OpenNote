import 'dart:math';
import 'dart:ui';

import '../domain/domain.dart';

/// Espacio arriba de la primera hoja.
const kTopPad = 16.0;

/// Dónde y a qué escala se dibuja la página dentro del visor.
/// Zoom 1 = la hoja entra justa a lo ancho (con un margen chico, hasta 1100 px).
class SheetLayout {
  final double scale; // píxeles por unidad lógica
  final double sheetLeft; // dónde empieza la hoja dentro del contenido scrolleable
  final double sheetWidth, contentWidth;
  const SheetLayout._(this.scale, this.sheetLeft, this.sheetWidth, this.contentWidth);

  /// Antes del primer layout.
  static const initial = SheetLayout._(1, 0, kW, kW);

  factory SheetLayout(double viewportWidth, double zoom) {
    final side = viewportWidth < 700 ? 6.0 : 24.0;
    final fit = min(viewportWidth - side * 2, 1100.0);
    final sw = fit * zoom;
    final contentW = max(viewportWidth, sw + side * 2);
    return SheetLayout._(sw / kW, (contentW - sw) / 2, sw, contentW);
  }

  /// Punto del visor → coordenadas de la página, con el contenido scrolleado [scroll].
  Offset toPage(Offset viewportPoint, Offset scroll) => Offset(
      (scroll.dx + viewportPoint.dx - sheetLeft) / scale, (scroll.dy + viewportPoint.dy - kTopPad) / scale);

  /// Scroll que deja el punto de la página [pagePoint] debajo de [viewportPoint].
  Offset scrollFor(Offset pagePoint, Offset viewportPoint) =>
      Offset(pagePoint.dx * scale + sheetLeft - viewportPoint.dx, pagePoint.dy * scale + kTopPad - viewportPoint.dy);
}
