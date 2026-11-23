import 'dart:ui';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle, TextDirection, FontWeight;

import '../domain/domain.dart';
import '../rendering/ink_layers.dart';
import '../rendering/stroke_painter.dart';
import '../rendering/text_layout.dart';
import '../theme/colors.dart';
import 'selection.dart';

/// Capa "en vivo", en coordenadas de la página: trazo en curso, goma, rectángulo de selección
/// y los trazos seleccionados mientras se arrastran (en la capa fija quedan ocultos).
void paintLiveLayer(
  Canvas c, {
  required NotebookDoc doc,
  required double scale,
  required Selection sel,
  Stroke? live,
  Offset? eraserAt,
  double eraserRadius = 0,
  Rect? visible, // zona que se ve (más margen): los trazos arrastrados de afuera no se dibujan
  List<OutlineEntry>? outline, // el índice, para marcar cada título con su número (con cualquier herramienta)
}) {
  if (live != null) paintStroke(c, live);
  if (eraserAt != null) {
    c.drawCircle(
      eraserAt,
      eraserRadius,
      Paint()
        ..color = kMuted
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 / scale,
    );
  }
  final border = Paint()
    ..color = kAccent
    ..strokeWidth = 1.5 / scale;
  final band = sel.band;
  if (band != null) {
    if (sel.capture && !sel.titleBand) {
      // captura (derecha a izquierda): punteado y verde
      final green = Paint()
        ..color = kCapture
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 / scale;
      c.drawRect(band, Paint()..color = const Color(0x1A2E9E5B));
      dashedRect(c, band, green, 6 / scale);
    } else {
      // ventana (izquierda a derecha, o la de la herramienta Título): línea continua y azul
      c.drawRect(band, Paint()..color = const Color(0x142F5BD3));
      c.drawRect(
          band,
          Paint()
            ..color = kAccent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 / scale);
    }
  }
  if (outline != null) _paintHeadingMarks(c, doc, scale, outline, visible);
  final drag = sel.drag;
  final xf = drag?.xf ?? const Xform();
  // transforma el lienzo como la selección: mover, escalar y rotar alrededor del pivote
  void withXform(void Function() draw) {
    c.save();
    c.translate(xf.pivot.dx + xf.shift.dx, xf.pivot.dy + xf.shift.dy);
    c.rotate(xf.angle);
    c.scale(xf.scale * xf.kx, xf.scale * xf.ky);
    c.translate(-xf.pivot.dx, -xf.pivot.dy);
    draw();
    c.restore();
  }

  if (drag != null) {
    withXform(() {
      for (final s in sel.strokesOf(doc)) {
        if (visible != null && !xf.applyRect(s.bounds).overlaps(visible)) continue;
        paintStroke(c, s);
      }
    });
  }
  final r = sel.bounds(doc);
  if (r != null) {
    withXform(() {
      c.drawRect(r, Paint()..color = const Color(0x0F2F5BD3));
      dashedRect(c, r, border..strokeWidth = 1.5 / scale / xf.scale, 6 / scale / xf.scale);
    });
  }
}

/// Posición de la pastilla con el número: a la izquierda de la barra, alineada con la primera línea de lo marcado;
/// si se sale de la hoja (x < 0), arriba de lo marcado alineada con la barra.
@visibleForTesting
Rect headingPillRect(Rect r, Size pill, double scale) {
  final cy = r.top + (r.height < 40 ? r.height : 40) / 2;
  final left = r.left - 10 / scale - 6 / scale - pill.width;
  if (left >= 2 / scale) return Rect.fromLTWH(left, cy - pill.height / 2, pill.width, pill.height);
  return Rect.fromLTWH(r.left - 10 / scale, r.top - 6 / scale - pill.height, pill.width, pill.height);
}

/// Ubica las pastillas (mismo orden que [items]): posición inicial con [headingPillRect]; se procesan ordenadas por
/// (hoja, top); si una se superpone con la anterior ya ubicada de su hoja (con 3/scale de separación) baja debajo de
/// ella, y al final queda entera dentro de su hoja.
@visibleForTesting
List<Rect> layoutHeadingPills(List<({Rect r, Size pill, double sheetTop, double sheetBottom})> items, double scale) {
  final order = List<int>.generate(items.length, (i) => i)
    ..sort((a, b) {
      final c = items[a].sheetTop.compareTo(items[b].sheetTop);
      return c != 0 ? c : items[a].r.top.compareTo(items[b].r.top);
    });
  final out = List<Rect>.filled(items.length, Rect.zero);
  final gap = 3 / scale, pad = 4 / scale;
  Rect? prev;
  double? prevSheet;
  for (final i in order) {
    final it = items[i];
    var pr = headingPillRect(it.r, it.pill, scale);
    if (prev != null && prevSheet == it.sheetTop && pr.inflate(gap / 2).overlaps(prev.inflate(gap / 2))) {
      pr = pr.shift(Offset(0, prev.bottom + gap - pr.top));
    }
    final lo = it.sheetTop + pad, hi = it.sheetBottom - pad - pr.height;
    final top = hi < lo ? lo : pr.top.clamp(lo, hi).toDouble();
    pr = pr.shift(Offset(0, top - pr.top));
    out[i] = pr;
    prev = pr;
    prevSheet = it.sheetTop;
  }
  return out;
}

/// Marca cada título de las hojas cargadas que se ven: fondo suave, barra lateral y pastilla con su número del índice.
final _pillTexts = <(String, int, int), TextPainter>{};

/// TextPainter del número de la pastilla, cacheado: la capa en vivo se repinta en cada movimiento del lápiz.
TextPainter _pillText(String number, int level, double fontSize) {
  final key = (number, level, (fontSize * 100).round());
  final hit = _pillTexts[key];
  if (hit != null) return hit;
  if (_pillTexts.length >= 64) _pillTexts.clear();
  return _pillTexts[key] = TextPainter(
    text: TextSpan(
        text: number,
        style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFFFFFFF),
            fontFeatures: const [FontFeature.tabularFigures()],
            height: 1)),
    textDirection: TextDirection.ltr,
  )..layout();
}

void _paintHeadingMarks(Canvas c, NotebookDoc doc, double scale, List<OutlineEntry> outline, Rect? visible) {
  final act = doc.nb.activeSection.id;
  final marks = <({OutlineEntry e, Rect r, Size pill, TextPainter tp, double sheetTop, double sheetBottom})>[];
  for (final e in outline) {
    if (e.sectionId != act || e.sheet >= doc.sheets.length || !doc.isLoadedAt(e.sheet)) continue;
    final h = doc.sheets[e.sheet].heads.where((x) => x.id == e.headingId).firstOrNull;
    if (h == null) continue;
    final r0 = headingBounds(doc, h, (t) => textBounds(t, doc.lineAt(t.y)));
    if (r0 == null) continue;
    final sheetTop = e.sheet * kSheetStep, sheetBottom = sheetTop + kSheetH;
    final r = r0.intersect(Rect.fromLTRB(-1e6, sheetTop, 1e6, sheetBottom));
    if (r.isEmpty) continue;
    final reach = Rect.fromLTRB(r.left - 80 / scale, r.top - 30 / scale, r.right, r.bottom);
    if (visible != null && !reach.overlaps(visible)) continue;
    final tp = _pillText(e.number, e.level, 11 / scale);
    marks.add((e: e, r: r, pill: Size(tp.width + 12 / scale, tp.height + 6 / scale), tp: tp, sheetTop: sheetTop, sheetBottom: sheetBottom));
  }
  final pills = layoutHeadingPills([for (final m in marks) (r: m.r, pill: m.pill, sheetTop: m.sheetTop, sheetBottom: m.sheetBottom)], scale);
  for (var i = 0; i < marks.length; i++) {
    final m = marks[i], e = m.e, r = m.r, pr = pills[i];
    c.drawRRect(
        RRect.fromRectAndRadius(r.inflate(5 / scale), Radius.circular(8 / scale)), Paint()..color = kAccent.withValues(alpha: .07));
    final bar = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (e.level == 1 ? 3.5 : (e.level == 2 ? 2.5 : 2)) / scale
      ..color = kAccent.withValues(alpha: e.level >= 3 ? .6 : .85);
    final bx = r.left - 10 / scale;
    c.drawLine(Offset(bx, r.top - 2 / scale), Offset(bx, r.bottom + 2 / scale), bar);
    final pill = RRect.fromRectAndRadius(pr, Radius.circular(pr.height / 2));
    c.drawRRect(
        pill.shift(Offset(0, 1 / scale)), Paint()..color = const Color(0x22000000)..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 / scale));
    c.drawRRect(pill, Paint()..color = kAccent.withValues(alpha: e.level == 1 ? 1 : .85));
    m.tp.paint(c, Offset(pr.left + 6 / scale, pr.top + 3 / scale));
  }
}
