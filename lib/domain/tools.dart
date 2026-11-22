import 'elements.dart';
import 'stroke.dart';

enum Tool { pen, hl, text, select }

/// Puntas del lápiz (id guardado en el trazo, nombre en pantalla).
const tips = [
  ('pen', 'Bolígrafo'),
  ('fountain', 'Pluma'),
  ('pencil', 'Lápiz'),
  ('fine', 'Fibra'),
  ('calli', 'Caligrafía'),
];

/// Pinceles de diseño (formas estampadas para decorar títulos y resúmenes): se muestran aparte de las puntas.
const designTips = [
  ('dots', 'Puntitos'),
  ('stars', 'Estrellas'),
  ('hearts', 'Corazones'),
  ('flowers', 'Flores'),
  ('scallop', 'Ondas'),
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
  List<String> penRecent = ['#22211e', '#1d4ed8', '#b91c1c', '#15803d', '#c2410c', '#7e22ce'];
  List<String> hlRecent = ['#f7d22c', '#5ee08a', '#ff86c8', '#5bc8ff'];
  int eraserSize = 1;
  String dock = 'top'; // top | left | right
  double zoom = 1; // 1 = la hoja entra justa a lo ancho
  bool zoomLocked = false;
  final clipboard = SelectionClipboard(); // no se guarda

  bool get drawing => tool == Tool.pen || tool == Tool.hl;
  PenPreset get current => tool == Tool.hl ? hl : pen;
  List<String> get recent => tool == Tool.hl ? hlRecent : penRecent;
  double get eraserRadius => eraserSizes[eraserSize];

  /// Elige un color y lo pone primero en "recientes" (hasta 7).
  void pickColor(String c) {
    current.color = c;
    final r = recent..remove(c);
    r.insert(0, c);
    if (r.length > 7) r.removeLast();
  }

  Map<String, dynamic> toJson() => {
        'tool': tool.name,
        'pen': pen.toJson(),
        'hl': hl.toJson(),
        'penRecent': penRecent,
        'hlRecent': hlRecent,
        'eraserSize': eraserSize,
        'dock': dock,
        'zoom': zoom,
        'zoomLocked': zoomLocked,
      };

  void load(Map? j) {
    if (j == null) return;
    tool = Tool.values.firstWhere((t) => t.name == j['tool'], orElse: () => Tool.pen);
    pen.load(j['pen'] as Map?);
    hl.load(j['hl'] as Map?);
    if (j['penRecent'] is List) penRecent = List<String>.from(j['penRecent'] as List);
    if (j['hlRecent'] is List) hlRecent = List<String>.from(j['hlRecent'] as List);
    eraserSize = ((j['eraserSize'] ?? 1) as int).clamp(0, 2);
    if (const ['top', 'left', 'right'].contains(j['dock'])) dock = j['dock'] as String;
    zoom = ((j['zoom'] ?? 1) as num).toDouble().clamp(.5, 4.0);
    zoomLocked = (j['zoomLocked'] ?? false) as bool;
  }
}
