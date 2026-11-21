import 'dart:math';
import 'dart:typed_data';

import 'stroke.dart';

/// Algo con memoria nativa que hay que soltar (el `ui.Vertices` que arma el painter).
abstract interface class NativeHandle {
  void dispose();
}

/// Borde difuminado (en unidades de hoja) para antialias por alfa en los costados de las tiras.
/// 0 = apagado: Impeller de Android ya hace MSAA 4x en pantalla y en `toImage`. Si en la tablet se ven serruchos,
/// poné 1 (cuesta ~3x vértices y colores por vértice: ver docs/TECNICO.md, "Trazos como mallas").
double kMeshFeather = 0;

/// Un trozo de malla de triángulos (índices de 16 bits: máx. [maxVertices] vértices).
class MeshPart {
  final Float32List pos; // x, y por vértice, en coordenadas de hoja
  final Uint16List idx; // triángulos
  final Int32List? colors; // ARGB por vértice (lápiz, borde difuminado); null: color del paint
  /// Lo que el painter arma a partir de esto (`ui.Vertices`); se suelta con la malla.
  NativeHandle? native;
  MeshPart(this.pos, this.idx, this.colors);

  int get vertexCount => pos.length >> 1;
  int get bytes => pos.lengthInBytes + idx.lengthInBytes + (colors?.lengthInBytes ?? 0);
}

/// Geometría de un trazo: normalmente un solo [MeshPart]; los trazos larguísimos se parten.
class StrokeMesh {
  static const maxVertices = 65000;
  final List<MeshPart> parts;
  final int generation;
  StrokeMesh(this.parts, this.generation);

  int get bytes => parts.fold(0, (a, p) => a + p.bytes);
  int get vertexCount => parts.fold(0, (a, p) => a + p.vertexCount);
  bool get colored => parts.isNotEmpty && parts.first.colors != null;

  void dispose() {
    for (final p in parts) {
      p.native?.dispose();
      p.native = null;
    }
  }
}

/// Malla del trazo [s] (null si no tiene puntos). Solo usa tipos de `dart:core`, `dart:math` y `dart:typed_data`:
/// se puede calcular en un isolate (al decodificar la hoja) y mandar sin copiar.
StrokeMesh? buildStrokeMesh(Stroke s, {double? feather}) {
  if (s.n == 0) return null;
  final f = feather ?? kMeshFeather;
  final parts = <MeshPart>[];
  _buildRange(s, 0, s.n, f, parts);
  return StrokeMesh(parts, s.meshGen);
}

const _chunk = 6000; // puntos por parte (con 4 vértices por punto queda lejos del tope de 65k)

void _buildRange(Stroke s, int a, int b, double feather, List<MeshPart> out) {
  if (b - a > _chunk) {
    // se parte con un punto compartido: los cortes quedan tapados por tapas/uniones redondas
    final mid = (a + b) ~/ 2;
    _buildRange(s, a, mid + 1, feather, out);
    _buildRange(s, mid, b, feather, out);
    return;
  }
  final part = _buildPart(s, a, b, feather);
  if (part.vertexCount > StrokeMesh.maxVertices && b - a > 2) {
    final mid = (a + b) ~/ 2;
    _buildRange(s, a, mid + 1, feather, out);
    _buildRange(s, mid, b, feather, out);
    return;
  }
  out.add(part);
}

MeshPart _buildPart(Stroke s, int a, int b, double feather) {
  final p = s.pts;
  final n = b - a;
  double x(int i) => p[(a + i) * 3];
  double y(int i) => p[(a + i) * 3 + 1];
  double pr(int i) => p[(a + i) * 3 + 2];
  final argb = s.color.toARGB32();
  final rgb = argb & 0x00FFFFFF;
  int alpha(double al) => ((al.clamp(0.0, 1.0)) * 255).round() << 24 | rgb;

  switch (s.k) {
    case 'hl':
    case 'fine':
      final w = _W(feather > 0);
      final xs = <double>[], ys = <double>[];
      _smoothCenterline([for (var i = 0; i < n; i++) ...[x(i), y(i)]], xs, ys);
      if (xs.length < 2) {
        // un solo punto: el trazo viejo era una línea de .1 de largo
        xs.add(xs[0] + .1);
        ys.add(ys[0]);
      }
      final hw = List<double>.filled(xs.length, s.w / 2);
      final col = feather > 0 ? List<int>.filled(xs.length, argb) : null;
      _strip(w, xs, ys, hw, col, round: s.k == 'fine', feather: feather);
      return w.done();
    case 'pencil':
      final w = _W(true);
      if (n == 1) {
        _circle(w, x(0), y(0), s.w * .4, alpha(s.o * .6), 12);
        return w.done();
      }
      // El dibujo viejo era un drawLine por tramo con tapas redondas: el alfa se apilaba en cada unión (cuentas) y
      // eso daba el grano. Acá la tira lleva un vértice en cada punto (alfa apilado: 1-(1-a)(1-b), con una variación
      // pseudoaleatoria estable) y otro en el medio de cada tramo (alfa del tramo): el color se interpola y queda la
      // misma cuenta periódica, sin pasadas superpuestas.
      double segA(int i) => s.o * (.28 + .6 * pr(i)); // alfa del tramo i-1..i
      double segH(int i) => s.w * (.55 + .6 * pr(i)) / 2;
      final xs = <double>[], ys = <double>[], hw = <double>[], col = <int>[];
      final gx = <double>[], gy = <double>[], ghw = <double>[], gcol = <int>[];
      for (var i = 0; i < n; i++) {
        final i1 = i == 0 ? 1 : i; // el primer punto copia al segundo
        final next = i + 1 < n ? i + 1 : i;
        final a0 = segA(i1), a1 = segA(next);
        final stacked = i == 0 || i == n - 1 ? a0 : 1 - (1 - a0) * (1 - a1);
        xs.add(x(i));
        ys.add(y(i));
        hw.add(i == 0 || i == n - 1 ? segH(i1) : (segH(i1) + segH(next)) / 2);
        col.add(alpha(stacked * _grain(a + i, 1)));
        if (i + 1 < n) {
          xs.add((x(i) + x(i + 1)) / 2);
          ys.add((y(i) + y(i + 1)) / 2);
          hw.add(segH(i + 1));
          col.add(alpha(a1));
        }
        // grano: una línea fina corrida, pseudoaleatoria pero estable
        final q = pr(i1);
        final j = ((max(1, a + i) * 7919) % 13 - 6) / 6 * s.w * .3;
        gx.add(x(i) + j);
        gy.add(y(i) - j);
        ghw.add(s.w * .35 / 2);
        gcol.add(alpha(s.o * (.12 + .25 * q)));
      }
      _stripDedupe(w, xs, ys, hw, col, round: true, feather: 0);
      _stripDedupe(w, gx, gy, ghw, gcol, round: true, feather: 0);
      return w.done();
    case 'calli':
      final w = _W(feather > 0);
      final col0 = feather > 0 ? argb : 0;
      final line = s.w * .22 / 2;
      if (n == 1) {
        _circle(w, x(0), y(0), line, col0, 8);
        return w.done();
      }
      // cinta: la punta plana a 45° (el ancho en cada dirección sale del vector fijo)
      const d = .7071;
      int? prev;
      for (var i = 0; i < n; i++) {
        final k = s.w * (.55 + .9 * pr(i));
        final v0 = w.v(x(i) + d * k, y(i) - d * k, col0);
        w.v(x(i) - d * k, y(i) + d * k, col0);
        if (prev != null) w.quad(prev, prev + 1, v0 + 1, v0);
        prev = v0;
      }
      final xs = [for (var i = 0; i < n; i++) x(i)], ys = [for (var i = 0; i < n; i++) y(i)];
      final hw = List<double>.filled(n, line);
      _stripDedupe(w, xs, ys, hw, feather > 0 ? List<int>.filled(n, argb) : null, round: true, feather: 0);
      return w.done();
    default:
      // pen / fountain: grosor según presión y (pluma) velocidad, con la misma fórmula que el dibujo viejo
      final fountain = s.k == 'fountain';
      final minF = fountain ? .15 : .35, rangeF = fountain ? 1.7 : 1.3;
      final w = _W(feather > 0);
      if (n == 1) {
        _circle(w, x(0), y(0), s.w * (minF + rangeF * pr(0)) / 2, feather > 0 ? argb : 0, 16);
        return w.done();
      }
      final xs = <double>[], ys = <double>[], hw = <double>[];
      var f = 1.0;
      for (var i = 0; i < n; i++) {
        // el grosor del tramo i-1..i usa la presión del punto i; el primer punto copia al segundo
        final q = i == 0 ? 1 : i;
        if (i > 0 && fountain) {
          final dist = sqrt(pow(x(i) - x(i - 1), 2) + pow(y(i) - y(i - 1), 2));
          final target = (1.25 - dist / (s.w * 3 + 3)).clamp(.45, 1.15);
          f = f * .7 + target * .3;
        }
        xs.add(x(i));
        ys.add(y(i));
        hw.add(s.w * (minF + rangeF * pr(q)) * (fountain ? (i == 0 ? 1 : f) : 1) / 2);
      }
      if (fountain) hw[0] = hw.length > 1 ? hw[1] : hw[0];
      _stripDedupe(w, xs, ys, hw, feather > 0 ? List<int>.filled(n, argb) : null, round: true, feather: feather);
      return w.done();
  }
}

/// Variación de alfa del lápiz por vértice: pseudoaleatoria pero estable (depende solo del índice global del punto),
/// entre [_grainLo] y [_grainHi] (se probó: más variación aleja al lápiz del dibujo viejo en la métrica del test).
const double _grainLo = .85, _grainHi = 1.15;
double _grain(int i, int salt) {
  final h = ((i * 7919 + salt * 104729) * 2654435761 >> 7) % 1021;
  return _grainLo + (_grainHi - _grainLo) * h / 1020;
}

/// Curva del trazo suave: pasa por los puntos medios con los puntos como control (como el `Path` viejo).
void _smoothCenterline(List<double> p, List<double> xs, List<double> ys) {
  final n = p.length ~/ 2;
  xs.add(p[0]);
  ys.add(p[1]);
  if (n == 1) return;
  var cx = p[0], cy = p[1]; // desde dónde sale el tramo
  for (var i = 1; i < n - 1; i++) {
    final qx = p[i * 2], qy = p[i * 2 + 1];
    final ex = (qx + p[i * 2 + 2]) / 2, ey = (qy + p[i * 2 + 3]) / 2;
    final len = (qx - cx).abs() + (qy - cy).abs() + (ex - qx).abs() + (ey - qy).abs();
    final steps = (len / 5).ceil().clamp(1, 8);
    for (var k = 1; k <= steps; k++) {
      final t = k / steps, u = 1 - t;
      xs.add(u * u * cx + 2 * u * t * qx + t * t * ex);
      ys.add(u * u * cy + 2 * u * t * qy + t * t * ey);
    }
    cx = ex;
    cy = ey;
  }
  xs.add(p[n * 2 - 2]);
  ys.add(p[n * 2 - 1]);
}

class _W {
  final bool colored;
  final pos = <double>[];
  final idx = <int>[];
  final cols = <int>[];
  _W(this.colored);

  int get count => pos.length >> 1;
  int v(double x, double y, [int c = 0]) {
    pos
      ..add(x)
      ..add(y);
    if (colored) cols.add(c);
    return count - 1;
  }

  void tri(int a, int b, int c) => idx
    ..add(a)
    ..add(b)
    ..add(c);
  void quad(int a, int b, int c, int d) {
    tri(a, b, c);
    tri(a, c, d);
  }

  MeshPart done() => MeshPart(Float32List.fromList(pos), Uint16List.fromList(idx), colored ? Int32List.fromList(cols) : null);
}

const _capSteps = 8;

/// Círculo (abanico) de [steps] lados.
void _circle(_W w, double cx, double cy, double r, int col, int steps) {
  final c = w.v(cx, cy, col);
  final first = w.v(cx + r, cy, col);
  var prev = first;
  for (var k = 1; k < steps; k++) {
    final a = 2 * pi * k / steps;
    final cur = w.v(cx + r * cos(a), cy + r * sin(a), col);
    w.tri(c, prev, cur);
    prev = cur;
  }
  w.tri(c, prev, first);
}

/// Media vuelta de abanico en ([cx],[cy]): del lado [nx],[ny] por el sentido [dx],[dy] al lado opuesto.
void _semi(_W w, double cx, double cy, double nx, double ny, double dx, double dy, double r, int col) {
  final c = w.v(cx, cy, col);
  var prev = w.v(cx + nx * r, cy + ny * r, col);
  for (var k = 1; k <= _capSteps; k++) {
    final a = pi * k / _capSteps;
    final ca = cos(a), sa = sin(a);
    final cur = w.v(cx + (nx * ca + dx * sa) * r, cy + (ny * ca + dy * sa) * r, col);
    w.tri(c, prev, cur);
    prev = cur;
  }
}

/// Como [_strip] pero sacando antes los puntos repetidos (el ancho de un repetido se pierde).
void _stripDedupe(_W w, List<double> x, List<double> y, List<double> hw, List<int>? col,
    {required bool round, required double feather}) {
  final xs = <double>[x[0]], ys = <double>[y[0]], hs = <double>[hw[0]];
  final cs = col == null ? null : <int>[col[0]];
  for (var i = 1; i < x.length; i++) {
    if ((x[i] - xs.last).abs() + (y[i] - ys.last).abs() < .02) {
      hs[hs.length - 1] = hw[i];
      cs?[cs.length - 1] = col![i];
      continue;
    }
    xs.add(x[i]);
    ys.add(y[i]);
    hs.add(hw[i]);
    cs?.add(col![i]);
  }
  if (xs.length < 2) {
    _circle(w, xs[0], ys[0], hs[0], cs?[0] ?? 0, 16);
    return;
  }
  _strip(w, xs, ys, hs, cs, round: round, feather: feather);
}

/// Tira de triángulos a lo largo de la línea [x],[y] (sin puntos repetidos, al menos 2) con semiancho [hw] en
/// cada punto. Uniones suaves por bisectriz; en giros de más de 60° se corta la tira y se agrega un círculo
/// chico en el punto. Tapas redondas (o rectas si [round] es false). Con [feather] > 0 cada borde lleva una
/// franja exterior de alfa 0 (antialias barato; hace falta [col]).
void _strip(_W w, List<double> x, List<double> y, List<double> hw, List<int>? col,
    {required bool round, required double feather}) {
  final m = x.length;
  final dx = List<double>.filled(m - 1, 0), dy = List<double>.filled(m - 1, 0);
  for (var i = 0; i < m - 1; i++) {
    final ex = x[i + 1] - x[i], ey = y[i + 1] - y[i];
    final l = sqrt(ex * ex + ey * ey);
    dx[i] = ex / l;
    dy[i] = ey / l;
  }
  int colAt(int i) => col == null ? 0 : col[i];
  final fe = feather > 0 && col != null;
  // un "par" son 2 vértices (o 4 con borde difuminado) consecutivos: devuelve el índice del primero
  int pair(int i, double nx, double ny, double scale) {
    final h = hw[i] * scale;
    if (!fe) {
      final v0 = w.v(x[i] + nx * h, y[i] + ny * h, colAt(i));
      w.v(x[i] - nx * h, y[i] - ny * h, colAt(i));
      return v0;
    }
    final hc = max(h - feather / 2, h * .3), ho = h + feather / 2;
    final c0 = colAt(i) & 0x00FFFFFF;
    final v0 = w.v(x[i] + nx * ho, y[i] + ny * ho, c0);
    w.v(x[i] + nx * hc, y[i] + ny * hc, colAt(i));
    w.v(x[i] - nx * hc, y[i] - ny * hc, colAt(i));
    w.v(x[i] - nx * ho, y[i] - ny * ho, c0);
    return v0;
  }

  final k = fe ? 4 : 2;
  void join(int a, int b) {
    for (var j = 0; j < k - 1; j++) {
      w.quad(a + j, a + j + 1, b + j + 1, b + j);
    }
  }

  // tapa de arranque
  if (round) _semi(w, x[0], y[0], -dy[0], dx[0], -dx[0], -dy[0], hw[0], colAt(0));
  var prev = pair(0, -dy[0], dx[0], 1);
  for (var i = 1; i < m - 1; i++) {
    final dot = dx[i - 1] * dx[i] + dy[i - 1] * dy[i];
    if (dot >= .5) {
      var bx = -dy[i - 1] - dy[i], by = dx[i - 1] + dx[i];
      final bl = sqrt(bx * bx + by * by);
      bx /= bl;
      by /= bl;
      final scale = 1 / max(bx * -dy[i] + by * dx[i], .5);
      final cur = pair(i, bx, by, scale);
      join(prev, cur);
      prev = cur;
    } else {
      // giro cerrado: termina el tramo anterior, empieza otro y se redondea el vértice
      join(prev, pair(i, -dy[i - 1], dx[i - 1], 1));
      _circle(w, x[i], y[i], hw[i], colAt(i), 10);
      prev = pair(i, -dy[i], dx[i], 1);
    }
  }
  join(prev, pair(m - 1, -dy[m - 2], dx[m - 2], 1));
  if (round) _semi(w, x[m - 1], y[m - 1], -dy[m - 2], dx[m - 2], dx[m - 2], dy[m - 2], hw[m - 1], colAt(m - 1));
}
