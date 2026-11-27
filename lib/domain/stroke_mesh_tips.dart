part of 'stroke_mesh.dart';

// Puntas "de efecto" del lápiz: punteado, discontinuo, tiza, rotulador biselado, neón y doble línea.
//
// Pensadas para dibujarse en vivo (el trazo se re-malla en cada punto): todo lo que se reparte a lo largo del trazo
// (puntos, guiones) se ancla al largo de arco desde el inicio y todo lo "azaroso" sale de [_rnd] (hash de índices),
// nunca de un Random. Así lo ya dibujado no se mueve cuando el trazo crece; solo cambia la punta final.

/// Puntas que llevan el alfa en los colores de los vértices (no van en capa con opacidad ni se juntan por color).
bool tipHasVertexAlpha(String k) => const {'pencil', 'chalk', 'neon', 'dotted', 'dashed'}.contains(k);

/// Cuánto se aleja la tinta de la línea central, en múltiplos del grosor (para el rectángulo del trazo y la goma).
double tipReach(String k) => switch (k) {
      'neon' => 2.0,
      'double' => .85,
      'chisel' => 1.2,
      _ => .5,
    };

/// Vértices de la línea suave por tramo de entrada, a lo sumo (el `_smoothCenterline` común llega a 8): acota la malla.
const _tipSteps = 3;

/// Línea central suave de una parte, sin puntos repetidos, con el largo de arco acumulado.
class _Line {
  final List<double> x, y, ra;
  _Line(this.x, this.y, this.ra);
  int get count => x.length;
  double get length => ra.last;
}

double _hyp(double dx, double dy) => sqrt(dx * dx + dy * dy);

/// Línea central de los puntos [a], [b) (la misma curva que `fine`). [minStep] ralea los vértices: se queda con uno
/// cada tanto (de adelante hacia atrás, así lo ya decidido no cambia al crecer el trazo; solo el último se corre).
_Line _lineOf(Stroke s, int a, int b, {double minStep = 0}) {
  final p = s.pts;
  final raw = <double>[
    for (var i = a; i < b; i++) ...[p[i * 3], p[i * 3 + 1]]
  ];
  final xs = <double>[], ys = <double>[];
  _smoothCenterline(raw, xs, ys, maxSteps: _tipSteps);
  final m = max(minStep, .02);
  final lx = <double>[xs[0]], ly = <double>[ys[0]], ra = <double>[0];
  for (var i = 1; i < xs.length; i++) {
    final d = _hyp(xs[i] - lx.last, ys[i] - ly.last);
    final last = i == xs.length - 1;
    if (d >= m) {
      ra.add(ra.last + d);
      lx.add(xs[i]);
      ly.add(ys[i]);
    } else if (last) {
      if (lx.length > 1) {
        // el final cae cerca del último vértice: lo reemplaza (si no quedan encimados)
        final d0 = _hyp(xs[i] - lx[lx.length - 2], ys[i] - ly[ly.length - 2]);
        if (d0 >= .02) {
          lx[lx.length - 1] = xs[i];
          ly[ly.length - 1] = ys[i];
          ra[ra.length - 1] = ra[ra.length - 2] + d0;
        }
      } else if (d >= .02) {
        ra.add(d);
        lx.add(xs[i]);
        ly.add(ys[i]);
      }
    }
  }
  return _Line(lx, ly, ra);
}

/// Largo de arco de la línea central de los puntos [0], [a] (donde empieza la parte que arranca en [a]): ancla los
/// puntos y guiones de las partes de un trazo larguísimo al mismo ritmo.
double _arcBefore(Stroke s, int a) => a <= 0 ? 0.0 : _lineOf(s, 0, a + 1).length;

/// Punto, tangente (unitaria) y tramo de la línea a [u] de arco.
(double, double, double, double, int) _lineAt(_Line l, double u) {
  var lo = 1, hi = l.count - 1;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (l.ra[mid] < u) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  final seg = l.ra[lo] - l.ra[lo - 1];
  final t = seg <= 0 ? 0.0 : ((u - l.ra[lo - 1]) / seg).clamp(0.0, 1.0);
  final dx = l.x[lo] - l.x[lo - 1], dy = l.y[lo] - l.y[lo - 1], dl = max(_hyp(dx, dy), 1e-9);
  return (l.x[lo - 1] + dx * t, l.y[lo - 1] + dy * t, dx / dl, dy / dl, lo);
}

int _argbOf(double al, int rgb) => (al.clamp(0.0, 1.0) * 255).round() << 24 | (rgb & 0x00FFFFFF);

/// Normales (izquierda de la tangente) y curvatura con signo de la línea (>0: gira hacia la normal), para correr
/// copias paralelas sin pliegues.
class _Frames {
  final List<double> nx, ny, kap;
  _Frames(this.nx, this.ny, this.kap);

  factory _Frames.of(_Line l) {
    final m = l.count;
    final dx = List<double>.filled(m - 1, 0), dy = List<double>.filled(m - 1, 0), dl = List<double>.filled(m - 1, 1);
    for (var i = 0; i < m - 1; i++) {
      dl[i] = max(_hyp(l.x[i + 1] - l.x[i], l.y[i + 1] - l.y[i]), 1e-9);
      dx[i] = (l.x[i + 1] - l.x[i]) / dl[i];
      dy[i] = (l.y[i + 1] - l.y[i]) / dl[i];
    }
    final nx = List<double>.filled(m, 0), ny = List<double>.filled(m, 1), kap = List<double>.filled(m, 0);
    for (var i = 0; i < m; i++) {
      var tx = i == 0 ? dx[0] : (i == m - 1 ? dx[m - 2] : dx[i - 1] + dx[i]);
      var ty = i == 0 ? dy[0] : (i == m - 1 ? dy[m - 2] : dy[i - 1] + dy[i]);
      var tl = _hyp(tx, ty);
      if (tl < 1e-6) {
        tx = dx[min(i, m - 2)];
        ty = dy[min(i, m - 2)];
        tl = 1;
      }
      nx[i] = -ty / tl;
      ny[i] = tx / tl;
    }
    final raw = List<double>.filled(m, 0);
    for (var i = 1; i < m - 1; i++) {
      raw[i] = (dx[i - 1] * dy[i] - dy[i - 1] * dx[i]) / ((dl[i - 1] + dl[i]) / 2);
    }
    for (var i = 1; i < m - 1; i++) {
      kap[i] = (raw[i - 1] + raw[i] * 2 + raw[i + 1]) / 4;
    }
    return _Frames(nx, ny, kap);
  }

  /// Corrimiento [off] sobre la normal en el vértice [i], sin pasar del radio de curvatura del lado interno.
  double off(int i, double off) {
    final k = kap[i];
    if (off * k > 0) {
      final lim = .85 / k.abs();
      if (off.abs() > lim) return off.sign * lim;
    }
    return off;
  }
}

/// Copia de la línea [l] corrida [off] por la normal (con [jitter] opcional por vértice, en la misma unidad).
(List<double>, List<double>) _offsetLine(_Line l, _Frames f, double off, {double Function(int i)? jitter}) {
  final xs = <double>[], ys = <double>[];
  for (var i = 0; i < l.count; i++) {
    final o = f.off(i, off + (jitter == null ? 0 : jitter(i)));
    xs.add(l.x[i] + f.nx[i] * o);
    ys.add(l.y[i] + f.ny[i] * o);
  }
  return (xs, ys);
}

/// Tramo [u0], [u1] de la línea: los extremos interpolados y los vértices de en medio.
(List<double>, List<double>) _subLine(_Line l, double u0, double u1) {
  final xs = <double>[], ys = <double>[];
  final (x0, y0, _, _, i0) = _lineAt(l, u0);
  final (x1, y1, _, _, _) = _lineAt(l, u1);
  xs.add(x0);
  ys.add(y0);
  for (var i = i0; i < l.count && l.ra[i] < u1; i++) {
    if (l.ra[i] > u0) {
      xs.add(l.x[i]);
      ys.add(l.y[i]);
    }
  }
  xs.add(x1);
  ys.add(y1);
  return (xs, ys);
}

/// Un punto: círculo de radio [r] (si no hay línea de dónde sacar la dirección).
MeshPart _dotPart(Stroke s, double x, double y, double r, int col, double feather) {
  final w = _W(true);
  _circle(w, x, y, r, col, 12, feather: feather);
  return w.done();
}

// ---------------- punteado ----------------

const _dotSteps = 10;
const _dotMaxVertices = 1 + 2 * _dotSteps; // con borde difuminado

/// Puntos redondos de diámetro ~el grosor, uno cada 2.2 grosores de arco. Con a lo sumo 2 por tramo de entrada (el
/// paso crece solo en trazos con tramos larguísimos): la cota de vértices vale siempre.
MeshPart _dottedPart(Stroke s, int a, int b, double feather) {
  final p = s.pts, r = max(s.w / 2, .2);
  final col = _argbOf(s.o, s.color.toARGB32());
  if (b - a < 2) return _dotPart(s, p[a * 3], p[a * 3 + 1], r, col, feather);
  final l = _lineOf(s, a, b);
  if (l.count < 2) return _dotPart(s, l.x[0], l.y[0], r, col, feather);
  final w = _W(true);
  final pitch = max(s.w * 2.2, l.length / (2 * (b - a - 1)));
  final pre = _arcBefore(s, a);
  for (var k = (pre / pitch).ceil(); k * pitch - pre <= l.length + 1e-9; k++) {
    final (x, y, _, _, _) = _lineAt(l, max(k * pitch - pre, 0));
    _circle(w, x, y, r, col, _dotSteps, feather: feather);
  }
  return w.done();
}

// ---------------- discontinuo ----------------

/// Guiones de ~4 grosores (con las tapas redondas) y huecos de ~2.5, siguiendo las curvas, anclados al largo de arco.
/// A lo sumo uno por tramo de entrada (el hueco crece solo en trazos con tramos larguísimos).
MeshPart _dashedPart(Stroke s, int a, int b, double feather) {
  final p = s.pts, hw = max(s.w / 2, .2);
  final col = _argbOf(s.o, s.color.toARGB32());
  if (b - a < 2) return _dotPart(s, p[a * 3], p[a * 3 + 1], hw, col, feather);
  final l = _lineOf(s, a, b);
  if (l.count < 2) return _dotPart(s, l.x[0], l.y[0], hw, col, feather);
  final w = _W(true);
  final body = max(s.w * 3, .1); // el guion sin las tapas (cada una suma medio grosor)
  final period = max(s.w * 6.5, l.length / (b - a - 1));
  final pre = _arcBefore(s, a);
  for (var k = ((pre - body) / period).floor(); k * period - pre <= l.length; k++) {
    final u0 = k * period - pre, u1 = u0 + body;
    if (u1 < 0) continue;
    final (xs, ys) = _subLine(l, max(u0, 0), min(u1, l.length));
    _stripDedupe(w, xs, ys, List<double>.filled(xs.length, hw), List<int>.filled(xs.length, col), round: true, feather: feather);
  }
  return w.done();
}

// ---------------- doble línea ----------------

/// Dos líneas finas paralelas a ±0.6 grosores de la línea central; en las curvas el lado interno se recorta al radio
/// de curvatura (sin pliegues).
MeshPart _doublePart(Stroke s, int a, int b, double feather) {
  final p = s.pts, hw = max(s.w * .2, .15), argb = s.color.toARGB32();
  final w = _W(feather > 0);
  final col0 = feather > 0 ? argb : 0;
  final off = s.w * .6;
  if (b - a < 2) {
    _circle(w, p[a * 3], p[a * 3 + 1] - off, hw, col0, 8, feather: feather);
    _circle(w, p[a * 3], p[a * 3 + 1] + off, hw, col0, 8, feather: feather);
    return w.done();
  }
  final l = _lineOf(s, a, b, minStep: max(s.w * .2, .3));
  if (l.count < 2) {
    _circle(w, l.x[0], l.y[0] - off, hw, col0, 8, feather: feather);
    _circle(w, l.x[0], l.y[0] + off, hw, col0, 8, feather: feather);
    return w.done();
  }
  final f = _Frames.of(l);
  for (final sign in const [1.0, -1.0]) {
    final (xs, ys) = _offsetLine(l, f, off * sign);
    _stripDedupe(w, xs, ys, List<double>.filled(xs.length, hw), feather > 0 ? List<int>.filled(xs.length, argb) : null,
        round: true, feather: feather);
  }
  return w.done();
}

// ---------------- tiza ----------------

const _chalkPasses = 3;

/// Grosor parejo con grano: [_chalkPasses] pasadas finas paralelas, cada una con corrimiento, grosor y alfa distintos
/// en cada vértice (hash del índice del vértice desde el inicio), así los bordes quedan irregulares y el trazo áspero.
MeshPart _chalkPart(Stroke s, int a, int b, double feather) {
  final p = s.pts, rgb = s.color.toARGB32() & 0x00FFFFFF;
  final w = _W(true);
  if (b - a < 2) {
    _circle(w, p[a * 3], p[a * 3 + 1], s.w * .4, _argbOf(s.o * .7, rgb), 12, feather: feather);
    return w.done();
  }
  final l = _lineOf(s, a, b, minStep: max(s.w * .3, .5));
  if (l.count < 2) {
    _circle(w, l.x[0], l.y[0], s.w * .4, _argbOf(s.o * .7, rgb), 12, feather: feather);
    return w.done();
  }
  final f = _Frames.of(l);
  final salt = a * 16;
  for (var j = 0; j < _chalkPasses; j++) {
    final base = ((j + .5) / _chalkPasses * 2 - 1) * s.w * .5;
    final (xs, ys) = _offsetLine(l, f, base, jitter: (i) => (_rnd(salt + i, j * 4 + 1) - .5) * s.w * .2);
    final hs = <double>[], cs = <int>[];
    for (var i = 0; i < l.count; i++) {
      hs.add(s.w * .2 * (.6 + .8 * _rnd(salt + i, j * 4 + 2)));
      final r = _rnd(salt + i, j * 4 + 3);
      cs.add(_argbOf(r < .16 ? s.o * .1 : s.o * (.35 + .65 * r), rgb)); // de a ratos casi se corta: grano
    }
    _stripDedupe(w, xs, ys, hs, cs, round: true, feather: feather);
  }
  return w.done();
}

// ---------------- rotulador biselado ----------------

/// Como `calli` (punta plana a ángulo fijo) pero más ancha, sin presión, con extremos rectos y opacidad pareja.
MeshPart _chiselPart(Stroke s, int a, int b, double feather) {
  final p = s.pts, argb = s.color.toARGB32();
  final w = _W(feather > 0);
  final col0 = feather > 0 ? argb : 0;
  final k = s.w * 1.4, line = max(s.w * .13, .15);
  const dx = .866, dy = -.5; // la punta plana a 30°
  if (b - a < 2) {
    final x = p[a * 3], y = p[a * 3 + 1], px = -dy * line * 1.6, py = dx * line * 1.6;
    final v = w.v(x + dx * k + px, y + dy * k + py, col0);
    w.v(x + dx * k - px, y + dy * k - py, col0);
    w.v(x - dx * k - px, y - dy * k - py, col0);
    w.v(x - dx * k + px, y - dy * k + py, col0);
    w.quad(v, v + 1, v + 2, v + 3);
    return w.done();
  }
  final l = _lineOf(s, a, b, minStep: max(s.w * .15, .3));
  if (l.count < 2) return _chiselPart(s, a, a + 1, feather);
  int? prev;
  for (var i = 0; i < l.count; i++) {
    final x = l.x[i], y = l.y[i];
    final int v0;
    if (feather > 0) {
      // borde solo en los costados largos; las puntas quedan rectas
      final kc = max(k - feather / 2, k * .3), ko = k + feather / 2, c0 = argb & 0x00FFFFFF;
      v0 = w.v(x + dx * ko, y + dy * ko, c0);
      w.v(x + dx * kc, y + dy * kc, argb);
      w.v(x - dx * kc, y - dy * kc, argb);
      w.v(x - dx * ko, y - dy * ko, c0);
      if (prev != null) {
        for (var j = 0; j < 3; j++) {
          w.quad(prev + j, prev + j + 1, v0 + j + 1, v0 + j);
        }
      }
    } else {
      v0 = w.v(x + dx * k, y + dy * k, col0);
      w.v(x - dx * k, y - dy * k, col0);
      if (prev != null) w.quad(prev, prev + 1, v0 + 1, v0);
    }
    prev = v0;
  }
  // un hilo fino para que no desaparezca al avanzar a lo largo de la punta
  _stripDedupe(w, l.x, l.y, List<double>.filled(l.count, line), feather > 0 ? List<int>.filled(l.count, argb) : null,
      round: false, feather: feather);
  return w.done();
}

// ---------------- neón ----------------

/// Abanico de anillos concéntricos desde [a0] por [sweep] radianes ([rings]: radio y color; radio 0 = centro).
void _ringFan(_W w, double cx, double cy, double a0, double sweep, int steps, List<(double, int)> rings) {
  final rows = <List<int>>[];
  int? center;
  for (final (r, c) in rings) {
    if (r == 0) {
      center = w.v(cx, cy, c);
      continue;
    }
    rows.add([
      for (var k = 0; k <= steps; k++) w.v(cx + r * cos(a0 + sweep * k / steps), cy + r * sin(a0 + sweep * k / steps), c)
    ]);
  }
  for (var k = 0; k < steps; k++) {
    if (center != null) w.tri(center, rows[0][k], rows[0][k + 1]);
    for (var r = 0; r + 1 < rows.length; r++) {
      w.quad(rows[r][k], rows[r + 1][k], rows[r + 1][k + 1], rows[r][k + 1]);
    }
  }
}

/// Neón: núcleo fino casi blanco y halo del color que se desvanece hacia afuera (colores por vértice, sin capas).
MeshPart _neonPart(Stroke s, int a, int b) {
  final p = s.pts, rgb = s.color.toARGB32() & 0x00FFFFFF;
  final w = _W(true);
  final core = max(s.w * .2, .3), halo = core + s.w * 1.5, mid = core + (halo - core) * .4;
  final cCore = _argbOf(s.o, _mix(rgb, 0xFFFFFF, .85));
  final cMid = _argbOf(s.o * .55, rgb), cEdge = _argbOf(0, rgb);
  final rings = <(double, int)>[(0.0, cCore), (core, cCore), (mid, cMid), (halo, cEdge)];
  if (b - a < 2) {
    _ringFan(w, p[a * 3], p[a * 3 + 1], 0, 2 * pi, 14, rings);
    return w.done();
  }
  final l = _lineOf(s, a, b, minStep: max(s.w * .35, .4));
  if (l.count < 2) {
    _ringFan(w, l.x[0], l.y[0], 0, 2 * pi, 14, rings);
    return w.done();
  }
  final m = l.count;
  final dx = List<double>.filled(m - 1, 0), dy = List<double>.filled(m - 1, 0);
  for (var i = 0; i < m - 1; i++) {
    final len = _hyp(l.x[i + 1] - l.x[i], l.y[i + 1] - l.y[i]);
    dx[i] = (l.x[i + 1] - l.x[i]) / len;
    dy[i] = (l.y[i + 1] - l.y[i]) / len;
  }
  final prof = <(double, int)>[(-halo, cEdge), (-mid, cMid), (-core, cCore), (core, cCore), (mid, cMid), (halo, cEdge)];
  int section(int i, double nx, double ny, double scale) {
    final v0 = w.v(l.x[i] + nx * prof[0].$1 * scale, l.y[i] + ny * prof[0].$1 * scale, prof[0].$2);
    for (var j = 1; j < prof.length; j++) {
      w.v(l.x[i] + nx * prof[j].$1 * scale, l.y[i] + ny * prof[j].$1 * scale, prof[j].$2);
    }
    return v0;
  }

  void join(int p0, int p1) {
    for (var j = 0; j < prof.length - 1; j++) {
      w.quad(p0 + j, p0 + j + 1, p1 + j + 1, p1 + j);
    }
  }

  _ringFan(w, l.x[0], l.y[0], atan2(dx[0], -dy[0]), pi, 8, rings);
  var prev = section(0, -dy[0], dx[0], 1);
  for (var i = 1; i < m - 1; i++) {
    final dot = dx[i - 1] * dx[i] + dy[i - 1] * dy[i];
    if (dot >= .5) {
      var bx = -dy[i - 1] - dy[i], by = dx[i - 1] + dx[i];
      final bl = _hyp(bx, by);
      bx /= bl;
      by /= bl;
      final cur = section(i, bx, by, 1 / max(bx * -dy[i] + by * dx[i], .5));
      join(prev, cur);
      prev = cur;
    } else {
      join(prev, section(i, -dy[i - 1], dx[i - 1], 1));
      _ringFan(w, l.x[i], l.y[i], 0, 2 * pi, 12, rings);
      prev = section(i, -dy[i], dx[i], 1);
    }
  }
  join(prev, section(m - 1, -dy[m - 2], dx[m - 2], 1));
  _ringFan(w, l.x[m - 1], l.y[m - 1], atan2(dx[m - 2], -dy[m - 2]), -pi, 8, rings);
  return w.done();
}
