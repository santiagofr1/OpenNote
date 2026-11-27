import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../data/export_raster.dart';
import '../domain/mind_map.dart';

/// Colores de las ramas (suaves pero con contraste contra el texto blanco), en orden; la rama n usa el n % largo.
const kMindMapPalette = <Color>[
  Color(0xFF3F7CAC),
  Color(0xFFD1603D),
  Color(0xFF3E9A6E),
  Color(0xFF8A5CB8),
  Color(0xFFC79A1E),
  Color(0xFFD14F7F),
  Color(0xFF2E9AA6),
  Color(0xFF6C7A3B),
];
const _rootColor = Color(0xFF2F3E7E);
const _ink = Color(0xFF232B33);
const _maxTextWidth = 260.0;
const _margin = 48.0;

Color mindMapBranchColor(int branch) => kMindMapPalette[branch < 0 ? 0 : branch % kMindMapPalette.length];

TextStyle _style(int depth, String? family) {
  final (size, weight, color) = switch (depth) {
    0 => (24.0, FontWeight.w700, const Color(0xFFFFFFFF)),
    1 => (18.0, FontWeight.w700, _ink),
    2 => (16.0, FontWeight.w600, _ink),
    _ => (14.5, FontWeight.w400, _ink),
  };
  return TextStyle(fontFamily: family, fontSize: size, fontWeight: weight, color: color, height: 1.2);
}

TextPainter _layoutText(String text, int depth, String? family, Color? color) {
  final st = _style(depth, family);
  return TextPainter(
    text: TextSpan(text: text, style: color == null ? st : st.copyWith(color: color)),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
    maxLines: 2,
    ellipsis: '…',
  )..layout(maxWidth: _maxTextWidth);
}

EdgeInsets _pad(int depth) => switch (depth) {
      0 => const EdgeInsets.symmetric(horizontal: 30, vertical: 18),
      1 => const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
      _ => const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    };

/// Tamaño de un nodo según su texto (hasta 2 líneas de [_maxTextWidth] de ancho, con "…").
Size measureMindNode(String text, int depth, {String? fontFamily}) {
  final tp = _layoutText(text, depth, fontFamily, null);
  final p = _pad(depth);
  final s = Size(tp.width + p.horizontal, tp.height + p.vertical);
  tp.dispose();
  return s;
}

/// Acomoda [root] con las medidas del dibujo.
MindMap layoutMindMapForPaint(MindNode root, {String? fontFamily}) =>
    layoutMindMap(root, (t, d) => measureMindNode(t, d, fontFamily: fontFamily), hGap: 46, vGap: 10);

/// Pinta el mapa (sin fondo ni margen) en [c], con las coordenadas del propio mapa.
void paintMindMap(ui.Canvas c, MindMap map, {String? fontFamily}) {
  // aristas: curvas suaves del color de la rama, más gruesas cerca de la raíz
  for (final e in map.edges) {
    final to = e.to, from = e.from;
    final right = to.side >= 0;
    final a = Offset(right ? from.rect.right : from.rect.left, from.rect.center.dy);
    final b = Offset(right ? to.rect.left : to.rect.right, to.rect.center.dy);
    final dx = (b.dx - a.dx) * .55;
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..cubicTo(a.dx + dx, a.dy, b.dx - dx, b.dy, b.dx, b.dy);
    c.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = switch (to.depth) { 1 => 5.0, 2 => 3.2, _ => 2.2 }
          ..color = mindMapBranchColor(to.branch).withValues(alpha: to.depth <= 2 ? .9 : .75)
          ..isAntiAlias = true);
  }
  for (final n in map.nodes) {
    final r = n.rect;
    final col = n.kind == MindKind.root ? _rootColor : mindMapBranchColor(n.branch);
    final rr = RRect.fromRectAndRadius(r, Radius.circular(n.kind == MindKind.heading ? 10 : r.height / 2));
    final fill = Paint()..isAntiAlias = true;
    Color? text;
    switch (n.kind) {
      case MindKind.root || MindKind.section:
        c.drawRRect(rr.shift(const Offset(0, 2)), Paint()..color = const Color(0x22000000)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
        c.drawRRect(rr, fill..color = col);
        text = const Color(0xFFFFFFFF);
      case MindKind.heading:
        c.drawRRect(rr, fill..color = col.withValues(alpha: .13));
        c.drawLine(
            Offset(r.left + 10, r.bottom - 1.5),
            Offset(r.right - 10, r.bottom - 1.5),
            Paint()
              ..color = col
              ..strokeWidth = 2.4
              ..strokeCap = StrokeCap.round
              ..isAntiAlias = true);
    }
    final tp = _layoutText(n.text, n.depth, fontFamily, text);
    tp.paint(c, Offset(r.left + (r.width - tp.width) / 2, r.top + (r.height - tp.height) / 2));
    tp.dispose();
  }
}

/// Tamaño en píxeles del PNG de un mapa de [bounds] y la escala usada: [pixelRatio] (2-3), reducida si algún lado pasaría
/// de [maxSide].
({int w, int h, double ratio}) mindMapRaster(ui.Rect bounds, double pixelRatio, {int maxSide = 8000}) {
  final w = bounds.width + 2 * _margin, h = bounds.height + 2 * _margin;
  final ratio = math.min(pixelRatio, maxSide / math.max(w, h));
  return (w: math.max(1, (w * ratio).round()), h: math.max(1, (h * ratio).round()), ratio: ratio);
}

/// El mapa de [root] como PNG: fondo blanco, margen alrededor y nitidez según [pixelRatio] (con tope de [maxSide] px).
Future<Uint8List> renderMindMapPng(MindNode root, {double pixelRatio = 3, String? fontFamily, int maxSide = 8000}) async {
  final map = layoutMindMapForPaint(root, fontFamily: fontFamily);
  final r = mindMapRaster(map.bounds, pixelRatio, maxSide: maxSide);
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.scale(r.ratio);
  c.drawRect(ui.Rect.fromLTWH(0, 0, r.w / r.ratio + 1, r.h / r.ratio + 1), Paint()..color = const Color(0xFFFFFFFF));
  c.translate(_margin - map.bounds.left, _margin - map.bounds.top);
  paintMindMap(c, map, fontFamily: fontFamily);
  return opaquePng(await rasterizeStable(rec.endRecording(), r.w, r.h), r.w, r.h);
}
