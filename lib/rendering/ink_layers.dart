import 'dart:developer' as developer;
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../domain/domain.dart';
import 'sheet_image_cache.dart';
import 'stroke_painter.dart';

/// Una tanda de trazos seguidos en el orden de dibujo (ver [ZRun]) DE UNA HOJA. Se repinta solo cuando cambia
/// [version] (la de esa hoja) o la lista de trazos; el resto del tiempo queda en caché. Cada tanda es su propia
/// capa del tamaño de la hoja: una hoja normal tiene una sola (toda su tinta), y se parte en más solo si hay
/// una imagen, nota o texto en el medio del orden.
/// [sheet]: rectángulo de la hoja en la tira (coordenadas globales); la tinta se recorta a él, así un trazo
/// que cruza de una hoja a la otra se ve en las dos.
/// [hidden]: trazos que no se dibujan acá (los que se están moviendo).
/// Si hay [cache], una tanda quieta se dibuja como imagen (ver [SheetImageCache]).
/// Los trazos borrados desde que se armó la lista se saltean (se mira [doc]), así borrar con la goma
/// repinta sin rearmar los widgets.
class InkPainter extends CustomPainter {
  final NotebookDoc doc;
  final List<Stroke> strokes;
  final Rect sheet;
  final double scale;
  final ValueNotifier<int> version;
  final Set<String> Function() hidden;

  /// Caché de imagen (ver [SheetImageCache]): [cacheKey] / [sheetId] dicen qué tanda es. [dpr] pasa de unidades
  /// lógicas a píxeles; [maxPx] es el ancho máximo en píxeles que se cachea (más zoom que eso va vectorial).
  final SheetImageCache? cache;
  final String cacheKey, sheetId;
  final double dpr, maxPx;
  final InkImage? _img;
  int? _points;
  int? _stripN;

  InkPainter(this.doc, this.strokes, this.sheet, this.scale, this.version, this.hidden,
      {this.cache, this.cacheKey = '', this.sheetId = '', this.dpr = 1, this.maxPx = 4096})
      : _img = cache?.entry(cacheKey, sheetId),
        super(repaint: cache == null ? version : Listenable.merge([version, cache.entry(cacheKey, sheetId)]));

  /// Trazos vivos de la tanda (los borrados desde que se armó la lista se saltean).
  Iterable<Stroke> _alive(Set<String> skip) => strokes.where((s) => identical(doc.strokes[s.id], s) && !skip.contains(s.id));

  @override
  void paint(Canvas c, Size size) {
    developer.Timeline.startSync('ON InkPainter.paint');
    try {
      _paint(c, size);
    } finally {
      // el modo con el que terminó de pintar queda como evento instantáneo dentro del paint
      developer.Timeline.instantSync('ON InkPainter modo', arguments: {'modo': _img?.mode.name ?? 'sin-cache'});
      developer.Timeline.finishSync();
    }
  }

  void _paint(Canvas c, Size size) {
    final skip = hidden();
    final img = _img;
    Path? onlyVector; // zona (en coordenadas de la capa) que falta dibujar trazo por trazo; null: toda la capa
    if (img != null && cache != null) {
      final w = (size.width * dpr).round(), h = (size.height * dpr).round();
      _points ??= strokes.fold<int>(0, (a, s) => a + s.n);
      _stripN ??= cache!.stripCount ??
          SheetImageCache.stripCountFor(strokes, sheet,
              maxPoints: cache!.maxPointsPerStrip, min: cache!.minStrips, max: cache!.maxStrips);
      img.cacheable = _points! >= cache!.minPoints;
      // con trazos arrastrándose (ocultos), muy ampliada o con poca tinta: vectorial y sin imagen
      if (skip.isNotEmpty || w > maxPx || !img.cacheable) {
        img.invalidate();
        img.mode = img.cacheable ? InkPaintMode.vector : InkPaintMode.small;
      } else {
        if (img.hasImage && !InkImage.sameStrokes(img.imageStrokes, strokes)) img.invalidate();
        img.want(w, h);
        final first = img.record == null;
        img.record = recordStrip;
        img.recStrokes = strokes;
        if (first) cache!.kick(); // si la hoja es de las del prefetch, ya hay con qué generarla
        img.blocked = false;
        img.stripN = _stripN!;
        img.ensureStrips();
        cache!.touch(img);
        final n = img.strips.length;
        // cada franja lista va como imagen (si el zoom cambió se estira la vieja hasta que se regenere)
        final missing = <int>[];
        for (var i = 0; i < n; i++) {
          final s = img.strips[i];
          if (s == null) {
            missing.add(i);
            continue;
          }
          final (y0, y1) = SheetImageCache.stripRange(s.fullH, n, i);
          c.drawImageRect(s.image, Rect.fromLTWH(0, 0, s.image.width.toDouble(), s.image.height.toDouble()),
              Rect.fromLTRB(0, size.height * y0 / s.fullH, size.width, size.height * y1 / s.fullH),
              Paint()..filterQuality = FilterQuality.low);
        }
        img.schedule();
        // hoja que todavía no se ve y sin imagen ni miniatura: no se dibuja nada (el prefetch la genera y al pasar a
        // visible se repinta). Sin hojas visibles conocidas (primer cuadro) se dibuja como siempre.
        if (missing.length == n && img.low == null && cache!.visibleSheets.isNotEmpty && !cache!.visibleSheets.contains(sheetId)) {
          img.mode = InkPaintMode.skipped;
          return;
        }
        if (missing.isEmpty) {
          img.mode = InkPaintMode.image;
          return;
        }
        final low = img.low;
        if (low != null) {
          // sustituto barato: la miniatura estirada en lo que falta
          for (final i in missing) {
            final (y0, y1) = SheetImageCache.stripRange(h, n, i);
            final (l0, l1) = SheetImageCache.stripRange(low.height, n, i);
            c.drawImageRect(low, Rect.fromLTRB(0, l0.toDouble(), low.width.toDouble(), l1.toDouble()),
                Rect.fromLTRB(0, size.height * y0 / h, size.width, size.height * y1 / h),
                Paint()..filterQuality = FilterQuality.medium);
          }
          img.mode = InkPaintMode.lowRes;
          return;
        }
        img.mode = InkPaintMode.vector;
        if (missing.length < n) {
          onlyVector = Path();
          for (final i in missing) {
            final (y0, y1) = SheetImageCache.stripRange(h, n, i);
            onlyVector.addRect(Rect.fromLTRB(0, size.height * y0 / h, size.width, size.height * y1 / h));
          }
        }
      }
    }
    if (onlyVector != null) c.clipPath(onlyVector);
    c.scale(scale);
    c.translate(0, -sheet.top);
    c.clipRect(sheet);
    paintStrokes(c, _alive(skip));
  }

  /// Graba las filas [y0, y1) de la tanda de la hoja a [w] x [h] píxeles (para una franja de la imagen; toda la
  /// hoja es y0 = 0, y1 = h). Solo se dibujan los trazos que tocan esas filas. null si hay trazos ocultos.
  @visibleForTesting
  ui.Picture? recordStrip(int w, int h, int y0, int y1, {int step = 1}) {
    final skip = hidden();
    if (skip.isNotEmpty) return null;
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.translate(0, -y0.toDouble());
    c.scale(w / sheet.width, h / sheet.height);
    c.translate(0, -sheet.top);
    c.clipRect(sheet);
    Iterable<Stroke> ss = _alive(skip);
    if (y1 - y0 < h) {
      // trazos que tocan la franja (con margen por el grosor); la franja se recorta sola al hacer la imagen
      const margin = 60.0;
      final top = sheet.top + y0 * sheet.height / h - margin, bottom = sheet.top + y1 * sheet.height / h + margin;
      ss = ss.where((s) => s.bounds.bottom >= top && s.bounds.top <= bottom);
    }
    if (step > 1) ss = ss.map((s) => _thinned(s, step));
    paintStrokes(c, ss);
    return rec.endRecording();
  }

  /// Copia del trazo con 1 de cada [k] puntos (siempre el primero y el último): para la miniatura, que se ve chica.
  static Stroke _thinned(Stroke s, int k) {
    final n = s.n;
    if (n <= k + 1) return s;
    final p = <double>[];
    for (var i = 0; i < n; i += k) {
      p.addAll([s.pts[i * 3], s.pts[i * 3 + 1], s.pts[i * 3 + 2]]);
    }
    if ((n - 1) % k != 0) p.addAll([s.pts[(n - 1) * 3], s.pts[(n - 1) * 3 + 1], s.pts[(n - 1) * 3 + 2]]);
    return Stroke(s.id, s.k, s.c, s.w, p, s.o)..z = s.z;
  }

  @override
  bool shouldRepaint(InkPainter o) =>
      o.doc != doc || o.scale != scale || o.sheet != sheet || o.dpr != dpr || !InkImage.sameStrokes(o.strokes, strokes);
}

/// Capa de lo que pasa "ahora": trazo en curso, goma, selección.
class LivePainter extends CustomPainter {
  final void Function(Canvas) draw;
  final double scale;
  LivePainter(this.draw, this.scale, Listenable tick) : super(repaint: tick);

  @override
  void paint(Canvas c, Size size) {
    c.scale(scale);
    draw(c);
  }

  @override
  bool shouldRepaint(LivePainter o) => o.scale != scale;
}

/// Rectángulo punteado
void dashedRect(Canvas c, Rect r, Paint p, double dash) {
  void line(Offset a, Offset b) {
    final len = (b - a).distance, dir = (b - a) / len;
    for (double d = 0; d < len; d += dash * 2) {
      c.drawLine(a + dir * d, a + dir * min(d + dash, len), p);
    }
  }

  line(r.topLeft, r.topRight);
  line(r.topRight, r.bottomRight);
  line(r.bottomRight, r.bottomLeft);
  line(r.bottomLeft, r.topLeft);
}
