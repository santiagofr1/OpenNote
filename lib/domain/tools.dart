import '../l10n/app_localizations.dart';
import 'elements.dart';
import 'stroke.dart';

enum Tool { pen, hl, paint, shape, text, select, title }

/// Puntas del lápiz (id guardado en el trazo, nombre en pantalla).
final tips = <(String, String Function(L))>[
  ('pen', (l) => l.tipPen),
  ('fountain', (l) => l.tipFountain),
  ('pencil', (l) => l.tipPencil),
  ('fine', (l) => l.tipFine),
  ('calli', (l) => l.tipCalligraphy),
];

/// Tipos de trazo de la pintura (id guardado en `pp.st`, nombre en pantalla).
final paintStyles = <(String, String Function(L))>[
  ('brush', (l) => l.paintStyleBrush),
  ('hl', (l) => l.paintStyleHighlighter),
  ('marker', (l) => l.paintStyleMarker),
];

/// Formas de la pintura decorativa (id guardado en el trazo, nombre en pantalla).
final paintShapes = <(String, String Function(L))>[
  ('paint-stars', (l) => l.paintShapeStars),
  ('paint-hearts', (l) => l.paintShapeHearts),
  ('paint-sparkles', (l) => l.paintShapeSparkles),
  ('paint-moons', (l) => l.paintShapeMoons),
  ('paint-dots', (l) => l.paintShapeDots),
  ('paint-circles', (l) => l.paintShapeCircles),
  ('paint-bangs', (l) => l.paintShapeExclamations),
  ('paint-bolts', (l) => l.paintShapeBolts),
  ('paint-ticks', (l) => l.paintShapeTicks),
  ('paint-crosses', (l) => l.paintShapeCrosses),
  ('paint-clouds', (l) => l.paintShapeClouds),
  ('paint-bubbles', (l) => l.paintShapeBubbles),
  ('paint-leaves', (l) => l.paintShapeLeaves),
  ('paint-paws', (l) => l.paintShapePaws),
  ('paint-triangles', (l) => l.paintShapeTriangles),
  ('paint-squares', (l) => l.paintShapeSquares),
  ('paint-diamonds', (l) => l.paintShapeDiamonds),
  ('paint-flowers', (l) => l.paintShapeFlowers),
  ('paint-notes', (l) => l.paintShapeNotes),
];

/// Formas exactas (id guardado en prefs, nombre en pantalla).
final shapeKinds = <(String, String Function(L))>[
  ('line', (l) => l.shapeKindLine),
  ('arrow', (l) => l.shapeKindArrow),
  ('rect', (l) => l.shapeKindRectangle),
  ('circle', (l) => l.shapeKindCircle),
  ('ellipse', (l) => l.shapeKindEllipse),
  ('triangle', (l) => l.shapeKindTriangle),
];

/// Radio de la goma: chica, mediana, grande.
const eraserSizes = [8.0, 16.0, 30.0];

class PenPreset {
  String tip, color;
  double width, opacity;
  PenPreset(this.tip, this.color, this.width, this.opacity);
  Map<String, dynamic> toJson() => {'tip': tip, 'color': color, 'width': width, 'opacity': opacity};
  /// Lee un lápiz guardado. Los valores de otro tipo o fuera de rango se ignoran / acotan: cargar los ajustes nunca tira.
  void load(Object? j) {
    if (j is! Map) return;
    if (j['tip'] is String) tip = j['tip'] as String;
    if (j['color'] is String) color = j['color'] as String;
    final w = j['width'];
    if (w is num && w.isFinite) width = w.toDouble().clamp(.1, 200.0);
    final o = j['opacity'];
    if (o is num && o.isFinite) opacity = o.toDouble().clamp(0.0, 1.0);
  }
}

/// Lo copiado de una selección. Vive en [ToolState] para poder pegar en otra página.
class SelectionClipboard {
  List<Stroke> strokes = [];
  List<TextBlock> texts = [];
  List<Item> items = [];
  bool get isEmpty => strokes.isEmpty && texts.isEmpty && items.isEmpty;
}

/// Herramientas elegidas (se guardan en prefs.json)
class ToolState {
  Tool tool = Tool.pen;
  final pen = PenPreset('pen', '#22211e', 2.6, 1);
  final hl = PenPreset('hl', '#f7d22c', 22, .4);
  final paint = PenPreset('paint-stars', '#f4a7c3', 34, .85);
  PaintParams paintParams = const PaintParams(); // brillo, formitas (color, cantidad, tamaño) de la pintura
  List<String> penRecent = ['#22211e', '#1d4ed8', '#b91c1c', '#15803d', '#c2410c', '#7e22ce'];
  List<String> hlRecent = ['#f7d22c', '#5ee08a', '#ff86c8', '#5bc8ff'];
  List<String> paintRecent = ['#f4a7c3', '#8fd8e0', '#e3cfa0', '#c9b3ec'];
  // Los 4 colores favoritos de la barra: fijos (elegirlos no los reordena), se cambian a mano.
  List<String> penFav = ['#22211e', '#1d4ed8', '#b91c1c', '#15803d'];
  List<String> hlFav = ['#f7d22c', '#5ee08a', '#ff86c8', '#5bc8ff'];
  List<String> paintFav = ['#f4a7c3', '#8fd8e0', '#e3cfa0', '#c9b3ec'];
  static const kFavCount = 4;
  int eraserSize = 1;
  String dock = 'top'; // top | left | right
  double zoom = 1; // 1 = la hoja entra justa a lo ancho
  bool zoomLocked = false;
  bool shapeSnap = true; // figuras inteligentes: lápiz quieto al final del trazo lo vuelve figura limpia
  // herramienta de formas: el borde usa el color, grosor y opacidad del lápiz
  String shapeKind = 'line'; // ver [shapeKinds]
  bool shapeFill = false; // relleno con color (solo formas cerradas)
  String shapeFillColor = '#93c5fd';
  bool shapeGrid = true; // pegar a la cuadrícula del fondo
  bool exportBackground = true; // exportar con el fondo de la hoja (papel, rayado, imagen) o solo lo escrito
  final clipboard = SelectionClipboard(); // no se guarda

  bool get drawing => tool == Tool.pen || tool == Tool.hl || tool == Tool.paint || tool == Tool.shape;
  PenPreset get current => switch (tool) { Tool.hl => hl, Tool.paint => paint, _ => pen };
  List<String> get recent => switch (tool) { Tool.hl => hlRecent, Tool.paint => paintRecent, _ => penRecent };
  List<String> get favorites => switch (tool) { Tool.hl => hlFav, Tool.paint => paintFav, _ => penFav };
  double get eraserRadius => eraserSizes[eraserSize];

  /// Reloj (los tests lo reemplazan para avanzar el tiempo).
  static DateTime Function() clock = DateTime.now;
  ({String prev, String now, Tool tool, DateTime at})? _lastPick; // último cambio de color hecho por [pickColor]

  /// Elige un color y lo pone primero en "recientes" (hasta 7).
  void pickColor(String c) {
    if (c != current.color) _lastPick = (prev: current.color, now: c, tool: tool, at: clock());
    current.color = c;
    _remember(recent, c);
  }

  /// Guarda un color en un lugar de los favoritos de la herramienta actual (puede repetirse).
  void setFavorite(int slot, String c) {
    if (slot >= 0 && slot < kFavCount) favorites[slot] = c;
  }

  /// Guarda el color actual de la herramienta en un favorito. Devuelve si cambió algo (ya estaba ahí: no).
  /// Un toque que cae justo antes del mantener apretado sobre el mismo favorito (pasa con el S Pen / el dedo en la
  /// tablet) no debe tragarse el color que el usuario quería guardar: se deshace ese toque y se guarda el color anterior.
  bool saveFavorite(int slot) {
    final r = _lastPick;
    _lastPick = null;
    if (r != null && r.tool == tool && current.color == r.now && slot >= 0 && slot < kFavCount && favorites[slot] == r.now &&
        clock().difference(r.at) <= const Duration(seconds: 2) && r.prev != r.now) {
      current.color = r.prev;
      _remember(recent, r.prev);
    }
    if (slot < 0 || slot >= kFavCount || favorites[slot] == current.color) return false;
    favorites[slot] = current.color;
    return true;
  }

  static List<String> _favs(Object? v, List<String> def) {
    if (v is List && v.length == kFavCount && v.every((e) => e is String && e.startsWith('#'))) {
      return List<String>.from(v);
    }
    return List<String>.from(def);
  }

  /// Lista de colores recientes: solo textos, sin repetidos y hasta 7; si no es una lista, se deja [def].
  static List<String> _recents(Object? v, List<String> def) {
    if (v is! List) return def;
    final out = <String>[];
    for (final e in v) {
      if (e is String && !out.contains(e) && out.length < 7) out.add(e);
    }
    return out;
  }

  static void _remember(List<String> r, String c) {
    r..remove(c)..insert(0, c);
    if (r.length > 7) r.removeLast();
  }

  /// Al cerrar el panel del Decorador: el color de las formas (si es un hex propio) entra a "recientes".
  void rememberShapeColor() {
    final c = paintParams.shapeColor;
    if (c != null && c.startsWith('#')) _remember(paintRecent, c);
  }

  Map<String, dynamic> toJson() => {
        'tool': tool.name,
        'pen': pen.toJson(),
        'hl': hl.toJson(),
        'paint': paint.toJson(),
        'paintParams': paintParams.toJson(),
        'penRecent': penRecent,
        'hlRecent': hlRecent,
        'paintRecent': paintRecent,
        'penFav': penFav,
        'hlFav': hlFav,
        'paintFav': paintFav,
        'eraserSize': eraserSize,
        'dock': dock,
        'zoom': zoom,
        'zoomLocked': zoomLocked,
        'shapeSnap': shapeSnap,
        'shapeKind': shapeKind,
        'shapeFill': shapeFill,
        'shapeFillColor': shapeFillColor,
        'shapeGrid': shapeGrid,
        'exportBg': exportBackground,
      };

  void load(Map? j) {
    if (j == null) return;
    tool = Tool.values.firstWhere((t) => t.name == j['tool'], orElse: () => Tool.pen);
    pen.load(j['pen']);
    hl.load(j['hl']);
    paint.load(j['paint']);
    paintParams = j['paintParams'] is Map ? PaintParams.fromJson(j['paintParams'] as Map) : const PaintParams();
    if (paint.tip == 'paint-none') {
      // la vieja opción "Ninguna" ahora es tener las formas apagadas
      paint.tip = 'paint-stars';
      paintParams = paintParams.copyWith(shapes: false);
    }
    if (!isPaint(paint.tip)) paint.tip = 'paint-stars'; // una forma que ya no existe
    penRecent = _recents(j['penRecent'], penRecent);
    hlRecent = _recents(j['hlRecent'], hlRecent);
    paintRecent = _recents(j['paintRecent'], paintRecent);
    penFav = _favs(j['penFav'], penFav);
    hlFav = _favs(j['hlFav'], hlFav);
    paintFav = _favs(j['paintFav'], paintFav);
    final es = j['eraserSize'];
    eraserSize = es is num && es.isFinite ? es.round().clamp(0, 2) : 1;
    if (const ['top', 'left', 'right'].contains(j['dock'])) dock = j['dock'] as String;
    final z = j['zoom'];
    zoom = z is num && z.isFinite ? z.toDouble().clamp(.5, 4.0) : 1.0;
    zoomLocked = j['zoomLocked'] is bool ? j['zoomLocked'] as bool : false;
    shapeSnap = j['shapeSnap'] is bool ? j['shapeSnap'] as bool : true;
    if (shapeKinds.any((k) => k.$1 == j['shapeKind'])) shapeKind = j['shapeKind'] as String;
    shapeFill = j['shapeFill'] is bool ? j['shapeFill'] as bool : false;
    final fc = j['shapeFillColor'];
    if (fc is String && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(fc)) shapeFillColor = fc;
    shapeGrid = j['shapeGrid'] is bool ? j['shapeGrid'] as bool : true;
    exportBackground = j['exportBg'] is bool ? j['exportBg'] as bool : true;
  }
}
