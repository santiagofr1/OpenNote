import 'dart:math';

/// Dónde se escriben los triángulos de una forma (lo implementa el escritor de mallas; solo `dart:core`/`dart:math`
/// para que todo siga andando en un isolate).
abstract interface class ShapeSink {
  int get count;

  /// Agrega un vértice (con color ARGB [c]) y devuelve su índice.
  int v(double x, double y, [int c = 0]);
  void tri(int a, int b, int c);
}

/// Formas de la pintura, en el orden del panel (el trazo guarda `paint-<id>`).
const paintShapeIds = [
  'stars', 'hearts', 'sparkles', 'moons', 'dots', 'circles', 'bangs', 'bolts', 'ticks', 'crosses',
  'clouds', 'bubbles', 'leaves', 'paws', 'triangles', 'squares', 'diamonds', 'flowers', 'notes', 'none', // 'none': trazos viejos (= formas apagadas)
];

/// Cómo se rota cada forma según el número [rot] (0..2π, pseudoaleatorio estable): 0 = derecha, 1 = unos ±15°,
/// 2 = unos ±25°, 3 = cualquier ángulo.
const _tilt = {
  'stars': 3, 'sparkles': 3, 'moons': 3, 'squares': 3, 'diamonds': 3, 'triangles': 3, 'leaves': 3,
  'bolts': 2,
  'hearts': 1, 'bangs': 1, 'notes': 1, 'bubbles': 1, 'paws': 1, 'clouds': 1, 'ticks': 1, 'crosses': 1, 'flowers': 3,
};

/// Agrega la forma [id] centrada en ([cx],[cy]) y toda dentro del radio [r], rotada según [rot] (ver [_tilt]),
/// con el color ARGB [col] en todos sus vértices. 'none' (o un id que no existe) no agrega nada.
void paintShape(ShapeSink w, String id, double cx, double cy, double r, double rot, int col) {
  final t = _tilt[id] ?? 0;
  final ang = switch (t) { 3 => rot, 2 => (rot / (2 * pi) - .5) * .9, 1 => (rot / (2 * pi) - .5) * .52, _ => 0.0 };
  final c = _Ctx(w, cx, cy, r, ang, col);
  switch (id) {
    case 'stars':
      c.starShape(5, .45, -pi / 2);
    case 'sparkles':
      c.starShape(4, .2, -pi / 2);
    case 'hearts':
      c.heart();
    case 'moons':
      c.moon();
    case 'dots':
      c.disc(0, 0, .6, 12);
    case 'circles':
      c.ring(0, 0, .9, .12, 16);
    case 'bangs':
      c.poly([-.2, -.95, .2, -.95, .12, .35, -.12, .35]);
      c.disc(0, .75, .2, 8);
    case 'bolts':
      c.poly([.2, -.95, -.5, .1, -.05, .1, -.25, .95, .5, -.2, .05, -.2]);
    case 'ticks':
      c.line(-.6, .05, -.2, .5, .12);
      c.line(-.2, .5, .6, -.5, .12);
    case 'crosses':
      c.line(-.55, -.55, .55, .55, .12);
      c.line(.55, -.55, -.55, .55, .12);
    case 'clouds':
      c.disc(-.45, .15, .4, 10);
      c.disc(0, -.15, .5, 12);
      c.disc(.45, .1, .42, 10);
      c.poly([-.45, .1, .45, .1, .45, .52, -.45, .55]);
    case 'bubbles':
      c.bubble();
    case 'leaves':
      c.leaf();
    case 'paws':
      c.ellipse(0, .4, .5, .42, 12);
      for (final (x, y) in const [(-.66, -.02), (-.25, -.55), (.25, -.55), (.66, -.02)]) {
        c.disc(x, y, .21, 8);
      }
    case 'triangles':
      c.regular(3, -pi / 2);
    case 'squares':
      c.regular(4, pi / 4, .95);
    case 'diamonds':
      c.poly([0, -1, .6, 0, 0, 1, -.6, 0]);
    case 'flowers':
      for (var k = 0; k < 5; k++) {
        final a = -pi / 2 + k * 2 * pi / 5;
        c.disc(.58 * cos(a), .58 * sin(a), .4, 10);
      }
      c.disc(0, 0, .3, 10);
    case 'notes':
      c.ellipse(-.3, .55, .38, .28, 12, -.35);
      c.line(.05, .5, .05, -.82, .08);
      c.line(.05, -.82, .35, -.6, .08);
      c.line(.35, -.6, .52, -.28, .08);
  }
}

/// Coordenadas locales (radio 1, y hacia abajo) que se pasan a la hoja con el centro, el tamaño y la rotación.
class _Ctx {
  final ShapeSink w;
  final double cx, cy, r, cs, sn;
  final int col;
  _Ctx(this.w, this.cx, this.cy, this.r, double ang, this.col)
      : cs = cos(ang),
        sn = sin(ang);

  int v(double x, double y) => w.v(cx + (x * cs - y * sn) * r, cy + (x * sn + y * cs) * r, col);

  /// Abanico desde ([x0],[y0]) por el contorno [pts] (x, y, x, y...); la forma tiene que ser estrellada respecto del punto.
  void fan(double x0, double y0, List<double> pts) {
    final c = v(x0, y0), n = pts.length ~/ 2;
    final ids = [for (var i = 0; i < n; i++) v(pts[i * 2], pts[i * 2 + 1])];
    for (var i = 0; i < n; i++) {
      w.tri(c, ids[i], ids[(i + 1) % n]);
    }
  }

  /// Polígono simple cualquiera (recorte de orejas).
  void poly(List<double> pts) {
    final n = pts.length ~/ 2;
    final ids = [for (var i = 0; i < n; i++) v(pts[i * 2], pts[i * 2 + 1])];
    var area = 0.0;
    for (var i = 0; i < n; i++) {
      final j = (i + 1) % n;
      area += pts[i * 2] * pts[j * 2 + 1] - pts[j * 2] * pts[i * 2 + 1];
    }
    final sign = area >= 0 ? 1.0 : -1.0;
    double cross(int a, int b, int c) =>
        (pts[b * 2] - pts[a * 2]) * (pts[c * 2 + 1] - pts[a * 2 + 1]) - (pts[b * 2 + 1] - pts[a * 2 + 1]) * (pts[c * 2] - pts[a * 2]);
    final rest = List<int>.generate(n, (i) => i);
    while (rest.length > 3) {
      var clipped = false;
      for (var i = 0; i < rest.length; i++) {
        final a = rest[(i + rest.length - 1) % rest.length], b = rest[i], c = rest[(i + 1) % rest.length];
        if (cross(a, b, c) * sign <= 1e-9) continue; // vértice cóncavo
        var inside = false;
        for (final o in rest) {
          if (o == a || o == b || o == c) continue;
          if (cross(a, b, o) * sign >= 0 && cross(b, c, o) * sign >= 0 && cross(c, a, o) * sign >= 0) {
            inside = true;
            break;
          }
        }
        if (inside) continue;
        w.tri(ids[a], ids[b], ids[c]);
        rest.removeAt(i);
        clipped = true;
        break;
      }
      if (!clipped) break; // polígono degenerado: se completa abajo
    }
    for (var i = 1; i + 1 < rest.length; i++) {
      w.tri(ids[rest[0]], ids[rest[i]], ids[rest[i + 1]]);
    }
  }

  void disc(double x, double y, double rad, int steps) => ellipse(x, y, rad, rad, steps);

  void ellipse(double x, double y, double rx, double ry, int steps, [double tilt = 0]) {
    final ct = cos(tilt), st = sin(tilt);
    fan(x, y, [
      for (var k = 0; k < steps; k++) ...[
        x + rx * cos(2 * pi * k / steps) * ct - ry * sin(2 * pi * k / steps) * st,
        y + rx * cos(2 * pi * k / steps) * st + ry * sin(2 * pi * k / steps) * ct,
      ]
    ]);
  }

  /// Aro de radio exterior [rad] y semigrosor [h] (el grosor total es 2 x [h]).
  void ring(double x, double y, double rad, double h, int steps) {
    final inner = rad - 2 * h;
    final o = [for (var k = 0; k < steps; k++) v(x + rad * cos(2 * pi * k / steps), y + rad * sin(2 * pi * k / steps))];
    final i = [for (var k = 0; k < steps; k++) v(x + inner * cos(2 * pi * k / steps), y + inner * sin(2 * pi * k / steps))];
    for (var k = 0; k < steps; k++) {
      final n = (k + 1) % steps;
      w.tri(o[k], o[n], i[n]);
      w.tri(o[k], i[n], i[k]);
    }
  }

  /// Segmento grueso (semigrosor [h]) con tapas rectas que sobresalen [h]: dos segmentos seguidos se unen sin hueco.
  void line(double x0, double y0, double x1, double y1, double h) {
    var dx = x1 - x0, dy = y1 - y0;
    final l = sqrt(dx * dx + dy * dy);
    dx /= l;
    dy /= l;
    final ax = x0 - dx * h, ay = y0 - dy * h, bx = x1 + dx * h, by = y1 + dy * h;
    final a = v(ax - dy * h, ay + dx * h), b = v(ax + dy * h, ay - dx * h);
    final c = v(bx + dy * h, by - dx * h), d = v(bx - dy * h, by + dx * h);
    w.tri(a, b, c);
    w.tri(a, c, d);
  }

  /// Polígono regular de [n] vértices en el radio [scale], el primero en el ángulo [rot0] (abanico desde el centro).
  void regular(int n, double rot0, [double scale = 1]) {
    fan(0, 0, [
      for (var k = 0; k < n; k++) ...[scale * cos(rot0 + k * 2 * pi / n), scale * sin(rot0 + k * 2 * pi / n)]
    ]);
  }

  /// Estrella de [points] puntas de radio [scale] (las puntas interiores a [inner] del radio).
  void starShape(int points, double inner, double start, [double scale = 1]) {
    fan(0, 0, [
      for (var k = 0; k < points * 2; k++) ...[
        (k.isEven ? 1 : inner) * scale * cos(start + k * pi / points),
        (k.isEven ? 1 : inner) * scale * sin(start + k * pi / points),
      ]
    ]);
  }

  /// Corazón (curva paramétrica clásica, en unidades de 1/19).
  void heart() {
    const sc = 1 / 19;
    fan(0, -2.5 * sc, [
      for (var k = 0; k < 24; k++) ...[
        16 * pow(sin(2 * pi * k / 24), 3) * sc,
        -(13 * cos(2 * pi * k / 24) - 5 * cos(4 * pi * k / 24) - 2 * cos(6 * pi * k / 24) - cos(8 * pi * k / 24) + 2.5) * sc,
      ]
    ]);
  }

  /// Luna creciente: la franja entre el círculo de radio 1 y otro de .8 corrido .45.
  void moon() {
    const small = .8, d = .45;
    final xi = (1 - small * small + d * d) / (2 * d), yi = sqrt(1 - xi * xi);
    final alpha = atan2(yi, xi), beta = atan2(yi, xi - d);
    const steps = 12;
    int? prev;
    for (var k = 0; k <= steps; k++) {
      final t = k / steps;
      final ao = alpha + t * (2 * pi - 2 * alpha), ai = beta + t * (2 * pi - 2 * beta);
      final o = v(cos(ao), sin(ao));
      v(d + small * cos(ai), small * sin(ai));
      if (prev != null) {
        w.tri(prev, prev + 1, o + 1);
        w.tri(prev, o + 1, o);
      }
      prev = o;
    }
  }

  /// Globo de diálogo: rectángulo redondeado con una colita abajo a la izquierda.
  void bubble() {
    const x = .75, y0 = -.6, y1 = .3, cr = .25;
    final pts = <double>[];
    for (final (ox, oy, a0) in const [(x - cr, y0 + cr, -pi / 2), (x - cr, y1 - cr, 0.0), (-x + cr, y1 - cr, pi / 2), (-x + cr, y0 + cr, pi)]) {
      for (var k = 0; k <= 4; k++) {
        pts..add(ox + cr * cos(a0 + k * pi / 8))..add(oy + cr * sin(a0 + k * pi / 8));
      }
    }
    fan(0, (y0 + y1) / 2, pts);
    poly([-.5, .2, -.1, .2, -.55, .8]);
  }

  /// Hoja: elipse puntiaguda partida al medio por el nervio (un hueco fino).
  void leaf() {
    const steps = 10, gap = .05;
    for (final s in const [-1.0, 1.0]) {
      int? prev;
      for (var k = 0; k <= steps; k++) {
        final t = k / steps, x = -.95 + 1.9 * t, hgt = .55 * sin(pi * t);
        final a = v(x, s * gap), b = v(x, s * max(hgt, gap));
        if (prev != null) {
          w.tri(prev, prev + 1, b);
          w.tri(prev, b, a);
        }
        prev = a;
      }
    }
  }
}
