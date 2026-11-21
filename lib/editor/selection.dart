import 'dart:ui';

import '../domain/domain.dart';
import '../rendering/text_layout.dart';

/// Rectángulo que envuelve trazos, textos y elementos (null si no hay nada).
/// [lineOf]: alto del renglón de cada texto (el de su hoja); sin él, el de referencia.
Rect? contentBounds(Iterable<Stroke> strokes, Iterable<TextBlock> texts, Iterable<Item> items,
        {double Function(TextBlock)? lineOf}) =>
    unionRects([
      ...strokes.map((s) => s.bounds),
      ...texts.map((t) => textRect(t, lineOf?.call(t) ?? kLine)),
      ...items.map((i) => i.rect)
    ]);

Rect? clipboardBounds(SelectionClipboard c) => contentBounds(c.strokes, c.texts, c.items);

/// Arrastre de la selección: los trazos se dibujan corridos [delta] hasta soltar;
/// textos y elementos se mueven en vivo y acá queda dónde estaban.
class MoveDrag {
  final Offset from;
  Offset delta = Offset.zero;
  final Map<String, Offset> textOrig, itemOrig;
  MoveDrag(this.from, this.textOrig, this.itemOrig);
}

/// Lo seleccionado (por id), el rectángulo que se está estirando y el arrastre en curso.
class Selection {
  final strokes = <String>{}, texts = <String>{}, items = <String>{};
  Offset? bandA, bandB;
  MoveDrag? drag;

  bool get isEmpty => strokes.isEmpty && texts.isEmpty && items.isEmpty;
  bool get moving => drag != null;
  Rect? get band => bandA == null || bandB == null ? null : Rect.fromPoints(bandA!, bandB!);

  /// El rectángulo se estira de derecha a izquierda: es de "captura" (toma todo lo que toca);
  /// de izquierda a derecha es de "ventana" (solo lo que queda adentro).
  bool get capture => bandA != null && bandB != null && bandB!.dx < bandA!.dx;

  /// Un solo elemento y nada más: se puede agrandar con la esquina.
  bool get singleItem => items.length == 1 && strokes.isEmpty && texts.isEmpty;

  void clear() {
    strokes.clear();
    texts.clear();
    items.clear();
    bandA = bandB = null;
    drag = null;
  }

  /// Reemplaza la selección (sin tocar el rectángulo ni el arrastre).
  void replace({Iterable<String> strokes = const [], Iterable<String> texts = const [], Iterable<String> items = const []}) {
    this.strokes
      ..clear()
      ..addAll(strokes);
    this.texts
      ..clear()
      ..addAll(texts);
    this.items
      ..clear()
      ..addAll(items);
  }

  /// Ids de todo lo seleccionado (trazos, textos y elementos).
  Set<String> get allIds => {...strokes, ...texts, ...items};

  /// "Seleccionar todo": todo lo de las hojas CARGADAS (las visibles y las cercanas), no el cuaderno entero:
  /// las hojas lejanas no están en memoria (ver la carga perezosa en [NotebookDoc]).
  void selectAll(NotebookDoc p) => replace(strokes: p.strokes.keys, texts: p.texts.keys, items: p.items.keys);

  // lo seleccionado que sigue existiendo en la página
  List<Stroke> strokesOf(NotebookDoc p) => [for (final id in strokes) ?p.strokes[id]];
  List<TextBlock> textsOf(NotebookDoc p) => [for (final id in texts) ?p.texts[id]];
  List<Item> itemsOf(NotebookDoc p) => [for (final id in items) ?p.items[id]];

  /// Rectángulo de lo seleccionado en su posición original (sin el arrastre en curso), con margen.
  Rect? bounds(NotebookDoc p) {
    final d = drag;
    Offset back(Offset? orig, double x, double y) => orig == null ? Offset.zero : orig - Offset(x, y);
    return contentBounds(
      strokesOf(p),
      [for (final t in textsOf(p)) t.copy(d: back(d?.textOrig[t.id], t.x, t.y))],
      [for (final it in itemsOf(p)) it.copy(d: back(d?.itemOrig[it.id], it.x, it.y))],
      lineOf: (t) => p.lineAt(t.y),
    )?.inflate(6);
  }

  /// Empieza a mover lo seleccionado desde [p].
  void startDrag(NotebookDoc doc, Offset p) => drag = MoveDrag(
        p,
        {for (final t in textsOf(doc)) t.id: Offset(t.x, t.y)},
        {for (final it in itemsOf(doc)) it.id: Offset(it.x, it.y)},
      );

  /// Selecciona lo que queda dentro de [r] ("ventana"): trazos con la mitad o más de sus puntos adentro;
  /// textos y elementos, si su centro cae adentro. Con [capture], todo lo que [r] toca: trazos cuyo
  /// recorrido cruza el rectángulo (ver [Stroke.touchesRect]), textos y elementos que se superponen.
  /// Un rectángulo mínimo (un toque) no elige nada.
  void selectIn(NotebookDoc doc, Rect r, {bool capture = false}) {
    replace();
    if (r.width < 4 && r.height < 4) return;
    if (capture) {
      for (final s in doc.strokes.values) {
        if (s.touchesRect(r)) strokes.add(s.id);
      }
      for (final t in doc.texts.values) {
        if (r.overlaps(textRect(t, doc.lineAt(t.y)))) texts.add(t.id);
      }
      for (final it in doc.items.values) {
        if (r.overlaps(it.rect)) items.add(it.id);
      }
      return;
    }
    for (final s in doc.strokes.values) {
      if (!r.overlaps(s.bounds)) continue;
      var inside = 0;
      for (var i = 0; i < s.pts.length; i += 3) {
        if (r.contains(Offset(s.pts[i], s.pts[i + 1]))) inside++;
      }
      if (inside * 2 >= s.n) strokes.add(s.id);
    }
    for (final t in doc.texts.values) {
      if (r.contains(textRect(t, doc.lineAt(t.y)).center)) texts.add(t.id);
    }
    for (final it in doc.items.values) {
      if (r.contains(it.rect.center)) items.add(it.id);
    }
  }
}
