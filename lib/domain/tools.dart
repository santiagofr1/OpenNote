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
  // Colores favoritos de la barra (1 a [kFavMax]): lugares editables; el elegido ([penFavSel]...) sigue al color de la herramienta.
  List<String> penFav = ['#22211e', '#1d4ed8', '#b91c1c', '#15803d'];
  List<String> hlFav = ['#f7d22c', '#5ee08a', '#ff86c8', '#5bc8ff'];
  List<String> paintFav = ['#f4a7c3', '#8fd8e0', '#e3cfa0', '#c9b3ec'];
  static const kFavMax = 8;
  int penFavSel = 0, hlFavSel = 0, paintFavSel = 0; // favorito elegido de cada herramienta (-1 = ninguno)
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
  List<String> get favorites => switch (tool) { Tool.hl => hlFav, Tool.paint => paintFav, _ => penFav };
  double get eraserRadius => eraserSizes[eraserSize];

  /// Favorito elegido de la herramienta actual (-1 = ninguno).
  int get favSel => switch (tool) { Tool.hl => hlFavSel, Tool.paint => paintFavSel, _ => penFavSel };
  set favSel(int v) {
    switch (tool) {
      case Tool.hl:
        hlFavSel = v;
      case Tool.paint:
        paintFavSel = v;
      default:
        penFavSel = v;
    }
  }

  /// Elige el favorito [i]: queda elegido y su color pasa a ser el de la herramienta.
  void useFavorite(int i) {
    if (i < 0 || i >= favorites.length) return;
    favSel = i;
    current.color = favorites[i];
  }

  /// Cambia el color de la herramienta; el favorito elegido (si hay) lo sigue.
  void setColor(String c) {
    current.color = c;
    if (favSel >= 0 && favSel < favorites.length) favorites[favSel] = c;
  }

  /// Suma el color actual como favorito nuevo (queda elegido). Falso si ya están los [kFavMax].
  bool addFavorite() {
    if (favorites.length >= kFavMax) return false;
    favorites.add(current.color);
    favSel = favorites.length - 1;
    return true;
  }

  /// Borra el favorito [i] (siempre queda al menos uno). Falso si no se pudo.
  bool removeFavorite(int i) {
    if (favorites.length <= 1 || i < 0 || i >= favorites.length) return false;
    favorites.removeAt(i);
    if (favSel == i) {
      favSel = -1;
    } else if (favSel > i) {
      favSel--;
    }
    return true;
  }

  static List<String> _favs(Object? v, List<String> def) {
    if (v is List && v.isNotEmpty && v.length <= kFavMax && v.every((e) => e is String && e.startsWith('#'))) {
      return List<String>.from(v);
    }
    return List<String>.from(def);
  }

  /// Favorito elegido guardado si es un índice válido; si no, el que tenga el color de la herramienta (o -1).
  static int _sel(Object? v, List<String> favs, String color) => v is int && v >= 0 && v < favs.length ? v : favs.indexOf(color);

  Map<String, dynamic> toJson() => {
        'tool': tool.name,
        'pen': pen.toJson(),
        'hl': hl.toJson(),
        'paint': paint.toJson(),
        'paintParams': paintParams.toJson(),
        'penFav': penFav,
        'hlFav': hlFav,
        'paintFav': paintFav,
        'penFavSel': penFavSel,
        'hlFavSel': hlFavSel,
        'paintFavSel': paintFavSel,
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
    penFav = _favs(j['penFav'], penFav);
    hlFav = _favs(j['hlFav'], hlFav);
    paintFav = _favs(j['paintFav'], paintFav);
    penFavSel = _sel(j['penFavSel'], penFav, pen.color);
    hlFavSel = _sel(j['hlFavSel'], hlFav, hl.color);
    paintFavSel = _sel(j['paintFavSel'], paintFav, paint.color);
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
