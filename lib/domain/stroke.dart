import 'dart:math';
import 'dart:ui';

import 'geometry.dart';
import 'stroke_mesh.dart';
import 'values.dart';
import 'z_order.dart';

/// Trazo: puntos guardados planos como [x, y, presión, x, y, presión, ...]
class Stroke extends Layered {
  // k = punta: pen | fountain | pencil | fine | calli | hl | pinceles de diseño (dots | stars | hearts | flowers | scallop)
  @override
  final String id;
  final String k, c;
  final double w, o; // grosor y opacidad (0..1)
  final List<double> pts;
  late final Color color = parseColor(c);
  Rect? _bounds;

  Stroke(this.id, this.k, this.c, this.w, this.pts, [this.o = 1]);

  /// Malla de triángulos del trazo (ver stroke_mesh.dart): se arma una vez (en el isolate al cargar la hoja, o al
  /// primer dibujo) y se descarta en [invalidate]. [batchCache] es el lote de trazos que el painter arma con éste
  /// como primero (opaco para el dominio).
  StrokeMesh? mesh;
  NativeHandle? batchCache;
  int meshGen = 0;

  /// La malla, calculándola si hace falta (null si no hay puntos).
  StrokeMesh? ensureMesh() => mesh ??= buildStrokeMesh(this);

  /// Suelta la malla y lo que se armó con ella (al descargar la hoja o al cambiar el trazo).
  void releaseMesh() {
    mesh?.dispose();
    mesh = null;
    batchCache?.dispose();
    batchCache = null;
  }

  /// Hay que llamarlo después de tocar [pts] (el rectángulo y la malla se cachean).
  void invalidate() {
    _bounds = null;
    meshGen++;
    releaseMesh();
  }

  int get n => pts.length ~/ 3;

  Rect get bounds {
    if (_bounds != null) return _bounds!;
    double x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9;
    for (var i = 0; i < pts.length; i += 3) {
      x0 = min(x0, pts[i]);
      x1 = max(x1, pts[i]);
      y0 = min(y0, pts[i + 1]);
      y1 = max(y1, pts[i + 1]);
    }
    final r = w * 1.6; // cubre también las formas de los pinceles de diseño (radio w * kDesignRadius)
    return _bounds = Rect.fromLTRB(x0 - r, y0 - r, x1 + r, y1 + r);
  }

  /// Copia corrida [d] (con otro [id] si se pega o duplica).
  Stroke moved(Offset d, {String? id}) {
    final p = List<double>.of(pts);
    for (var i = 0; i < p.length; i += 3) {
      p[i] += d.dx;
      p[i + 1] += d.dy;
    }
    return Stroke(id ?? this.id, k, c, w, p, o)..z = z;
  }

  /// Copia transformada por [t] (con otro [id] si hace falta): todos los puntos, y el grosor se multiplica por la escala.
  Stroke transformed(Xform t, {String? id}) {
    if (t.isMove) return moved(t.shift, id: id);
    final p = List<double>.of(pts);
    for (var i = 0; i < p.length; i += 3) {
      final q = t.apply(Offset(p[i], p[i + 1]));
      p[i] = q.dx;
      p[i + 1] = q.dy;
    }
    return Stroke(id ?? this.id, k, c, w * t.scale, p, o)..z = z;
  }

  /// Cuánto se aleja la tinta de la línea central: la mitad del grosor, o el radio de la forma en los diseños.
  double get _reach => isDesignTip(k) ? w * kDesignRadius : w / 2;

  /// ¿El trazo toca el rectángulo [r]? Real: algún tramo del recorrido, engordado la mitad del grosor,
  /// cruza el rectángulo (no alcanza con que se superpongan los rectángulos que envuelven).
  bool touchesRect(Rect r) {
    if (!bounds.overlaps(r)) return false;
    final g = r.inflate(_reach), p = pts;
    if (n == 1) return g.contains(Offset(p[0], p[1]));
    for (var i = 1; i < n; i++) {
      if (segmentIntersectsRect(Offset(p[i * 3 - 3], p[i * 3 - 2]), Offset(p[i * 3], p[i * 3 + 1]), g)) return true;
    }
    return false;
  }

  /// Corre el trazo [dy] hacia abajo, en el lugar (lo usan las operaciones de hojas).
  /// La malla (si ya está armada, p. ej. en el isolate de carga, en coordenadas de la hoja) se corre igual en vez
  /// de recalcularse.
  void translateY(double dy) {
    for (var i = 1; i < pts.length; i += 3) {
      pts[i] += dy;
    }
    final m = mesh;
    invalidate();
    if (m != null) {
      for (final p in m.parts) {
        for (var i = 1; i < p.pos.length; i += 2) {
          p.pos[i] += dy;
        }
      }
      mesh = m;
    }
  }

  /// ¿La goma de radio [r] en [pt] toca este trazo?
  bool hitBy(Offset pt, double r) {
    if (!bounds.inflate(r).contains(pt)) return false;
    final lim = r + (isDesignTip(k) ? _reach : w * .75), p = pts;
    if (n == 1) return (Offset(p[0], p[1]) - pt).distance < lim;
    for (var i = 1; i < n; i++) {
      if (distToSegment(pt, Offset(p[i * 3 - 3], p[i * 3 - 2]), Offset(p[i * 3], p[i * 3 + 1])) < lim) return true;
    }
    return false;
  }

  /// Promedio con los vecinos: saca el temblequeo sin deformar. La presión no se toca.
  void smooth() {
    if (n < 4) return;
    final c = List<double>.of(pts);
    for (var i = 1; i < n - 1; i++) {
      for (var k = 0; k < 2; k++) {
        pts[i * 3 + k] = (c[(i - 1) * 3 + k] + 2 * c[i * 3 + k] + c[(i + 1) * 3 + k]) / 4;
      }
    }
    invalidate();
  }

  factory Stroke.fromJson(Map j) => Stroke(
        j['id'] as String,
        (j['k'] ?? 'pen') as String,
        (j['c'] ?? '#22211e') as String,
        jsonDouble(j['w'], 2),
        [
          for (final p in (j['pts'] as List))
            ...[jsonDouble(p[0]), jsonDouble(p[1]), (p as List).length > 2 ? jsonDouble(p[2], .5) : .5]
        ],
        jsonDouble(j['o'], 1),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'k': k,
        'c': c,
        'w': w,
        if (o < 1) 'o': round2(o),
        'pts': [
          for (var i = 0; i < pts.length; i += 3) [round1(pts[i]), round1(pts[i + 1]), round2(pts[i + 2])]
        ],
      };
}
