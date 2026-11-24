import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../domain/domain.dart';

/// Máximo de vértices de un lote de trazos (índices de 16 bits y, de paso, un lote ~ un tramo de hoja que se puede
/// descartar por zona).
const kBatchVertices = 12000;

class _Native implements NativeHandle {
  final ui.Vertices v;
  _Native(this.v);
  @override
  void dispose() => v.dispose();
}

/// Lote de trazos seguidos de la misma pasada, mismo color y sin capa, dibujado con UN `drawVertices`.
/// Vive en [Stroke.batchCache] del primer trazo; se rehace si cambia cualquiera (identidad o [Stroke.meshGen]).
class _Batch implements NativeHandle {
  final List<Stroke> members;
  final List<int> gens;
  final ui.Vertices vertices;
  _Batch(this.members, this.gens, this.vertices);
  bool validFor(List<Stroke> s) {
    if (s.length != members.length) return false;
    for (var i = 0; i < s.length; i++) {
      if (!identical(s[i], members[i]) || s[i].meshGen != gens[i] || s[i].mesh == null) return false;
    }
    return true;
  }

  @override
  void dispose() => vertices.dispose();
}

ui.Vertices _verticesOf(MeshPart p) {
  final h = p.native;
  if (h is _Native) return h.v;
  final v = ui.Vertices.raw(VertexMode.triangles, p.pos, colors: p.colors, indices: p.idx);
  p.native = _Native(v);
  return v;
}

/// Pinta una lista de partes ya armadas con el color [color] (o el de los vértices si la malla es de colores).
void _drawParts(Canvas c, Iterable<MeshPart> parts, Color color, bool colored) {
  final paint = Paint()
    ..color = color
    ..isAntiAlias = true;
  for (final p in parts) {
    c.drawVertices(_verticesOf(p), colored ? BlendMode.dst : BlendMode.srcOver, paint);
  }
}

bool _layered(Stroke s) => s.o < .999 && s.k != 'pencil' && !isPaint(s.k); // lápiz y pintura llevan el alfa en los vértices

/// Relleno de una forma exacta: el polígono de sus puntos a 35 % de opacidad (por la opacidad del trazo), debajo del borde.
void _paintFill(Canvas c, Stroke s) {
  c.drawPath(s.fillPath, Paint()..color = parseColor(s.fill!).withValues(alpha: .35 * s.o));
}

/// Dibuja un trazo según su punta (ver [tips]; 'hl' es el resaltador) con su malla de triángulos
/// (un `drawVertices` por trazo). Los trazos con opacidad menor a 1 van en una capa para que no se
/// oscurezcan sus propias uniones (el lápiz lleva el alfa en los colores de los vértices).
void paintStroke(Canvas c, Stroke s) {
  final m = s.ensureMesh();
  if (m == null) return;
  if (s.fill != null) _paintFill(c, s);
  final layered = _layered(s);
  if (layered) c.saveLayer(s.bounds, Paint()..color = Color.fromRGBO(0, 0, 0, s.o));
  _drawParts(c, m.parts, s.color, m.colored);
  if (layered) c.restore();
}


/// Dibuja varios trazos: primero los resaltadores, así quedan debajo de la tinta.
/// Los trazos seguidos opacos del mismo color se juntan en lotes (un `drawVertices` por ~[kBatchVertices] vértices).
/// [cull]: si se pasa, no se dibujan los trazos ni lotes que no tocan ese rectángulo (conviene pasar siempre la
/// misma lista y recortar con esto: así los lotes no cambian de una franja a otra).
void paintStrokes(Canvas c, Iterable<Stroke> strokes, {Rect? cull}) {
  final list = strokes is List<Stroke> ? strokes : strokes.toList();
  _pass(c, list, cull, true);
  _pass(c, list, cull, false);
}

void _pass(Canvas c, List<Stroke> list, Rect? cull, bool hl) {
  var group = <Stroke>[];
  var verts = 0;
  int? key;
  void flush() {
    if (group.isNotEmpty) _drawGroup(c, group, cull);
    group = <Stroke>[];
    verts = 0;
    key = null;
  }

  for (final s in list) {
    if (isUnderInk(s.k) != hl || s.n == 0) continue;
    if (s.fill != null || _layered(s)) {
      // con relleno va solo (no entra en lotes): el relleno va antes del borde
      flush();
      if (cull == null || s.bounds.overlaps(cull)) paintStroke(c, s);
      continue;
    }
    final m = s.ensureMesh();
    if (m == null) continue;
    final k = m.colored ? 0 : s.color.toARGB32();
    if (group.isNotEmpty && (k != key || verts + m.vertexCount > kBatchVertices)) flush();
    group.add(s);
    verts += m.vertexCount;
    key = k;
  }
  flush();
}

void _drawGroup(Canvas c, List<Stroke> g, Rect? cull) {
  if (g.length == 1) {
    if (cull == null || g[0].bounds.overlaps(cull)) paintStroke(c, g[0]);
    return;
  }
  if (cull != null) {
    var r = g.first.bounds;
    for (final s in g) {
      r = r.expandToInclude(s.bounds);
    }
    if (!r.overlaps(cull)) return;
  }
  final b = _batchOf(g);
  final colored = g.first.mesh!.colored;
  c.drawVertices(b.vertices, colored ? BlendMode.dst : BlendMode.srcOver, Paint()..color = g.first.color);
}

_Batch _batchOf(List<Stroke> g) {
  final first = g.first;
  final old = first.batchCache;
  if (old is _Batch && old.validFor(g)) return old;
  old?.dispose();
  var nv = 0, ni = 0;
  final colored = first.mesh!.colored;
  for (final s in g) {
    nv += s.mesh!.vertexCount;
    for (final p in s.mesh!.parts) {
      ni += p.idx.length;
    }
  }
  final pos = Float32List(nv * 2), idx = Uint16List(ni);
  final cols = colored ? Int32List(nv) : null;
  var vo = 0, io = 0;
  for (final s in g) {
    for (final p in s.mesh!.parts) {
      pos.setRange(vo * 2, (vo + p.vertexCount) * 2, p.pos);
      cols?.setRange(vo, vo + p.vertexCount, p.colors!);
      for (var i = 0; i < p.idx.length; i++) {
        idx[io + i] = p.idx[i] + vo;
      }
      vo += p.vertexCount;
      io += p.idx.length;
    }
  }
  final v = ui.Vertices.raw(VertexMode.triangles, pos, colors: cols, indices: idx);
  final b = _Batch(List.of(g), [for (final s in g) s.meshGen], v);
  first.batchCache = b;
  return b;
}

// ---------------- el dibujo de antes (solo para los tests) ----------------


/// El dibujo de antes (un `drawLine`/`Path` por tramo). Solo para comparar en los tests con el de mallas.
@visibleForTesting
void paintStrokeLegacy(Canvas c, Stroke s) {
  if (s.n == 0) return;
  switch (s.k) {
    case 'hl':
      _pathStroke(c, s, s.color.withValues(alpha: s.o), StrokeCap.butt);
      return;
    case 'fine':
    case kCoverTip:
      _pathStroke(c, s, s.color.withValues(alpha: s.o), StrokeCap.round);
      return;
    case 'pencil':
      _pencil(c, s);
      return;
  }
  // con opacidad: se dibuja en una capa para que no se oscurezcan las uniones
  final layered = s.o < .999;
  if (layered) c.saveLayer(s.bounds, Paint()..color = Color.fromRGBO(0, 0, 0, s.o));
  if (s.k == 'calli') {
    _calli(c, s);
  } else if (s.k == 'fountain') {
    _variable(c, s, .15, 1.7, true);
  } else {
    _variable(c, s, .35, 1.3, false);
  }
  if (layered) c.restore();
}

/// trazo de grosor constante (fibra, resaltador), suavizado con curvas
void _pathStroke(Canvas c, Stroke s, Color color, StrokeCap cap) {
  final p = s.pts, n = s.n;
  final path = Path()..moveTo(p[0], p[1]);
  if (n == 1) path.lineTo(p[0] + .1, p[1]);
  for (var i = 1; i < n - 1; i++) {
    path.quadraticBezierTo(p[i * 3], p[i * 3 + 1], (p[i * 3] + p[i * 3 + 3]) / 2, (p[i * 3 + 1] + p[i * 3 + 4]) / 2);
  }
  if (n > 1) path.lineTo(p[n * 3 - 3], p[n * 3 - 2]);
  c.drawPath(
    path,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.w
      ..strokeCap = cap
      ..strokeJoin = StrokeJoin.round,
  );
}

/// grosor según presión (bolígrafo) y además según velocidad (pluma)
void _variable(Canvas c, Stroke s, double minF, double rangeF, bool speed) {
  final p = s.pts, n = s.n;
  final paint = Paint()
    ..color = s.color
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  if (n == 1) {
    c.drawCircle(Offset(p[0], p[1]), s.w * (minF + rangeF * p[2]) / 2, paint..style = PaintingStyle.fill);
    return;
  }
  double f = 1;
  for (var i = 1; i < n; i++) {
    final a = Offset(p[i * 3 - 3], p[i * 3 - 2]), b = Offset(p[i * 3], p[i * 3 + 1]);
    if (speed) {
      final target = (1.25 - (b - a).distance / (s.w * 3 + 3)).clamp(.45, 1.15);
      f = f * .7 + target * .3;
    }
    paint.strokeWidth = s.w * (minF + rangeF * p[i * 3 + 2]) * f;
    c.drawLine(a, b, paint);
  }
}

/// lápiz: más claro con poca presión, con algo de grano
void _pencil(Canvas c, Stroke s) {
  final p = s.pts, n = s.n;
  final paint = Paint()
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  final grain = Paint()
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke;
  if (n == 1) {
    c.drawCircle(Offset(p[0], p[1]), s.w * .4, paint..color = s.color.withValues(alpha: s.o * .6));
    return;
  }
  for (var i = 1; i < n; i++) {
    final pr = p[i * 3 + 2];
    final a = Offset(p[i * 3 - 3], p[i * 3 - 2]), b = Offset(p[i * 3], p[i * 3 + 1]);
    paint
      ..color = s.color.withValues(alpha: s.o * (.28 + .6 * pr))
      ..strokeWidth = s.w * (.55 + .6 * pr);
    c.drawLine(a, b, paint);
    // grano: una línea fina corrida, pseudoaleatoria pero estable
    final j = ((i * 7919) % 13 - 6) / 6 * s.w * .3;
    grain
      ..color = s.color.withValues(alpha: s.o * (.12 + .25 * pr))
      ..strokeWidth = s.w * .35;
    c.drawLine(a + Offset(j, -j), b + Offset(j, -j), grain);
  }
}

/// caligrafía: punta plana a 45°, gruesa o fina según la dirección
void _calli(Canvas c, Stroke s) {
  final p = s.pts, n = s.n;
  final fill = Paint()..color = s.color;
  final line = Paint()
    ..color = s.color
    ..strokeCap = StrokeCap.round
    ..style = PaintingStyle.stroke
    ..strokeWidth = s.w * .22;
  const dir = Offset(.7071, -.7071);
  for (var i = 0; i < n; i++) {
    final b = Offset(p[i * 3], p[i * 3 + 1]);
    final a = i == 0 ? b : Offset(p[i * 3 - 3], p[i * 3 - 2]);
    final nb = dir * (s.w * (.55 + .9 * p[i * 3 + 2]));
    final path = Path()
      ..moveTo((a + nb).dx, (a + nb).dy)
      ..lineTo((b + nb).dx, (b + nb).dy)
      ..lineTo((b - nb).dx, (b - nb).dy)
      ..lineTo((a - nb).dx, (a - nb).dy)
      ..close();
    c.drawPath(path, fill);
    c.drawLine(a, b, line);
  }
}

