import 'dart:math';
import 'dart:ui';

import '../domain/domain.dart';
import '../rendering/text_layout.dart';

/// Rectángulo que envuelve trazos, textos y elementos (null si no hay nada).
/// [lineOf]: alto del renglón de cada texto (el de su hoja); sin él, el de referencia.
Rect? contentBounds(Iterable<Stroke> strokes, Iterable<TextBlock> texts, Iterable<Item> items,
        {double Function(TextBlock)? lineOf}) =>
    unionRects([
      ...strokes.map((s) => s.bounds),
      ...texts.map((t) => textBounds(t, lineOf?.call(t) ?? kLine)),
      ...items.map((i) => i.rect)
    ]);

Rect? clipboardBounds(SelectionClipboard c) => contentBounds(c.strokes, c.texts, c.items);

/// Qué se agarró de la selección: el interior (mover), una esquina (escalar), el medio de un lado (estirar) o la manija de arriba (rotar).
enum Handle { move, tl, tr, br, bl, top, right, bottom, left, rotate }

/// Las manijas del medio de cada lado (estiran sin mantener la proporción).
bool isSideHandle(Handle h) => h == Handle.top || h == Handle.right || h == Handle.bottom || h == Handle.left;

/// Arrastre de la selección: los trazos se dibujan transformados por [xf] hasta soltar; textos y elementos se
/// actualizan en vivo y acá queda dónde (y de qué tamaño) estaban.
class MoveDrag {
  final Offset from;
  final Handle handle;

  /// Escalar: [pivot] es la esquina opuesta (ancla) y [corner] la que se arrastra. Rotar: [pivot] es el centro.
  final Offset pivot, corner;

  /// Escala mínima (que nada quede de 0 ni más chico que lo permitido para un elemento).
  final double minScale;

  /// Estiramiento mínimo por eje (manijas de los lados).
  final double minKx, minKy;
  Xform xf = const Xform();
  final Map<String, Rect> textOrig, itemOrig;

  /// Escala, giro y ancho que tenía cada texto al empezar (los textos escalan y giran con la selección).
  final Map<String, (double, double, double)> textState;
  MoveDrag(this.from, this.textOrig, this.itemOrig,
      {this.textState = const {}, this.handle = Handle.move, this.pivot = Offset.zero, this.corner = Offset.zero, this.minScale = .1, this.minKx = .1, this.minKy = .1});

  /// Cuánto se corrió (el arrastre de mover).
  Offset get delta => xf.shift;
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

  /// Rectángulo de lo seleccionado en su posición original (sin el arrastre en curso), sin margen.
  Rect? contentRect(NotebookDoc p) {
    final d = drag;
    return contentBounds(
      strokesOf(p),
      [
        for (final t in textsOf(p))
          t.copy(d: (d?.textOrig[t.id]?.topLeft ?? Offset(t.x, t.y)) - Offset(t.x, t.y))
            ..scale = d?.textState[t.id]?.$1 ?? t.scale
            ..angle = d?.textState[t.id]?.$2 ?? t.angle
            ..w = d?.textState[t.id]?.$3 ?? t.w
      ],
      [for (final it in itemsOf(p)) if (d?.itemOrig[it.id] case final r?) it.copy()..x = r.left..y = r.top..w = r.width..h = r.height else it],
      lineOf: (t) => p.lineAt(t.y),
    );
  }

  /// [contentRect] con margen: el recuadro que se ve.
  Rect? bounds(NotebookDoc p) => contentRect(p)?.inflate(6);

  /// Empieza a mover lo seleccionado desde [p].
  void startDrag(NotebookDoc doc, Offset p) => drag = _newDrag(doc, p, Handle.move);

  /// Empieza a escalar (esquina [h]), estirar (lado [h]) o rotar ([Handle.rotate]) lo seleccionado; [p] es donde está el lápiz.
  void startHandle(NotebookDoc doc, Handle h, Offset p) {
    final r = contentRect(doc);
    if (r == null) return;
    drag = _newDrag(doc, p, h, r);
  }

  MoveDrag _newDrag(NotebookDoc doc, Offset p, Handle h, [Rect? r]) {
    final texts = {for (final t in textsOf(doc)) t.id: textRect(t, doc.lineAt(t.y))};
    final items = {for (final it in itemsOf(doc)) it.id: it.rect};
    final state = {for (final t in textsOf(doc)) t.id: (t.scale, t.angle, t.w)};
    var pivot = Offset.zero, corner = Offset.zero, minScale = .1, minKx = .1, minKy = .1;
    if (r != null && h == Handle.rotate) pivot = r.center;
    if (r != null && h != Handle.move && h != Handle.rotate) {
      corner = switch (h) {
        Handle.tl => r.topLeft,
        Handle.tr => r.topRight,
        Handle.br => r.bottomRight,
        Handle.bl => r.bottomLeft,
        Handle.top => r.topCenter,
        Handle.right => r.centerRight,
        Handle.bottom => r.bottomCenter,
        _ => r.centerLeft,
      };
      pivot = switch (h) {
        Handle.tl => r.bottomRight,
        Handle.tr => r.bottomLeft,
        Handle.br => r.topLeft,
        Handle.bl => r.topRight,
        Handle.top => r.bottomCenter,
        Handle.right => r.centerLeft,
        Handle.bottom => r.topCenter,
        _ => r.centerRight,
      };
      // un elemento no baja de 60 de ancho (ni de alto, salvo el audio, que es de 56)
      // un texto no baja de 1/4 de su tamaño normal
      for (final t in textsOf(doc)) {
        minScale = max(minScale, min(.25 / t.scale, 1.0));
        minKx = max(minKx, min(60 / t.w, 1.0));
      }
      for (final it in itemsOf(doc)) {
        final need = max(60 / it.w, it.type == 'image' ? 0.0 : (it.type == 'audio' ? 56 : 60) / it.h);
        minScale = max(minScale, min(need, 1.0));
        minKx = max(minKx, min(60 / it.w, 1.0));
        minKy = max(minKy, min((it.type == 'audio' ? 56 : 60) / it.h, 1.0));
      }
    }
    return MoveDrag(p, texts, items,
        textState: state, handle: h, pivot: pivot, corner: corner, minScale: minScale, minKx: minKx, minKy: minKy);
  }

  /// El lápiz (o el dedo) está en [p]: calcula la transformación del arrastre en curso.
  void dragTo(Offset p) {
    final d = drag;
    if (d == null) return;
    switch (d.handle) {
      case Handle.move:
        d.xf = Xform.move(p - d.from);
      case Handle.rotate:
        final a = (p - d.pivot).direction - (d.from - d.pivot).direction;
        d.xf = Xform(pivot: d.pivot, angle: snapAngle(atan2(sin(a), cos(a))));
      case Handle.left || Handle.right:
        // estira solo el ancho: el lado opuesto queda fijo
        final den = d.from.dx - d.pivot.dx;
        final kx = den.abs() < 1e-6 ? 1.0 : (p.dx - d.pivot.dx) / den;
        d.xf = Xform(pivot: d.pivot, kx: max(d.minKx, kx));
      case Handle.top || Handle.bottom:
        final den = d.from.dy - d.pivot.dy;
        final ky = den.abs() < 1e-6 ? 1.0 : (p.dy - d.pivot.dy) / den;
        d.xf = Xform(pivot: d.pivot, ky: max(d.minKy, ky));
      default:
        // escala uniforme: cuánto se alejó el lápiz del ancla, sobre la diagonal, respecto de donde agarró la esquina
        final v = d.corner - d.pivot;
        double along(Offset q) => (q.dx - d.pivot.dx) * v.dx + (q.dy - d.pivot.dy) * v.dy;
        final s = along(d.from).abs() < 1e-6 ? 1.0 : along(p) / along(d.from);
        d.xf = Xform(pivot: d.pivot, scale: max(d.minScale, s));
    }
  }

  /// Deja textos y elementos como corresponde a la transformación del arrastre (en vivo, y al volver a la identidad
  /// quedan donde estaban). Marca sucias las hojas de antes y de después. Los textos solo cambian de lugar; los
  /// elementos, de tamaño y de lugar (el centro; no rotan). Los textos escalan ([TextBlock.scale]) y giran ([TextBlock.angle]).
  void applyToBlocks(NotebookDoc doc) {
    final d = drag;
    if (d == null) return;
    final xf = d.xf;
    d.textOrig.forEach((id, r) {
      final t = doc.texts[id];
      if (t == null) return;
      doc.markDirtyElement(t);
      final st = d.textState[id] ?? (t.scale, t.angle, t.w);
      if (xf.isMove) {
        final m = xf.shift;
        t.scale = st.$1;
        t.angle = st.$2;
        t.w = st.$3;
        t.x = r.left + m.dx;
        t.y = r.top + m.dy;
      } else if (xf.kx != 1 || xf.ky != 1) {
        // estirar: cambia el ancho de la caja (el texto se reacomoda); el alto sale del contenido
        final c = xf.apply(r.center);
        t.scale = st.$1;
        t.angle = st.$2;
        // se parte del ancho que se ve (si el texto no llena la caja, el borde sigue al lápiz)
        t.w = max(20.0, min(st.$3, r.width / st.$1) * xf.kx);
        t.x = c.dx - r.width * xf.kx / 2;
        t.y = c.dy - r.height / 2;
      } else {
        t.w = st.$3;
        // escala (desde el pivote, como los elementos) y giro: el centro va donde lo lleva la transformación
        final c = xf.apply(r.center), size = r.size * xf.scale;
        t.scale = st.$1 * xf.scale;
        t.angle = st.$2 + xf.angle;
        t.x = c.dx - size.width / 2;
        t.y = c.dy - size.height / 2;
      }
      doc.markDirtyElement(t);
    });
    d.itemOrig.forEach((id, r) {
      final it = doc.items[id];
      if (it == null) return;
      doc.markDirtyElement(it);
      if (xf.isMove) {
        it..x = r.left + xf.shift.dx..y = r.top + xf.shift.dy..w = r.width..h = r.height;
      } else {
        final c = xf.apply(r.center), w = r.width * xf.kx * xf.scale, h = r.height * xf.ky * xf.scale;
        it..x = c.dx - w / 2..y = c.dy - h / 2..w = w..h = h;
      }
      doc.markDirtyElement(it);
    });
  }

  /// Lo que hay bajo [pt] (con margen [tol], en unidades de documento), de arriba hacia abajo en lo que se VE:
  /// el orden de dibujo, con el resaltador debajo de la tinta de su tanda (ver [zRuns]). Hit test real:
  /// trazos contra su recorrido, textos y elementos contra su rectángulo.
  List<Layered> hitStack(NotebookDoc doc, Offset pt, double tol) {
    final seen = <Layered>[];
    for (final run in zRuns(doc.drawOrder())) {
      final ink = run.strokes;
      if (ink != null) {
        seen..addAll(ink.where((s) => isUnderInk(s.k)))..addAll(ink.where((s) => !isUnderInk(s.k)));
      } else {
        seen.add(run.single!);
      }
    }
    bool hit(Layered e) => switch (e) {
          Stroke s => s.hitBy(pt, tol),
          TextBlock t => textHit(t, pt, tol, doc.lineAt(t.y)),
          Item it => it.rect.inflate(tol).contains(pt),
          _ => false,
        };
    return [for (final e in seen.reversed) if (hit(e)) e];
  }

  /// Deja seleccionado solo [e].
  void selectOne(Layered e) => replace(
      strokes: [if (e is Stroke) e.id], texts: [if (e is TextBlock) e.id], items: [if (e is Item) e.id]);

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
        if (r.overlaps(textBounds(t, doc.lineAt(t.y)))) texts.add(t.id);
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
      if (r.contains(textBounds(t, doc.lineAt(t.y)).center)) texts.add(t.id);
    }
    for (final it in doc.items.values) {
      if (r.contains(it.rect.center)) items.add(it.id);
    }
  }
}
