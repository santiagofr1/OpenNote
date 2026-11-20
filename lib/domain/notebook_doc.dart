import 'dart:collection';
import 'dart:ui';

import 'elements.dart';
import 'geometry.dart';
import 'notebook.dart';
import 'paper_layout.dart' as paper;
import 'stroke.dart';
import 'values.dart';
import 'z_order.dart';

/// Lo que hay en una hoja, con coordenadas LOCALES (y = 0 es el borde de arriba de esa hoja).
/// Es lo que se guarda en cada archivo `.sheet`.
class SheetContent {
  final List<Stroke> strokes;
  final List<TextBlock> texts;
  final List<Item> items;
  SheetContent({List<Stroke>? strokes, List<TextBlock>? texts, List<Item>? items})
      : strokes = strokes ?? [],
        texts = texts ?? [],
        items = items ?? [];

  bool get isEmpty => strokes.isEmpty && texts.isEmpty && items.isEmpty;
}

/// Mapa de elementos que avisa cada vez que se agrega, reemplaza o saca uno (para saber qué hoja cambió).
class _TrackedMap<V extends Layered> extends MapBase<String, V> {
  final Map<String, V> inner;
  final void Function(V) _touch;
  _TrackedMap(this.inner, this._touch);

  @override
  V? operator [](Object? key) => inner[key];
  @override
  void operator []=(String key, V value) {
    final old = inner[key];
    if (old != null) _touch(old); // la hoja donde estaba
    inner[key] = value;
    _touch(value); // y la hoja donde queda
  }

  @override
  V? remove(Object? key) {
    final old = inner.remove(key);
    if (old != null) _touch(old);
    return old;
  }

  @override
  void clear() {
    inner.values.forEach(_touch);
    inner.clear();
  }

  @override
  Iterable<String> get keys => inner.keys;
  @override
  Iterable<V> get values => inner.values;
  @override
  Iterable<MapEntry<String, V>> get entries => inner.entries;
  @override
  int get length => inner.length;
  @override
  bool get isEmpty => inner.isEmpty;
  @override
  bool get isNotEmpty => inner.isNotEmpty;
  @override
  bool containsKey(Object? key) => inner.containsKey(key);
  @override
  void forEach(void Function(String, V) action) => inner.forEach(action);
}

/// El cuaderno abierto en memoria: una tira continua de hojas.
///
/// Trazos, textos y elementos viven en coordenadas GLOBALES de la tira (la hoja k ocupa
/// y de `k * kSheetStep` a `k * kSheetStep + kSheetH`), así el editor, la selección, la tinta
/// y el deshacer funcionan igual que con una sola página larga.
/// Cada elemento pertenece a la hoja que contiene su borde de arriba ([sheetOfY]).
/// El orden de dibujo es uno solo para todo (ver [Layered]): [drawOrder]. El orden de los mapas no cuenta.
///
/// Hojas sucias (para guardar solo lo que cambió): agregar, reemplazar o sacar de [strokes] / [texts] / [items]
/// marca solo la hoja de antes y la de después. Lo que se cambia EN EL LUGAR (x, y, tamaño, texto, z)
/// hay que marcarlo a mano con [markDirtyElement] antes y después del cambio. El contenido de cada hoja
/// no incluye sus datos (título, fondo...): eso va en notebook.json y se compara aparte al guardar.
class NotebookDoc {
  final Notebook nb;
  final Map<String, Stroke> _rawStrokes;
  final Map<String, TextBlock> _rawTexts;
  final Map<String, Item> _rawItems;
  late final Map<String, Stroke> strokes = _TrackedMap(_rawStrokes, markDirtyElement);
  late final Map<String, TextBlock> texts = _TrackedMap(_rawTexts, markDirtyElement);
  late final Map<String, Item> items = _TrackedMap(_rawItems, markDirtyElement);

  // ids (SheetMeta.id, no el índice: las hojas se mueven) de las hojas con cambios sin guardar
  final _dirty = <String>{};
  bool _allDirty = false;

  NotebookDoc(this.nb, {Map<String, Stroke>? strokes, Map<String, TextBlock>? texts, Map<String, Item>? items})
      : _rawStrokes = strokes ?? {},
        _rawTexts = texts ?? {},
        _rawItems = items ?? {} {
    if (nb.sheets.isEmpty) nb.sheets.add(nb.newSheet()); // un cuaderno siempre tiene al menos una hoja
  }

  /// Un documento de una sola hoja suelta (miniaturas de la biblioteca).
  factory NotebookDoc.single(SheetMeta meta, SheetContent c) =>
      NotebookDoc.fromSheets(Notebook('', '', sheets: [meta]), [c]);

  String get id => nb.id;
  List<SheetMeta> get sheets => nb.sheets;
  int get sheetCount => sheets.length;

  /// Alto de toda la tira.
  double get h => heightFor(sheets.length);

  bool get isEmpty => strokes.isEmpty && texts.isEmpty && items.isEmpty;

  /// Hoja que contiene la altura [y] (el espacio entre hojas cuenta para la de arriba).
  int sheetOfY(double y) => (y / kSheetStep).floor().clamp(0, sheets.length - 1);

  /// Alto del renglón de texto (unidades) de la hoja que contiene [y].
  double lineAt(double y) {
    final m = sheets[sheetOfY(y)];
    return paper.textLine(m.bg, m.spacing);
  }

  /// Lleva la y global [y] de un texto al renglón de SU hoja (cada hoja tiene su espaciado).
  /// [floor]: al renglón de arriba en vez del más cercano.
  double snapTextY(double y, {bool floor = false}) {
    final k = sheetOfY(y), m = sheets[k];
    return k * kSheetStep + paper.snapTextY(y - k * kSheetStep, m.bg, m.spacing, floor: floor);
  }

  // ================= hojas sucias =================
  /// Hoja (índice) a la que se guarda [e]: la de su borde de arriba, igual que en [splitBySheet].
  int sheetOfElement(Layered e) => switch (e) {
        Stroke s => _sheetOfStroke(s),
        TextBlock t => sheetOfY(t.y),
        Item i => sheetOfY(i.y),
        _ => 0,
      };

  /// Marca la hoja que contiene la altura [y].
  void markDirtyAt(double y) => _dirty.add(sheets[sheetOfY(y)].id);

  /// Marca todas las hojas que toca el rectángulo [r].
  void markDirtyRect(Rect r) {
    for (var k = sheetOfY(r.top); k <= sheetOfY(r.bottom); k++) {
      _dirty.add(sheets[k].id);
    }
  }

  /// Marca la hoja donde está ahora [e]. Si lo cambiás en el lugar, llamalo ANTES y DESPUÉS del cambio.
  void markDirtyElement(Layered e) => _dirty.add(sheets[sheetOfElement(e)].id);

  /// Marca la hoja de índice [k].
  void markDirtySheet(int k) => _dirty.add(sheets[k].id);

  /// Todo cambió (operaciones de hojas): se guarda todo.
  void markAllDirty() => _allDirty = true;

  bool get hasDirty => _allDirty || _dirty.isNotEmpty;

  /// Lo sucio hasta ahora, y lo deja limpio (lo usa el guardado; lo que se marque después queda para el próximo).
  ({Set<String> ids, bool all}) takeDirty() {
    final r = (ids: Set<String>.of(_dirty), all: _allDirty);
    _dirty.clear();
    _allDirty = false;
    return r;
  }

  /// Vuelve a marcar lo que [takeDirty] devolvió (el guardado falló).
  void restoreDirty(({Set<String> ids, bool all}) d) {
    _dirty.addAll(d.ids);
    if (d.all) _allDirty = true;
  }

  // ================= orden de dibujo =================
  /// Todo lo que se dibuja, de abajo hacia arriba.
  List<Layered> drawOrder() => sortByZ([...items.values, ...strokes.values, ...texts.values]);

  /// [z] para un elemento nuevo: arriba de todo.
  int nextZ() {
    var m = -1;
    for (final e in items.values) {
      if (e.z > m) m = e.z;
    }
    for (final e in strokes.values) {
      if (e.z > m) m = e.z;
    }
    for (final e in texts.values) {
      if (e.z > m) m = e.z;
    }
    return m + 1;
  }

  /// Pone [els] arriba de todo, conservando el orden que tenían entre sí.
  void stackOnTop(Iterable<Layered> els) {
    var z = nextZ();
    for (final e in sortByZ(els)) {
      markDirtyElement(e);
      e.z = z++;
    }
  }

  /// Cambia el [z] del elemento [id] (trazo, texto o elemento), donde esté.
  void setZ(String id, int z) {
    final e = strokes[id] ?? texts[id] ?? items[id];
    if (e != null) {
      markDirtyElement(e);
      e.z = z;
    }
  }

  /// Mueve en el orden de dibujo lo que tenga alguno de los ids de [ids] (ver [computeReorder]).
  /// Aplica el cambio y lo devuelve para poder deshacerlo; null si no cambia nada.
  ZChange? reorder(Set<String> ids, ZMove move, Rect Function(Layered) rectOf) {
    final ch = computeReorder(drawOrder(), ids, move, rectOf);
    if (ch != null) ch.after.forEach(setZ);
    return ch;
  }

  int _sheetOfStroke(Stroke s) => sheetOfY(s.bounds.top);

  // ================= hojas al final =================
  /// Agrega una hoja al final con el estilo del cuaderno.
  void addSheet() {
    markDirtySheet(sheets.length - 1); // lo que estaba pasado del final de la última puede caer en la nueva
    sheets.add(nb.newSheet());
  }

  /// Agrega hojas hasta que [y] quede a menos de una hoja del final (escribir o pegar abajo).
  void growFor(double y) {
    final want = y ~/ kSheetStep + 2;
    if (y > h - 250) {
      while (sheets.length < want) {
        addSheet();
      }
    }
  }

  /// La última hoja no tiene nada: se puede quitar.
  bool get lastSheetEmpty {
    final top = (sheets.length - 1) * kSheetStep;
    return !strokes.values.any((s) => s.bounds.bottom > top) &&
        !texts.values.any((t) => t.y + lineAt(t.y) > top) &&
        !items.values.any((i) => i.y + i.h > top);
  }

  /// Quita la última hoja si hay más de una y está vacía.
  bool removeLastSheetIfEmpty() {
    if (sheets.length < 2 || !lastSheetEmpty) return false;
    sheets.removeLast();
    return true;
  }

  // ================= operaciones sobre hojas =================
  // Todas corren los elementos en el lugar (los objetos son los mismos: los campos de texto
  // y la selección que los referencian siguen valiendo, pero el deshacer ya no).

  /// Corre [dy] los elementos de las hojas para las que [test] da verdadero.
  void _shiftWhere(bool Function(int sheet) test, double dy) {
    if (dy == 0) return;
    for (final s in strokes.values) {
      if (test(_sheetOfStroke(s))) s.translateY(dy);
    }
    for (final t in texts.values) {
      if (test(sheetOfY(t.y))) t.y += dy;
    }
    for (final i in items.values) {
      if (test(sheetOfY(i.y))) i.y += dy;
    }
  }

  /// Hoja nueva en la posición [at] (0..cantidad): lo que estaba desde ahí baja una hoja.
  /// [content] (coordenadas locales) se pone adentro; se usa tal cual, sin copiar.
  SheetMeta insertSheet(int at, {SheetMeta? meta, SheetContent? content}) {
    at = at.clamp(0, sheets.length);
    if (at < sheets.length) {
      markAllDirty(); // corre las de abajo
    } else {
      markDirtySheet(sheets.length - 1);
    }
    _shiftWhere((k) => k >= at, kSheetStep);
    final m = meta ?? nb.newSheet();
    sheets.insert(at, m);
    if (content != null) _place(content, at * kSheetStep);
    return m;
  }

  /// Copia la hoja [i] justo después de ella (con ids nuevos). Devuelve la hoja nueva.
  SheetMeta duplicateSheet(int i) {
    final src = sheets[i];
    final copy = _contentOf(i, fresh: true);
    return insertSheet(i + 1,
        meta: src.copy(id: newId('h'), title: src.title.isEmpty ? '' : '${src.title} (copia)', bookmark: false),
        content: copy);
  }

  /// Borra la hoja [i] con todo lo que tiene; lo de abajo sube. No se puede borrar la última que queda.
  bool deleteSheet(int i) {
    if (sheets.length < 2 || i < 0 || i >= sheets.length) return false;
    markAllDirty();
    strokes.removeWhere((_, s) => _sheetOfStroke(s) == i);
    texts.removeWhere((_, t) => sheetOfY(t.y) == i);
    items.removeWhere((_, it) => sheetOfY(it.y) == i);
    _shiftWhere((k) => k > i, -kSheetStep);
    sheets.removeAt(i);
    return true;
  }

  /// Lleva la hoja [from] a la posición [to] (las del medio se corren una).
  void moveSheet(int from, int to) {
    final n = sheets.length;
    if (from < 0 || from >= n || to < 0 || to >= n || from == to) return;
    markAllDirty();
    // nueva posición de cada hoja vieja
    final order = List.generate(n, (i) => i)
      ..removeAt(from)
      ..insert(to, from);
    final newPos = List.filled(n, 0);
    for (var p = 0; p < n; p++) {
      newPos[order[p]] = p;
    }
    // el corrimiento depende de la hoja vieja de cada elemento: se calcula antes de tocar nada
    for (final s in strokes.values) {
      final k = _sheetOfStroke(s);
      s.translateY((newPos[k] - k) * kSheetStep);
    }
    for (final t in texts.values) {
      final k = sheetOfY(t.y);
      t.y += (newPos[k] - k) * kSheetStep;
    }
    for (final it in items.values) {
      final k = sheetOfY(it.y);
      it.y += (newPos[k] - k) * kSheetStep;
    }
    sheets.insert(to, sheets.removeAt(from));
  }

  // ================= hojas <-> documento =================
  /// Lo de la hoja [i] en coordenadas locales (copias; con ids nuevos si [fresh]).
  SheetContent _contentOf(int i, {bool fresh = false}) {
    final d = Offset(0, -i * kSheetStep);
    return SheetContent(
      strokes: [
        for (final s in strokes.values)
          if (_sheetOfStroke(s) == i) s.moved(d, id: fresh ? newId('s') : null)
      ],
      texts: [
        for (final t in texts.values)
          if (sheetOfY(t.y) == i) t.copy(id: fresh ? newId('t') : null, d: d)
      ],
      items: [
        for (final it in items.values)
          if (sheetOfY(it.y) == i) it.copy(id: fresh ? newId('i') : null, d: d)
      ],
    );
  }

  /// Parte el documento en el contenido de cada hoja, en coordenadas locales (copias).
  /// Cada elemento va a la hoja que contiene el borde de arriba de su rectángulo.
  /// Cada copia conserva su [Layered.z]: dentro de cada hoja queda el orden de dibujo.
  List<SheetContent> splitBySheet() {
    final out = List.generate(sheets.length, (_) => SheetContent());
    for (final s in strokes.values) {
      final k = _sheetOfStroke(s);
      out[k].strokes.add(s.moved(Offset(0, -k * kSheetStep)));
    }
    for (final t in texts.values) {
      final k = sheetOfY(t.y);
      out[k].texts.add(t.copy(d: Offset(0, -k * kSheetStep)));
    }
    for (final it in items.values) {
      final k = sheetOfY(it.y);
      out[k].items.add(it.copy(d: Offset(0, -k * kSheetStep)));
    }
    return out;
  }

  /// Como [splitBySheet] pero solo de las hojas con id en [ids] (copias; clave: id de la hoja).
  /// No copia el resto del cuaderno. Las hojas pedidas sin nada devuelven un contenido vacío.
  Map<String, SheetContent> splitSheets(Set<String> ids) {
    final out = <int, SheetContent>{};
    for (var k = 0; k < sheets.length; k++) {
      if (ids.contains(sheets[k].id)) out[k] = SheetContent();
    }
    for (final s in strokes.values) {
      final k = _sheetOfStroke(s);
      out[k]?.strokes.add(s.moved(Offset(0, -k * kSheetStep)));
    }
    for (final t in texts.values) {
      final k = sheetOfY(t.y);
      out[k]?.texts.add(t.copy(d: Offset(0, -k * kSheetStep)));
    }
    for (final it in items.values) {
      final k = sheetOfY(it.y);
      out[k]?.items.add(it.copy(d: Offset(0, -k * kSheetStep)));
    }
    return {for (final e in out.entries) sheets[e.key].id: e.value};
  }

  /// Arma el documento global del cuaderno [nb] con el contenido local de cada hoja
  /// (inverso de [splitBySheet]). [sheets] tiene que tener una entrada por hoja de [nb].
  factory NotebookDoc.fromSheets(Notebook nb, List<SheetContent> sheets) {
    assert(sheets.length == nb.sheets.length);
    final doc = NotebookDoc(nb);
    for (var k = 0; k < sheets.length; k++) {
      doc._place(sheets[k], k * kSheetStep);
    }
    return doc;
  }

  /// Agrega [c] (coordenadas locales) corrido [top] hacia abajo, sin copiar.
  /// Los elementos quedan arriba de todo, en el orden de [Layered.z] que traía la hoja.
  void _place(SheetContent c, double top) {
    var z = nextZ();
    for (final e in sortByZ([...c.items, ...c.strokes, ...c.texts])) {
      e.z = z++;
    }
    for (final s in c.strokes) {
      if (top != 0) s.translateY(top);
      _rawStrokes[s.id] = s;
    }
    for (final t in c.texts) {
      t.y += top;
      _rawTexts[t.id] = t;
    }
    for (final i in c.items) {
      i.y += top;
      _rawItems[i.id] = i;
    }
  }
}
