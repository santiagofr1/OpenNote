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

  /// "Seleccionar todo": todo lo de la hoja [sheet] (índice; como Samsung Notes, que selecciona por página). Cada
  /// elemento es de la hoja de su borde de arriba ([NotebookDoc.sheetOfElement]). Una hoja sin cargar no tiene elementos.
  /// Sin [sheet]: todo lo que haya cargado (lo usa "Seleccionar todo el cuaderno" después de cargar las hojas que faltan).
  void selectAll(NotebookDoc p, {int? sheet}) {
    bool inSheet(Layered e) => sheet == null || p.sheetOfElement(e) == sheet;
    replace(
      strokes: [for (final s in p.strokes.values) if (inSheet(s)) s.id],
      texts: [for (final t in p.texts.values) if (inSheet(t)) t.id],
      items: [for (final i in p.items.values) if (inSheet(i)) i.id],
    );
  }

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

  /// Lo que hay bajo [pt] (con margen [tol], en unidades de documento), de arriba hacia abajo en lo que se VE:
  /// el orden de dibujo, con el resaltador debajo de la tinta de su tanda (ver [zRuns]). Hit test real:
  /// trazos contra su recorrido, textos y elementos contra su rectángulo.
  List<Layered> hitStack(NotebookDoc doc, Offset pt, double tol) {
    final seen = <Layered>[];
    for (final run in zRuns(doc.drawOrder())) {
      final ink = run.strokes;
      if (ink != null) {
        seen..addAll(ink.where((s) => s.k == 'hl'))..addAll(ink.where((s) => s.k != 'hl'));
      } else {
        seen.add(run.single!);
      }
    }
    bool hit(Layered e) => switch (e) {
          Stroke s => s.hitBy(pt, tol),
          TextBlock t => textRect(t, doc.lineAt(t.y)).inflate(tol).contains(pt),
          Item it => it.rect.inflate(tol).contains(pt),
          _ => false,
        };
    return [for (final e in seen.reversed) if (hit(e)) e];
  }

  /// Deja seleccionado solo [e].
  void selectOne(Layered e) => replace(
      strokes: [if (e is Stroke) e.id], texts: [if (e is TextBlock) e.id], items: [if (e is Item) e.id]);

  /// ¿Hay resaltador y además cualquier otra cosa (tinta, textos, imágenes, notas, audios)? Entonces la barrita
  /// ofrece los filtros "Solo resaltador" / "Sin resaltador".
  bool mixedInk(NotebookDoc doc) {
    final s = strokesOf(doc);
    return s.any((x) => x.k == 'hl') && (s.any((x) => x.k != 'hl') || texts.isNotEmpty || items.isNotEmpty);
  }

  /// Filtra la selección. Con [hl]: queda solo el resaltador (se sueltan tinta, textos y elementos).
  /// Sin [hl]: se saca el resaltador y queda todo lo demás (tinta, textos y elementos).
  void keepOnly(NotebookDoc doc, {required bool hl}) {
    final keep = [for (final s in strokesOf(doc)) if ((s.k == 'hl') == hl) s.id];
    replace(strokes: keep, texts: hl ? const [] : texts.toList(), items: hl ? const [] : items.toList());
  }

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
