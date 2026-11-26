import 'package:flutter/gestures.dart';

import '../domain/domain.dart';

// Entrada del lápiz: qué hace cada puntero y cómo se arman los puntos del trazo.

bool isStylus(PointerEvent e) => e.kind == PointerDeviceKind.stylus || e.kind == PointerDeviceKind.invertedStylus;

/// Botón del S Pen apretado, punta goma del lápiz, o clic derecho del mouse.
bool wantsEraser(PointerEvent e) =>
    e.kind == PointerDeviceKind.invertedStylus ||
    (isStylus(e) && (e.buttons & (kPrimaryStylusButton | kSecondaryStylusButton)) != 0) ||
    (e.kind == PointerDeviceKind.mouse && (e.buttons & kSecondaryMouseButton) != 0);

enum PenAction { erase, draw, select, title }

/// Qué hace un puntero que apoya en la hoja con la herramienta [tool].
/// null: nada (el dedo solo scrollea y así la palma se ignora; en modo texto el lápiz toca los campos).
PenAction? penActionFor(PointerDownEvent e, Tool tool) {
  final mouse = e.kind == PointerDeviceKind.mouse;
  // las formas también las dibuja el dedo (un dedo no scrollea con esa herramienta)
  if (!isStylus(e) && !mouse && !(tool == Tool.shape && e.kind == PointerDeviceKind.touch)) return null;
  if (mouse && e.buttons != kPrimaryMouseButton && e.buttons != kSecondaryMouseButton) return null;
  if (wantsEraser(e)) return PenAction.erase;
  return switch (tool) {
    Tool.text => null,
    Tool.select => PenAction.select,
    Tool.title => PenAction.title,
    Tool.pen || Tool.hl || Tool.paint || Tool.shape => PenAction.draw,
  };
}

/// Presión de 0 a 1. El mouse (o un lápiz que no informa rango) dibuja con presión media.
double pressureOf(PointerEvent e) {
  if (!isStylus(e)) return .5;
  final range = e.pressureMax - e.pressureMin;
  final p = range > 0 ? ((e.pressure - e.pressureMin) / range).clamp(0.0, 1.0) : .5;
  return p.isFinite ? p : .5; // un driver que manda NaN no puede arruinar el trazo
}

/// Agrega un punto al trazo en curso. Descarta los que casi no se movieron
/// y suaviza la presión para que el grosor no salte.
void appendInkPoint(Stroke s, Offset p, double pressure) {
  // un punto con coordenadas que no son números (NaN, infinito) no entra: rompería el guardado de toda la hoja
  if (!p.dx.isFinite || !p.dy.isFinite) return;
  final pts = s.pts;
  var pr = pressure.isFinite ? pressure : .5;
  if (pts.isNotEmpty) {
    final lx = pts[pts.length - 3], ly = pts[pts.length - 2];
    if ((p.dx - lx).abs() + (p.dy - ly).abs() < .6) return;
    pr = pts[pts.length - 1] * .65 + pr * .35;
  }
  pts.addAll([p.dx, p.dy, pr]);
  s.invalidate();
}

/// Trazos que toca la goma de radio [r] en [pt]. Los correctores del PDF ([kCoverTip]) no cuentan: se sacan con
/// Deshacer o seleccionándolos.
List<Stroke> strokesHit(NotebookDoc doc, Offset pt, double r) =>
    [for (final s in doc.strokes.values) if (s.k != kCoverTip && s.hitBy(pt, r)) s];
