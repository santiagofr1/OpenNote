import 'dart:math';
import 'dart:typed_data';

import 'paint_shapes.dart';
import 'stroke.dart';
import 'values.dart';

part 'stroke_mesh_tips.dart';

/// Algo con memoria nativa que hay que soltar (el `ui.Vertices` que arma el painter).
abstract interface class NativeHandle {
  void dispose();
}

/// Ancho del borde difuminado en píxeles de pantalla: el antialias de las mallas (`drawVertices` no lo tiene).
const kFeatherPx = 1.0;

/// Borde difuminado vigente, en unidades de hoja (0 = sin borde: tests y miniaturas). Lo fija el editor según el zoom
/// (ver [featherForPxPerUnit]); las mallas recuerdan con cuál se armaron ([StrokeMesh.feather]).
double meshFeather = 0;

/// Borde (en unidades de hoja) que da [kFeatherPx] píxeles de pantalla con [pxPerUnit] píxeles por unidad (zoom por
/// devicePixelRatio). El factor se cuantiza a escalones de 2^(1/2) para no rearmar las mallas en cada cuadro del zoom.
double featherForPxPerUnit(double pxPerUnit) {
  if (!(pxPerUnit > 0) || pxPerUnit.isInfinite) return 0;
  final step = pow(2, (log(pxPerUnit) / ln2 * 2).round() / 2).toDouble();
  return kFeatherPx / step;
}

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

  /// Borde difuminado (unidades de hoja) con el que se armó; 0 si no lleva.
  final double feather;
  StrokeMesh(this.parts, this.generation, [this.feather = 0]);

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
  final f = feather ?? meshFeather;
  final parts = <MeshPart>[];
  if (isPaint(s.k)) {
    // partes de tamaño fijo y alineadas al inicio: al dibujar en vivo solo cambia la última
    for (var a = 0; a < s.n; a += _paintChunk) {
      _paintRange(s, a, min(a + _paintChunk, s.n), f, parts);
    }
  } else {
    _buildRange(s, 0, s.n, f, parts);
  }
  return StrokeMesh(parts, s.meshGen, f);
}

/// ¿La malla de [s] lleva colores por vértice ([StrokeMesh.colored])? Sale del trazo, sin armarla: lápiz y pintura
/// siempre; las puntas con alfa por vértice ([tipHasVertexAlpha]) también; el resto cuando hay borde difuminado
/// ([meshFeather] o [feather]).
bool meshIsColored(Stroke s, {double? feather}) =>
    isPaint(s.k) || tipHasVertexAlpha(s.k) || (feather ?? meshFeather) > 0;

/// Cota aproximada de los vértices de la malla de [s] sin armarla (para agrupar trazos en lotes): no depende del
/// borde difuminado, así los lotes no cambian al cambiar este.
int estimateMeshVertices(Stroke s) {
  final n = s.n;
  if (isPaint(s.k)) return 60 * n + 30;
  return switch (s.k) {
    'pencil' => 16 * n + 30,
    'calli' => 8 * n + 20,
    // las nuevas: la línea suave tiene a lo sumo [_tipSteps] vértices por tramo de entrada (y se ralea); los puntos
    // y guiones además tienen tope duro por tramo (ver stroke_mesh_tips.dart)
    'dotted' => 2 * _dotMaxVertices * n + 30,
    'dashed' => 40 * n + 40,
    'chalk' => 36 * n + 100,
    'chisel' => 24 * n + 60,
    'neon' => 20 * n + 120,
    'double' => 26 * n + 100,
    _ => 4 * n + 34,
  };
}

const _chunk = 6000; // puntos por parte (con 4 vértices por punto queda lejos del tope de 65k)
const _paintChunk = 250; // la pintura lleva ~20 vértices por muestra y decoración: partes chicas

/// Parte [a], [b) de una pintura; si igual se pasa del tope de vértices se parte en dos (disjuntas).
void _paintRange(Stroke s, int a, int b, double feather, List<MeshPart> out) {
  final part = _paintPart(s, a, b, feather);
  if (part.vertexCount > StrokeMesh.maxVertices && b - a > 1) {
    final mid = (a + b) ~/ 2;
    _paintRange(s, a, mid, feather, out);
    _paintRange(s, mid, b, feather, out);
    return;
  }
  out.add(part);
}

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
    case final k when isPaint(k):
      return _paintPart(s, a, b, feather); // (no pasa por acá: buildStrokeMesh arma la pintura aparte)
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
    case 'dotted':
      return _dottedPart(s, a, b, feather);
    case 'dashed':
      return _dashedPart(s, a, b, feather);
    case 'chalk':
      return _chalkPart(s, a, b, feather);
    case 'chisel':
      return _chiselPart(s, a, b, feather);
    case 'neon':
      return _neonPart(s, a, b);
    case 'double':
      return _doublePart(s, a, b, feather);
    case 'pencil':
      final w = _W(true);
      if (n == 1) {
        _circle(w, x(0), y(0), s.w * .4, alpha(s.o * .6), 12, feather: feather);
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
      _stripDedupe(w, xs, ys, hw, col, round: true, feather: feather);
      _stripDedupe(w, gx, gy, ghw, gcol, round: true, feather: feather);
      return w.done();
    case 'calli':
      final w = _W(feather > 0);
      final col0 = feather > 0 ? argb : 0;
      final line = s.w * .22 / 2;
      if (n == 1) {
        _circle(w, x(0), y(0), line, col0, 8, feather: feather);
        return w.done();
      }
      // cinta: la punta plana a 45° (el ancho en cada dirección sale del vector fijo)
      const d = .7071;
      int? prev;
      for (var i = 0; i < n; i++) {
        final k = s.w * (.55 + .9 * pr(i));
        final int v0;
        if (feather > 0) {
          // borde solo en los costados largos (la cinta se abre sobre el vector fijo); las puntas quedan rectas
          final kc = max(k - feather / 2, k * .3), ko = k + feather / 2, c0 = argb & 0x00FFFFFF;
          v0 = w.v(x(i) + d * ko, y(i) - d * ko, c0);
          w.v(x(i) + d * kc, y(i) - d * kc, argb);
          w.v(x(i) - d * kc, y(i) + d * kc, argb);
          w.v(x(i) - d * ko, y(i) + d * ko, c0);
          if (prev != null) {
            for (var j = 0; j < 3; j++) {
              w.quad(prev + j, prev + j + 1, v0 + j + 1, v0 + j);
            }
          }
        } else {
          v0 = w.v(x(i) + d * k, y(i) - d * k, col0);
          w.v(x(i) - d * k, y(i) + d * k, col0);
          if (prev != null) w.quad(prev, prev + 1, v0 + 1, v0);
        }
        prev = v0;
      }
      final xs = [for (var i = 0; i < n; i++) x(i)], ys = [for (var i = 0; i < n; i++) y(i)];
      final hw = List<double>.filled(n, line);
      _stripDedupe(w, xs, ys, hw, feather > 0 ? List<int>.filled(n, argb) : null, round: true, feather: feather);
      return w.done();
    default:
      // pen / fountain: grosor según presión y (pluma) velocidad, con la misma fórmula que el dibujo viejo
      final fountain = s.k == 'fountain';
      final cover = s.k == kCoverTip; // corrector: grosor parejo, sin presión
      final minF = cover ? 1.0 : (fountain ? .15 : .35), rangeF = cover ? 0.0 : (fountain ? 1.7 : 1.3);
      final w = _W(feather > 0);
      if (n == 1) {
        _circle(w, x(0), y(0), s.w * (minF + rangeF * pr(0)) / 2, feather > 0 ? argb : 0, 16, feather: feather);
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

/// Pintura decorativa (`paint-*`): una franja de fondo (pincel seco, resaltador o fibra, según `pp.style`), brillo y
/// formas, cada cosa activable. Todo con color por vértice (el alfa también) y determinístico: lo "azaroso" sale de
/// [_rnd] (hash de índices), nunca de un Random. Orden (lo de después queda arriba): fondo, brillo, formas.
///
/// Pensada para dibujarse en vivo (el trazo se re-malla en cada punto) y para curvas cerradas:
///  - La parte [a], [b) se corta de la MISMA curva suave que todo el trazo (cada parte tiene los puntos de control de
///    sus vecinas como contexto), así que las uniones entre partes quedan en el mismo punto y con la misma normal.
///  - Todo lo "azaroso" se ancla al largo de arco desde el inicio de la parte (celdas fijas), no al largo total: lo ya
///    dibujado no se mueve cuando el trazo crece; solo cambia la punta final.
///  - Las normales se suavizan por arco y los corrimientos del lado interno de una curva se recortan al radio de
///    curvatura local (sin pliegues).
/// Las puntas desflecadas del pincel solo van en el inicio y el fin reales del trazo (no en los cortes entre partes).
MeshPart _paintPart(Stroke s, int a, int b, double feather) {
  final p = s.pts, n = s.n;
  final w = _W(true), sw = max(s.w, 1.0), hw = sw / 2;
  final pp = s.pp ?? const PaintParams();
  final showShapes = pp.shapes && s.k != 'paint-none';
  final bgOn = pp.bg || (!showShapes && pp.glitter <= 0); // defensivo: nunca un trazo invisible
  const maxV = StrokeMesh.maxVertices - 100; // tope duro: un trazo larguísimo con pocos puntos no pasa de acá
  final nb = (sw / 4).round().clamp(8, 14);
  double dist(double x0, double y0, double x1, double y1) => sqrt((x1 - x0) * (x1 - x0) + (y1 - y0) * (y1 - y0));

  // 1) línea central suave de la parte, con contexto de las vecinas (iS / iE: dónde empieza y termina lo propio)
  final xs = <double>[], ys = <double>[];
  var iS = 0, iE = 0;
  if (n == 1) {
    // un toque: mancha corta horizontal
    xs.addAll([p[0] - sw * .3, p[0] + sw * .3]);
    ys.addAll([p[1], p[1]]);
    iE = 1;
  } else {
    final ctx = hw * 1.5 + 8;
    var ea = a, eb = b, acc = 0.0;
    for (var c = 0; ea > 0 && acc < ctx && c < 80; c++, ea--) {
      acc += dist(p[ea * 3], p[ea * 3 + 1], p[ea * 3 - 3], p[ea * 3 - 2]);
    }
    acc = 0;
    for (var c = 0; eb < n && acc < ctx && c < 80; c++, eb++) {
      acc += dist(p[eb * 3 - 3], p[eb * 3 - 2], p[eb * 3], p[eb * 3 + 1]);
    }
    // la curva es la cadena de cuadráticas por los puntos medios con cada punto como control (como el Path viejo)
    (double, double) startOf(int i) =>
        i <= 1 ? (p[0], p[1]) : ((p[i * 3 - 3] + p[i * 3]) / 2, (p[i * 3 - 2] + p[i * 3 + 1]) / 2);
    (double, double) endOf(int i) => i == n - 1
        ? (p[i * 3], p[i * 3 + 1])
        : i == 0
            ? (p[0], p[1])
            : ((p[i * 3] + p[i * 3 + 3]) / 2, (p[i * 3 + 1] + p[i * 3 + 4]) / 2);
    final st = startOf(ea);
    xs.add(st.$1);
    ys.add(st.$2);
    for (var i = ea; i < eb; i++) {
      if (i == a) iS = xs.length - 1;
      if (i == n - 1) {
        xs.add(p[i * 3]);
        ys.add(p[i * 3 + 1]);
      } else if (i > 0) {
        final cx = xs.last, cy = ys.last, qx = p[i * 3], qy = p[i * 3 + 1];
        final (ex, ey) = endOf(i);
        final len = (qx - cx).abs() + (qy - cy).abs() + (ex - qx).abs() + (ey - qy).abs();
        final steps = (len / 5).ceil().clamp(1, 8);
        for (var k = 1; k <= steps; k++) {
          final t = k / steps, u = 1 - t;
          xs.add(u * u * cx + 2 * u * t * qx + t * t * ex);
          ys.add(u * u * cy + 2 * u * t * qy + t * t * ey);
        }
      }
      if (i == b - 1) iE = xs.length - 1;
    }
  }
  final ra = List<double>.filled(xs.length, 0);
  for (var i = 1; i < xs.length; i++) {
    ra[i] = ra[i - 1] + dist(xs[i - 1], ys[i - 1], xs[i], ys[i]);
  }
  final arcS = ra[iS], arcE = ra[iE], ownLen = arcE - arcS;
  if (ownLen < .05) return w.done();

  // 2) re-muestreo por largo de arco: grilla anclada al inicio de la parte (+ una muestra justo en el fin propio).
  // El paso crece si el trazo es tan largo que no entraría.
  final ds = max(sw * .12 < 2 ? 2.0 : min(sw * .12, 6.0), ownLen / (30000 / (2 * nb)));
  final us = <double>[];
  var addedE = false;
  for (var k = -(arcS / ds).floor(); arcS + k * ds <= ra.last + 1e-9; k++) {
    final u = arcS + k * ds;
    if (u < arcE - .02) {
      us.add(u);
    } else {
      if (!addedE) us.add(arcE);
      addedE = true;
      if (u > arcE + .02) us.add(u);
    }
  }
  if (!addedE) us.add(arcE);
  final me = us.length;
  final ex = List<double>.filled(me, 0), ey = List<double>.filled(me, 0);
  var rj = 1;
  for (var i = 0; i < me; i++) {
    final u = us[i];
    while (rj < ra.length - 1 && ra[rj] < u) {
      rj++;
    }
    final seg = ra[rj] - ra[rj - 1], t = seg <= 0 ? 0.0 : ((u - ra[rj - 1]) / seg).clamp(0.0, 1.0);
    ex[i] = xs[rj - 1] + (xs[rj] - xs[rj - 1]) * t;
    ey[i] = ys[rj - 1] + (ys[rj] - ys[rj - 1]) * t;
  }
  // índices de lo propio
  var i0 = 0, i1 = me - 1;
  for (var i = 0; i < me; i++) {
    if ((us[i] - arcS).abs() <= 1e-9) i0 = i;
    if ((us[i] - arcE).abs() <= 1e-9) i1 = i;
  }
  if (i1 - i0 < 1) return w.done();

  // 3) tangentes suavizadas por arco (cuerda entre ±hw/2), normales y curvatura con signo
  // (la cuerda se toma sobre la línea cruda en u ± hw/2, no sobre las muestras: así no depende de la grilla y dos
  // partes vecinas dan la misma normal en su unión)
  (double, double) rawAt(double u) {
    var lo = 1, hi = ra.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (ra[mid] < u) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final seg = ra[lo] - ra[lo - 1], t = seg <= 0 ? 0.0 : ((u - ra[lo - 1]) / seg).clamp(0.0, 1.0);
    return (xs[lo - 1] + (xs[lo] - xs[lo - 1]) * t, ys[lo - 1] + (ys[lo] - ys[lo - 1]) * t);
  }

  final tx = List<double>.filled(me, 1), ty = List<double>.filled(me, 0);
  for (var i = 0; i < me; i++) {
    final (x0, y0) = rawAt(max(us[i] - hw / 2, 0));
    final (x1, y1) = rawAt(min(us[i] + hw / 2, ra.last));
    var dx = x1 - x0, dy = y1 - y0;
    var l = sqrt(dx * dx + dy * dy);
    if (l < 1e-9) {
      final q0 = max(i - 1, 0), q1 = min(i + 1, me - 1);
      dx = ex[q1] - ex[q0];
      dy = ey[q1] - ey[q0];
      l = sqrt(dx * dx + dy * dy);
    }
    if (l < 1e-9) {
      dx = 1;
      dy = 0;
      l = 1;
    }
    tx[i] = dx / l;
    ty[i] = dy / l;
  }
  var kap = List<double>.filled(me, 0);
  for (var i = 1; i < me - 1; i++) {
    kap[i] = (tx[i - 1] * ty[i + 1] - ty[i - 1] * tx[i + 1]) / max(us[i + 1] - us[i - 1], 1e-6);
  }
  final ks = List<double>.of(kap); // un promedio de 3 muestras saca el ruido del re-muestreo
  for (var i = 1; i < me - 1; i++) {
    ks[i] = (kap[i - 1] + kap[i] * 2 + kap[i + 1]) / 4;
  }
  kap = ks;

  // 4) lo propio: arrays cortados a [i0, i1]
  final m = i1 - i0 + 1;
  final sx = ex.sublist(i0, i1 + 1), sy = ey.sublist(i0, i1 + 1);
  final nx = [for (var i = i0; i <= i1; i++) -ty[i]], ny = [for (var i = i0; i <= i1; i++) tx[i]];
  final stx = tx.sublist(i0, i1 + 1), sty = ty.sublist(i0, i1 + 1);
  final sk = kap.sublist(i0, i1 + 1);
  final arc = [for (var i = i0; i <= i1; i++) us[i] - arcS];
  final total = arc[m - 1];

  /// Corrimiento [off] sobre la normal en la muestra [i], sin pasar del radio de curvatura del lado interno.
  double ef(int i, double off) {
    final k = sk[i];
    if (off * k > 0) {
      final lim = .85 / k.abs();
      if (off.abs() > lim) return off.sign * lim;
    }
    return off;
  }

  final rgb = s.color.toARGB32() & 0x00FFFFFF;
  int argb(double al, int c) => ((al.clamp(0.0, 1.0)) * 255).round() << 24 | c;
  final salt = a * 131;
  final realStart = a == 0, realEnd = b == n;

  // a) fondo
  if (bgOn && pp.style == 'brush') {
    // cerdas: tiras finas paralelas, cada una con desplazamiento, grosor, alfa y largo propios
    final trimCap = total * .4; // entre las dos puntas nunca se come más del 80% de la tira
    for (var j = 0; j < nb && w.count < maxV; j++) {
      final edge = j == 0 || j == nb - 1 ? 1.3 : 1.0;
      final off0 = ((j + .5) / nb * 2 - 1) * hw * .92 + (_rnd(j, 1) - .5) * hw * .1;
      final hb = hw / nb * (.8 + .6 * _rnd(j, 2));
      final al = s.o * (.55 + .45 * _rnd(j, 3));
      final tint = (_rnd(j, 6) - .5) * .16; // varía el tono: + aclara, - oscurece
      final c = tint >= 0 ? _mix(rgb, 0xFFFFFF, tint) : _mix(rgb, 0, -tint);
      final trimS = realStart ? min(pow(_rnd(j, 4), 1.5) * sw * .55 * edge, trimCap) : 0.0;
      final trimE = realEnd ? min(pow(_rnd(j, 5), 1.5) * sw * .55 * edge, trimCap) : 0.0;
      final px = <double>[], py = <double>[], ph = <double>[], pc = <int>[];
      final phase = _rnd(j, 7) * 2 * pi;
      for (var i = 0; i < m; i++) {
        if (arc[i] < trimS || arc[i] > total - trimE) continue;
        final off = ef(i, off0 + sin(arc[i] / (sw * .8) + phase) * hw * .03);
        final qx = sx[i] + nx[i] * off, qy = sy[i] + ny[i] * off;
        // la tira solo avanza: un punto que retrocede (o casi no avanza) en la dirección de la tangente se descarta
        if (px.isNotEmpty && (qx - px.last) * stx[i] + (qy - py.last) * sty[i] <= .2) continue;
        px.add(qx);
        py.add(qy);
        ph.add(hb);
        // la punta se desvanece en los últimos pasos: queda desflecada
        final fadeS = realStart ? ((arc[i] - trimS) / (sw * .25)).clamp(0.0, 1.0) : 1.0;
        final fadeE = realEnd ? ((total - trimE - arc[i]) / (sw * .25)).clamp(0.0, 1.0) : 1.0;
        pc.add(argb(al * (.35 + .65 * min(fadeS, fadeE)), c));
      }
      if (px.length >= 2) _stripDedupe(w, px, py, ph, pc, round: false, feather: feather);
    }
  } else if (bgOn) {
    // resaltador: plano, translúcido, bordes limpios y extremos rectos; fibra: sólida y pareja, extremos redondeados
    final marker = pp.style == 'marker';
    final col = argb(marker ? min(1.0, s.o + .1) : s.o * .55, rgb);
    int? prev;
    for (var i = 0; i < m; i++) {
      final l = w.v(sx[i] + nx[i] * ef(i, hw), sy[i] + ny[i] * ef(i, hw), col);
      w.v(sx[i] + nx[i] * ef(i, -hw), sy[i] + ny[i] * ef(i, -hw), col);
      if (prev != null) w.quad(prev, prev + 1, l + 1, l);
      prev = l;
    }
    if (marker) {
      if (realStart) _semi(w, sx[0], sy[0], nx[0], ny[0], -stx[0], -sty[0], hw, col);
      if (realEnd) _semi(w, sx[m - 1], sy[m - 1], nx[m - 1], ny[m - 1], stx[m - 1], sty[m - 1], hw, col);
    }
  }

  // punto de la franja a [u] de arco y [v] de lado (v en -hw..hw), con el mismo recorte de curvatura que las cerdas
  (double, double) at(double u, double v) {
    var lo = 1, hi = m - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (arc[mid] < u) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final i = lo;
    final seg = arc[i] - arc[i - 1], t = seg <= 0 ? 0.0 : ((u - arc[i - 1]) / seg).clamp(0.0, 1.0);
    final e0 = ef(i - 1, v), e1 = ef(i, v);
    final x0 = sx[i - 1] + nx[i - 1] * e0, y0 = sy[i - 1] + ny[i - 1] * e0;
    final x1 = sx[i] + nx[i] * e1, y1 = sy[i] + ny[i] * e1;
    return (x0 + (x1 - x0) * t, y0 + (y1 - y0) * t);
  }

  // b) brillo: puntitos aclarados (la mayoría) y algunos oscurecidos, ~1 cada 80 u² de franja con el brillo en .5.
  // Se recorre el arco en celdas de largo fijo y cada celda lleva su cantidad con semilla (parte, celda): lo ya
  // dibujado no cambia al seguir dibujando.
  if (pp.glitter > 0) {
    final cl = max(sw * .5, total / 20000);
    final lambda = cl * sw / 80 * pp.glitter * 2;
    for (var k = 0; k * cl < total && w.count < maxV - 8; k++) {
      final cell = (a * 7919 + k) * 257;
      final cnt = (lambda + _rnd(cell, 9)).floor();
      for (var t = 0; t < cnt && w.count < maxV - 8; t++) {
        final h = cell + t + 1;
        final u = (k + _rnd(h, 10)) * cl;
        if (u > total) continue;
        final (x, y) = at(u, (_rnd(h, 11) * 2 - 1) * hw * .95);
        final r = 1 + 1.5 * _rnd(h, 12);
        final dark = _rnd(h, 13) < .3;
        final col = dark
            ? argb(s.o * (.3 + .3 * _rnd(h, 14)), _mix(rgb, 0, .35))
            : argb(s.o * (.5 + .4 * _rnd(h, 14)), _mix(rgb, 0xFFFFFF, .65));
        _circle(w, x, y, r, col, 6);
      }
    }
  }

  // c) formas repartidas dentro de la franja: color propio (o claro/oscuro del fondo), cantidad y tamaño ajustables
  if (showShapes) {
    final step = sw * (1.4 - 1.2 * pp.density);
    var u = total < step ? total / 2 : step * .4;
    final sc = pp.shapeColor;
    for (var k = 0; u <= total && w.count < maxV - 100; k++, u += step * (.75 + .5 * _rnd(salt + k, 20))) {
      final r = min(sw * (.1 + .3 * pp.size) * (.6 + .8 * _rnd(salt + k, 21)), hw * .95);
      final v = (_rnd(salt + k, 22) * 2 - 1) * max(0.0, hw - r * 1.1);
      final (x, y) = at(u, v);
      final id = s.k.substring(6);
      final col = argb(s.o * (_whiteShapes.contains(id) ? .75 : .85), _shapeRgb(sc, rgb, _defaultShapeRgb(id, rgb)));
      paintShape(w, id, x, y, r, _rnd(salt + k, 23) * 2 * pi, col);
    }
  }
  return w.done();
}

/// Número pseudoaleatorio estable en [0, 1) a partir de dos enteros (hash de bits, sin Random).
double _rnd(int i, int salt) {
  var x = (i * 374761393 + salt * 668265263) & 0xFFFFFFFF;
  x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0xFFFFFFFF;
  x = ((x ^ (x >> 16)) * 0x45d9f3b) & 0xFFFFFFFF;
  x ^= x >> 16;
  return x / 4294967296.0;
}

/// Formas que por defecto van en blanco; las de [_goldShapes] en dorado oscuro y el resto en el fondo aclarado.
const _whiteShapes = {'stars', 'sparkles', 'dots', 'circles', 'bangs', 'clouds', 'bubbles'};
const _goldShapes = {'moons', 'bolts', 'ticks', 'crosses'};
int _defaultShapeRgb(String id, int rgb) =>
    _whiteShapes.contains(id) ? 0xFFFFFF : _mix(rgb, _goldShapes.contains(id) ? 0x8a6a2a : 0xFFFFFF, .55);

/// Color de las formas: [sc] es null (el de la forma por defecto, [def]), 'light' / 'dark' (el fondo [rgb] aclarado u
/// oscurecido) o un hex '#rrggbb'.
int _shapeRgb(String? sc, int rgb, int def) => switch (sc) {
      null => def,
      'light' => _mix(rgb, 0xFFFFFF, .6),
      'dark' => _mix(rgb, 0, .35),
      _ => parseColor(sc).toARGB32() & 0x00FFFFFF,
    };

/// Mezcla el color [rgb] hacia [to] (ambos 0xRRGGBB) una fracción [t].
int _mix(int rgb, int to, double t) {
  int ch(int sh) => (((rgb >> sh) & 255) * (1 - t) + ((to >> sh) & 255) * t).round().clamp(0, 255);
  return ch(16) << 16 | ch(8) << 8 | ch(0);
}

/// Variación de alfa del lápiz por vértice: pseudoaleatoria pero estable (depende solo del índice global del punto),
/// entre [_grainLo] y [_grainHi] (se probó: más variación aleja al lápiz del dibujo viejo en la métrica del test).
const double _grainLo = .85, _grainHi = 1.15;
double _grain(int i, int salt) {
  final h = ((i * 7919 + salt * 104729) * 2654435761 >> 7) % 1021;
  return _grainLo + (_grainHi - _grainLo) * h / 1020;
}

/// Curva del trazo suave: pasa por los puntos medios con los puntos como control (como el `Path` viejo).
void _smoothCenterline(List<double> p, List<double> xs, List<double> ys, {int maxSteps = 8}) {
  final n = p.length ~/ 2;
  xs.add(p[0]);
  ys.add(p[1]);
  if (n == 1) return;
  var cx = p[0], cy = p[1]; // desde dónde sale el tramo
  for (var i = 1; i < n - 1; i++) {
    final qx = p[i * 2], qy = p[i * 2 + 1];
    final ex = (qx + p[i * 2 + 2]) / 2, ey = (qy + p[i * 2 + 3]) / 2;
    final len = (qx - cx).abs() + (qy - cy).abs() + (ex - qx).abs() + (ey - qy).abs();
    final steps = (len / 5).ceil().clamp(1, maxSteps);
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

class _W implements ShapeSink {
  final bool colored;
  final pos = <double>[];
  final idx = <int>[];
  final cols = <int>[];
  _W(this.colored);

  @override
  int get count => pos.length >> 1;
  @override
  int v(double x, double y, [int c = 0]) {
    pos
      ..add(x)
      ..add(y);
    if (colored) cols.add(c);
    return count - 1;
  }

  @override
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

/// Círculo (abanico) de [steps] lados. Con [feather] > 0 (y colores por vértice) el borde es un anillo de alfa 0.
void _circle(_W w, double cx, double cy, double r, int col, int steps, {double feather = 0}) {
  if (feather > 0 && w.colored) {
    final rc = max(r - feather / 2, r * .3), ro = r + feather / 2, c0 = col & 0x00FFFFFF;
    final c = w.v(cx, cy, col);
    final inner = w.count, outer = inner + steps;
    for (var k = 0; k < steps; k++) {
      final a = 2 * pi * k / steps;
      w.v(cx + rc * cos(a), cy + rc * sin(a), col);
    }
    for (var k = 0; k < steps; k++) {
      final a = 2 * pi * k / steps;
      w.v(cx + ro * cos(a), cy + ro * sin(a), c0);
    }
    for (var k = 0; k < steps; k++) {
      final k1 = (k + 1) % steps;
      w.tri(c, inner + k, inner + k1);
      w.quad(inner + k, outer + k, outer + k1, inner + k1);
    }
    return;
  }
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
    _circle(w, xs[0], ys[0], hs[0], cs?[0] ?? 0, 16, feather: cs == null ? 0 : feather);
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
      _circle(w, x[i], y[i], hw[i], colAt(i), 10, feather: fe ? feather : 0);
      prev = pair(i, -dy[i], dx[i], 1);
    }
  }
  join(prev, pair(m - 1, -dy[m - 2], dx[m - 2], 1));
  if (round) _semi(w, x[m - 1], y[m - 1], -dy[m - 2], dx[m - 2], dx[m - 2], dy[m - 2], hw[m - 1], colAt(m - 1));
}
