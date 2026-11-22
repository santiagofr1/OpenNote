import 'elements.dart';
import 'stroke.dart';

enum Tool { pen, hl, paint, text, select }

/// Puntas del lápiz (id guardado en el trazo, nombre en pantalla).
const tips = [
  ('pen', 'Bolígrafo'),
  ('fountain', 'Pluma'),
  ('pencil', 'Lápiz'),
  ('fine', 'Fibra'),
  ('calli', 'Caligrafía'),
];

/// Tipos de trazo de la pintura (id guardado en `pp.st`, nombre en pantalla).
const paintStyles = [('brush', 'Pincel'), ('hl', 'Resaltador'), ('marker', 'Fibra')];

/// Formas de la pintura decorativa (id guardado en el trazo, nombre en pantalla).
const paintShapes = [
  ('paint-stars', 'Estrellas'),
  ('paint-hearts', 'Corazones'),
  ('paint-sparkles', 'Destellos'),
  ('paint-moons', 'Lunas'),
  ('paint-dots', 'Puntos'),
  ('paint-circles', 'Círculos'),
  ('paint-bangs', 'Exclamaciones'),
  ('paint-bolts', 'Rayos'),
  ('paint-ticks', 'Ticks'),
  ('paint-crosses', 'Cruces'),
  ('paint-clouds', 'Nubes'),
  ('paint-bubbles', 'Globos'),
  ('paint-leaves', 'Hojas'),
  ('paint-paws', 'Huellas'),
  ('paint-triangles', 'Triángulos'),
  ('paint-squares', 'Cuadrados'),
  ('paint-diamonds', 'Rombos'),
  ('paint-flowers', 'Flores'),
  ('paint-notes', 'Notas'),
];

/// Radio de la goma: chica, mediana, grande.
const eraserSizes = [8.0, 16.0, 30.0];

/// Paleta: grises + 10 familias de color en 4 tonos (oscuro → claro)
const palette = [
  '#000000', '#22211e', '#4b4a46', '#7a776e', '#a8a59c', '#d4d1c8', '#ffffff',
  '#7f1d1d', '#b91c1c', '#ef4444', '#fca5a5',
  '#7c2d12', '#c2410c', '#f97316', '#fdba74',
  '#713f12', '#ca8a04', '#facc15', '#fde68a',
  '#14532d', '#15803d', '#22c55e', '#86efac',
  '#134e4a', '#0f766e', '#14b8a6', '#5eead4',
  '#1e3a8a', '#1d4ed8', '#3b82f6', '#93c5fd',
  '#312e81', '#4338ca', '#6366f1', '#a5b4fc',
  '#581c87', '#7e22ce', '#a855f7', '#d8b4fe',
  '#831843', '#be185d', '#ec4899', '#f9a8d4',
  '#3f2a1d', '#7c5a3c', '#a47551', '#d6b896',
];
/// Colores de las formitas: blanco, plateado, dorado, o el fondo aclarado / oscurecido ('light' / 'dark', ver [PaintParams]).
const paintShapeColors = ['#ffffff', '#c0c4cc', '#d4a937', 'light', 'dark'];

/// Fondos de la pintura: pasteles (rosa, aqua, beige dorado, lila, menta, durazno, manteca, gris perla).
const paintPalette = ['#f4a7c3', '#8fd8e0', '#e3cfa0', '#c9b3ec', '#a8e2c4', '#f8c4a0', '#f6e7a1', '#d9dbe0'];
const hlPalette = ['#f7d22c', '#ffb347', '#5ee08a', '#5bc8ff', '#ff86c8', '#c79bff', '#ff6b6b', '#b8f35d'];

class PenPreset {
  String tip, color;
  double width, opacity;
  PenPreset(this.tip, this.color, this.width, this.opacity);
  Map<String, dynamic> toJson() => {'tip': tip, 'color': color, 'width': width, 'opacity': opacity};
  void load(Map? j) {
    if (j == null) return;
    tip = (j['tip'] ?? tip) as String;
    color = (j['color'] ?? color) as String;
    width = ((j['width'] ?? width) as num).toDouble();
    opacity = ((j['opacity'] ?? opacity) as num).toDouble();
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
  int eraserSize = 1;
  String dock = 'top'; // top | left | right
  double zoom = 1; // 1 = la hoja entra justa a lo ancho
  bool zoomLocked = false;
  bool shapeSnap = true; // figuras inteligentes: lápiz quieto al final del trazo lo vuelve figura limpia
  final clipboard = SelectionClipboard(); // no se guarda

  bool get drawing => tool == Tool.pen || tool == Tool.hl || tool == Tool.paint;
  PenPreset get current => switch (tool) { Tool.hl => hl, Tool.paint => paint, _ => pen };
  List<String> get recent => switch (tool) { Tool.hl => hlRecent, Tool.paint => paintRecent, _ => penRecent };
  double get eraserRadius => eraserSizes[eraserSize];

  /// Elige un color y lo pone primero en "recientes" (hasta 7).
  void pickColor(String c) {
    current.color = c;
    _remember(recent, c);
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
        'eraserSize': eraserSize,
        'dock': dock,
        'zoom': zoom,
        'zoomLocked': zoomLocked,
        'shapeSnap': shapeSnap,
      };

  void load(Map? j) {
    if (j == null) return;
    tool = Tool.values.firstWhere((t) => t.name == j['tool'], orElse: () => Tool.pen);
    pen.load(j['pen'] as Map?);
    hl.load(j['hl'] as Map?);
    paint.load(j['paint'] as Map?);
    paintParams = j['paintParams'] is Map ? PaintParams.fromJson(j['paintParams'] as Map) : const PaintParams();
    if (paint.tip == 'paint-none') {
      // la vieja opción "Ninguna" ahora es tener las formas apagadas
      paint.tip = 'paint-stars';
      paintParams = paintParams.copyWith(shapes: false);
    }
    if (!isPaint(paint.tip)) paint.tip = 'paint-stars'; // una forma que ya no existe
    if (j['penRecent'] is List) penRecent = List<String>.from(j['penRecent'] as List);
    if (j['hlRecent'] is List) hlRecent = List<String>.from(j['hlRecent'] as List);
    if (j['paintRecent'] is List) paintRecent = List<String>.from(j['paintRecent'] as List);
    eraserSize = ((j['eraserSize'] ?? 1) as int).clamp(0, 2);
    if (const ['top', 'left', 'right'].contains(j['dock'])) dock = j['dock'] as String;
    zoom = ((j['zoom'] ?? 1) as num).toDouble().clamp(.5, 4.0);
    zoomLocked = (j['zoomLocked'] ?? false) as bool;
    shapeSnap = j['shapeSnap'] is bool ? j['shapeSnap'] as bool : true;
  }
}
