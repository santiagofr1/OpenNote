import 'dart:math';
import 'dart:ui';

import 'geometry.dart';
import 'paint_shapes.dart';
import 'stroke_mesh.dart';
import 'values.dart';
import 'z_order.dart';

/// ¿[k] es una pintura decorativa (`paint-<forma>`, ver [paintShapeIds])?
bool isPaint(String k) => k.startsWith('paint-') && paintShapeIds.contains(k.substring(6));

/// Punta del corrector que la goma pinta sobre un PDF: trazo opaco de ancho constante (sin presión) y extremos redondos.
const kCoverTip = 'cover';

/// Lo que se dibuja debajo de la tinta de su tanda: resaltador y pintura.
bool isUnderInk(String k) => k == 'hl' || isPaint(k);

/// Resaltador: se compone multiplicando con lo de abajo (el texto de un PDF queda encima).
bool isHighlighter(String k) => k == 'hl';

/// Tipos de trazo de la pintura: pincel seco, resaltador (franja plana translúcida) y fibra (franja sólida pareja).
const paintStyleIds = ['brush', 'hl', 'marker'];

/// Ajustes de una franja de pintura (van en `pp` del trazo; valores 0..1, faltantes = valor por defecto).
class PaintParams {
  final double glitter, density, size; // brillo, cantidad de formas, tamaño de formas
  final String? shapeColor; // null: según la forma; 'light' / 'dark': el fondo aclarado / oscurecido; '#rrggbb'
  final String style; // 'brush' | 'hl' | 'marker' (ver [paintStyleIds])
  final bool bg, shapes; // franja de fondo prendida / formas prendidas (al menos una de fondo, formas o brillo)
  const PaintParams({
    this.glitter = .5,
    this.density = .5,
    this.size = .5,
    this.shapeColor,
    this.style = 'brush',
    this.bg = true,
    this.shapes = true,
  });

  factory PaintParams.fromJson(Map j) => PaintParams(
        glitter: jsonDouble(j['g'], .5).clamp(0.0, 1.0),
        density: jsonDouble(j['sd'], .5).clamp(0.0, 1.0),
        size: jsonDouble(j['ss'], .5).clamp(0.0, 1.0),
        shapeColor: j['sc'] is String ? j['sc'] as String : null,
        style: j['st'] is String && paintStyleIds.contains(j['st']) ? j['st'] as String : 'brush',
        bg: j['bg'] is bool ? j['bg'] as bool : true,
        shapes: j['sh'] is bool ? j['sh'] as bool : true,
      );

  /// Copia con cambios; [autoColor] borra el color de las formas (null no alcanza para eso).
  PaintParams copyWith({
    double? glitter,
    double? density,
    double? size,
    String? shapeColor,
    bool autoColor = false,
    String? style,
    bool? bg,
    bool? shapes,
  }) =>
      PaintParams(
        glitter: glitter ?? this.glitter,
        density: density ?? this.density,
        size: size ?? this.size,
        shapeColor: autoColor ? null : (shapeColor ?? this.shapeColor),
        style: style ?? this.style,
        bg: bg ?? this.bg,
        shapes: shapes ?? this.shapes,
      );

  Map<String, dynamic> toJson() => {
        'g': round2(glitter),
        'sd': round2(density),
        'ss': round2(size),
        if (shapeColor != null) 'sc': shapeColor,
        if (style != 'brush') 'st': style,
        if (!bg) 'bg': false,
        if (!shapes) 'sh': false,
      };

  @override
  bool operator ==(Object other) =>
      other is PaintParams &&
      other.glitter == glitter &&
      other.density == density &&
      other.size == size &&
      other.shapeColor == shapeColor &&
      other.style == style &&
      other.bg == bg &&
      other.shapes == shapes;
  @override
  int get hashCode => Object.hash(glitter, density, size, shapeColor, style, bg, shapes);
}

/// Trazo: puntos guardados planos como [x, y, presión, x, y, presión, ...]
class Stroke extends Layered {
  // k = punta: pen | fountain | pencil | fine | calli | hl | cover | pintura (paint-<forma>)
  @override
  final String id;
  final String k, c;
  final double w, o; // grosor y opacidad (0..1)
  final List<double> pts;
  final PaintParams? pp; // ajustes de la pintura (null en los demás trazos)
  final String? fill; // relleno de una forma exacta ('#rrggbb'); null: sin relleno
  late final Color color = parseColor(c);
  Rect? _bounds;
  Path? _fillPath;

  Stroke(this.id, this.k, this.c, this.w, this.pts, [this.o = 1, this.pp, this.fill]);

  /// Polígono cerrado de los puntos (para el relleno), cacheado hasta [invalidate].
  Path get fillPath {
    final cached = _fillPath;
    if (cached != null) return cached;
    return _fillPath = Path()
      ..addPolygon([for (var i = 0; i + 1 < pts.length; i += 3) Offset(pts[i], pts[i + 1])], true);
  }

  /// Malla de triángulos del trazo (ver stroke_mesh.dart): se arma una vez (en el isolate al cargar la hoja, o al
  /// primer dibujo) y se descarta en [invalidate]. [batchCache] es el lote de trazos que el painter arma con éste
  /// como primero (opaco para el dominio).
  StrokeMesh? mesh;
  NativeHandle? batchCache;
  int meshGen = 0;

  /// La malla, calculándola si hace falta (null si no hay puntos).
  /// Si el borde difuminado vigente ([meshFeather]) cambió desde que se armó, se rehace (y se suelta el lote).
  StrokeMesh? ensureMesh() {
    final m = mesh;
    if (m != null && (m.feather == meshFeather)) return m;
    if (m != null) releaseMesh();
    return mesh = buildStrokeMesh(this);
  }

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
    _fillPath = null;
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
    final r = w * 1.6; // cubre la franja de pintura (ancho w) con sus puntas
    return _bounds = Rect.fromLTRB(x0 - r, y0 - r, x1 + r, y1 + r);
  }

  /// Copia corrida [d] (con otro [id] si se pega o duplica).
  Stroke moved(Offset d, {String? id}) {
    final p = List<double>.of(pts);
    for (var i = 0; i < p.length; i += 3) {
      p[i] += d.dx;
      p[i + 1] += d.dy;
    }
    return Stroke(id ?? this.id, k, c, w, p, o, pp, fill)..z = z;
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
    return Stroke(id ?? this.id, k, c, w * t.scale, p, o, pp, fill)..z = z;
  }

  /// Cuánto se aleja la tinta de la línea central: la mitad del grosor (un poco más en la pintura, por el desflecado).
  double get _reach => isPaint(k) ? w * .55 : w / 2;

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
    final lim = r + w * .75, p = pts;
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
        j['pp'] is Map ? PaintParams.fromJson(j['pp'] as Map) : null,
        j['f'] is String ? j['f'] as String : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'k': k,
        'c': c,
        'w': w,
        if (o < 1) 'o': round2(o),
        if (pp != null) 'pp': pp!.toJson(),
        if (fill != null) 'f': fill,
        'pts': [
          for (var i = 0; i < pts.length; i += 3) [round1(pts[i]), round1(pts[i + 1]), round2(pts[i + 2])]
        ],
      };
}
