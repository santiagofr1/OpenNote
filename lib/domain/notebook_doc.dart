import 'dart:collection';
import 'dart:developer' as developer;
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

  /// Copia independiente (mismos ids, mismas coordenadas locales).
  SheetContent copy() => SheetContent(
        strokes: [for (final s in strokes) s.moved(Offset.zero)],
        texts: [for (final t in texts) t.copy()],
        items: [for (final i in items) i.copy()],
      );
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
///
/// Carga perezosa: [sheets] (los [SheetMeta]) siempre están todas, pero los elementos (trazos, textos, items)
/// solo existen de las hojas CARGADAS ([loadedSheets]). Una hoja no cargada es lo que dice su archivo en disco:
/// NUNCA se escribe desde acá (el guardado solo toca las cargadas) y se carga con [attachSheet] / se suelta con
/// [detachSheet] (los usa la `Storage`, que sabe cuándo es seguro). Las operaciones de hojas (mover, borrar,
/// insertar) funcionan igual con hojas sin cargar porque lo que se guarda en cada archivo son coordenadas locales.
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

  // ids de las hojas cuyos elementos están en memoria
  final _loaded = <String>{};
  // hojas NO cargadas donde cayó un elemento (se lo movió o pegó ahí): al cargarlas hay que guardarlas
  final _misplaced = <String>{};
  final _loadListeners = <void Function(String id, bool loaded)>[];

  /// [lazy]: ninguna hoja empieza cargada (las carga la `Storage` con [attachSheet]).
  NotebookDoc(this.nb,
      {Map<String, Stroke>? strokes, Map<String, TextBlock>? texts, Map<String, Item>? items, bool lazy = false})
      : _rawStrokes = strokes ?? {},
        _rawTexts = texts ?? {},
        _rawItems = items ?? {} {
    if (nb.sheets.isEmpty) {
      final m = nb.newSheet(); // un cuaderno siempre tiene al menos una hoja (nueva: no hay nada que cargar)
      nb.sheets.add(m);
      _loaded.add(m.id);
    }
    if (!lazy) _loaded.addAll(nb.sheets.map((m) => m.id));
  }

  /// Cuaderno con todas las hojas sin cargar.
  factory NotebookDoc.lazy(Notebook nb) => NotebookDoc(nb, lazy: true);

  /// Un documento de una sola hoja suelta (miniaturas de la biblioteca).
  factory NotebookDoc.single(SheetMeta meta, SheetContent c) =>
      NotebookDoc.fromSheets(Notebook('', '', sheets: [meta]), [c]);

  String get id => nb.id;
  List<SheetMeta> get sheets => nb.sheets;
  int get sheetCount => sheets.length;

  /// Ancho del contenido: el de una hoja, o el del lienzo infinito (que crece a la derecha).
  double get width => nb.canvas ? nb.canvasW : kW;

  /// Zona de la hoja [k] dentro de la tira. En un lienzo la franja es todo el ancho y llega hasta la de abajo
  /// (incluye el hueco, así nada queda en tierra de nadie).
  Rect bandRect(int k) =>
      nb.canvas ? Rect.fromLTWH(0, k * kSheetStep, width, kSheetStep) : Rect.fromLTWH(0, k * kSheetStep, kW, kSheetH);

  /// Alto de toda la tira.
  double get h => heightFor(sheets.length);

  // ================= hojas cargadas =================
  /// Ids de las hojas cuyos elementos están en memoria.
  Set<String> get loadedSheets => Set.unmodifiable(_loaded);
  bool isLoaded(String sheetId) => _loaded.contains(sheetId);
  bool isLoadedAt(int k) => k >= 0 && k < sheets.length && _loaded.contains(sheets[k].id);
  bool get allLoaded => sheets.every((m) => _loaded.contains(m.id));

  /// Índice de la hoja [sheetId] (-1 si ya no está).
  int indexOfSheet(String sheetId) => sheets.indexWhere((m) => m.id == sheetId);

  /// Hojas sin cargar donde cayó algún elemento: hay que cargarlas cuanto antes (al cargar se marcan para guardar).
  Set<String> get misplacedSheets => Set.unmodifiable(_misplaced);
  bool get hasMisplaced => _misplaced.isNotEmpty;

  /// Avisa cuando una hoja se carga (true) o se descarga (false). Lo usan el editor y el panel de hojas.
  void addLoadListener(void Function(String id, bool loaded) f) => _loadListeners.add(f);
  void removeLoadListener(void Function(String id, bool loaded) f) => _loadListeners.remove(f);

  /// Ids de las hojas que toca el rectángulo [r].
  Iterable<String> sheetIdsOfRect(Rect r) sync* {
    for (var k = sheetOfY(r.top); k <= sheetOfY(r.bottom); k++) {
      yield sheets[k].id;
    }
  }

  /// Id de la hoja donde está ahora el elemento [elementId] (trazo, texto o item); null si no está en memoria.
  String? sheetIdOfElementId(String elementId) {
    final e = _rawStrokes[elementId] ?? _rawTexts[elementId] ?? _rawItems[elementId];
    return e == null ? null : sheets[sheetOfElement(e)].id;
  }

  /// Pone en memoria el contenido [c] (coordenadas locales, sin copiar) de la hoja [id], que estaba sin cargar.
  /// Si ya está cargada no hace NADA (nunca pisa lo que hay en memoria). No marca nada sucio: es lo que dice el disco,
  /// salvo que haya elementos que cayeron en esta hoja antes de cargarla. Devuelve si la cargó.
  bool attachSheet(String id, SheetContent c) => developer.Timeline.timeSync('ON attachSheet', () => _attachSheet(id, c));

  bool _attachSheet(String id, SheetContent c) {
    final k = indexOfSheet(id);
    if (k < 0 || _loaded.contains(id)) return false;
    _place(c, k * kSheetStep);
    _loaded.add(id);
    if (_misplaced.remove(id)) _dirty.add(id);
    _touch(id);
    if (k + 1 < sheets.length) _touch(sheets[k + 1].id); // un trazo puede pasarse a la hoja de abajo
    for (final f in List.of(_loadListeners)) {
      f(id, true);
    }
    return true;
  }

  /// Saca de memoria los elementos de la hoja [id] (no los borra del disco). Se niega (false) si la hoja
  /// no está cargada o tiene cambios sin guardar: soltar eso perdería datos.
  bool detachSheet(String id) => developer.Timeline.timeSync('ON detachSheet', () => _detachSheet(id));

  bool _detachSheet(String id) {
    final k = indexOfSheet(id);
    if (k < 0 || !_loaded.contains(id) || isSheetDirty(id)) return false;
    _rawStrokes.removeWhere((_, s) {
      if (_sheetOfStroke(s) != k) return false;
      s.releaseMesh(); // las mallas se sueltan con la hoja
      return true;
    });
    _rawTexts.removeWhere((_, t) => sheetOfY(t.y) == k);
    _rawItems.removeWhere((_, it) => sheetOfY(it.y) == k);
    _loaded.remove(id);
    _touch(id);
    if (k + 1 < sheets.length) _touch(sheets[k + 1].id);
    for (final f in List.of(_loadListeners)) {
      f(id, false);
    }
    return true;
  }

  bool get isEmpty => strokes.isEmpty && texts.isEmpty && items.isEmpty;

  /// Hoja que contiene la altura [y] (el espacio entre hojas cuenta para la de arriba).
  int sheetOfY(double y) => (y / kSheetStep).floor().clamp(0, sheets.length - 1);

  /// Alto del renglón de texto (unidades) de la hoja que contiene [y].
  double lineAt(double y) {
    final m = sheets[sheetOfY(y)];
    return paper.textLine(m.bg, m.spacing, size: m.size);
  }

  /// Tamaño de papel (a4 | a3 | a5) de la hoja que contiene [y].
  String sizeAt(double y) => sheets[sheetOfY(y)].size;

  /// Lleva la y global [y] de un texto al renglón de SU hoja (cada hoja tiene su espaciado).
  /// [floor]: al renglón de arriba en vez del más cercano.
  double snapTextY(double y, {bool floor = false}) {
    final k = sheetOfY(y), m = sheets[k];
    return k * kSheetStep + paper.snapTextY(y - k * kSheetStep, m.bg, m.spacing, floor: floor, size: m.size);
  }

  // ================= hojas sucias =================
  /// Hoja (índice) a la que se guarda [e]: la de su borde de arriba, igual que en [splitBySheet].
  int sheetOfElement(Layered e) => switch (e) {
        Stroke s => _sheetOfStroke(s),
        TextBlock t => sheetOfY(t.y),
        Item i => sheetOfY(i.y),
        _ => 0,
      };

  // Avisos para el render (repintar solo la hoja que cambió). Es aparte de lo sucio: takeDirty (el guardado)
  // no los toca. id null = todas las hojas.
  final _renderListeners = <void Function(String? sheetId)>[];
  void addRenderListener(void Function(String? sheetId) f) => _renderListeners.add(f);
  void removeRenderListener(void Function(String? sheetId) f) => _renderListeners.remove(f);

  void _touch(String? id) {
    if (_renderListeners.isEmpty) return;
    for (final f in List.of(_renderListeners)) {
      f(id);
    }
  }

  // Un elemento de la hoja k cambió. Si la hoja no está cargada, el elemento cayó ahí sin que la hoja esté en memoria
  // (hay que cargarla; ver [misplacedSheets]).
  void _mark(int k) {
    final id = sheets[k].id;
    if (_loaded.contains(id)) {
      _dirty.add(id);
    } else {
      _misplaced.add(id);
    }
    _touch(id);
  }

  // Cambió algo de la hoja k que no es un elemento (la hoja de arriba de una nueva): una hoja sin cargar no se toca,
  // su archivo no cambia.
  void _markSheet(int k) {
    final id = sheets[k].id;
    if (!_loaded.contains(id)) return;
    _dirty.add(id);
    _touch(id);
  }

  /// Marca la hoja que contiene la altura [y].
  void markDirtyAt(double y) => _mark(sheetOfY(y));

  /// Marca la hoja donde está ahora [e]. Si lo cambiás en el lugar, llamalo ANTES y DESPUÉS del cambio.
  /// Para el guardado cuenta solo la hoja de su borde de arriba; para el render, un trazo avisa a todas
  /// las hojas que toca (se dibuja recortado en cada una).
  void markDirtyElement(Layered e) {
    final k = sheetOfElement(e);
    _mark(k);
    if (e is Stroke) {
      final b = e.bounds;
      for (var j = sheetOfY(b.top); j <= sheetOfY(b.bottom); j++) {
        if (j != k) _touch(sheets[j].id);
      }
    }
  }

  /// Marca la hoja de índice [k] (si no está cargada no hay nada que guardar y no hace nada).
  void markDirtySheet(int k) => _markSheet(k);

  /// Todo cambió (operaciones de hojas): se guarda todo.
  void markAllDirty() {
    _allDirty = true;
    _touch(null);
  }

  bool get hasDirty => _allDirty || _dirty.isNotEmpty;

  /// La hoja [id] tiene cambios sin guardar (o está todo sucio).
  bool isSheetDirty(String id) => _allDirty || _dirty.contains(id);

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
    final m = nb.newSheet();
    sheets.add(m);
    _loaded.add(m.id); // una hoja nueva está entera en memoria
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
    if (!isLoadedAt(sheets.length - 1)) return false; // sin cargar no se sabe: no se quita
    return !strokes.values.any((s) => s.bounds.bottom > top) &&
        !texts.values.any((t) => t.y + lineAt(t.y) > top) &&
        !items.values.any((i) => i.y + i.h > top);
  }

  /// Quita la última hoja si hay más de una y está vacía.
  bool removeLastSheetIfEmpty() {
    if (sheets.length < 2 || !lastSheetEmpty) return false;
    final gone = sheets.removeLast().id;
    _loaded.remove(gone);
    _dirty.remove(gone);
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
  /// [keepZ]: el contenido ya trae el orden de dibujo del documento (deshacer / rehacer de hojas): no se renumera arriba de todo.
  SheetMeta insertSheet(int at, {SheetMeta? meta, SheetContent? content, bool keepZ = false}) {
    at = at.clamp(0, sheets.length);
    if (at < sheets.length) {
      markAllDirty(); // corre las de abajo
    } else {
      markDirtySheet(sheets.length - 1);
    }
    _shiftWhere((k) => k >= at, kSheetStep);
    final m = meta ?? nb.newSheet();
    sheets.insert(at, m);
    _loaded.add(m.id); // una hoja nueva está entera en memoria
    if (content != null) _place(content, at * kSheetStep, keepZ: keepZ);
    _dirty.add(m.id); // hay que escribirla (también al restaurar una borrada: en disco puede haber algo viejo)
    _touch(m.id);
    return m;
  }

  /// Copia la hoja [i] justo después de ella (con ids nuevos). Devuelve la hoja nueva.
  SheetMeta duplicateSheet(int i, {String Function(String title)? copyTitle}) {
    if (!isLoadedAt(i)) throw StateError('la hoja $i no está cargada: cargala antes de duplicarla');
    final src = sheets[i];
    final copy = _contentOf(i, fresh: true);
    return insertSheet(i + 1,
        meta: src.copy(id: newId('h'), title: src.title.isEmpty ? '' : (copyTitle?.call(src.title) ?? '${src.title} (copia)'), bookmark: false),
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
    final gone = sheets.removeAt(i).id; // si no estaba cargada no hay nada en memoria; su archivo lo borra la Storage
    _loaded.remove(gone);
    _misplaced.remove(gone);
    _dirty.remove(gone);
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
  /// Solo para documentos con todo cargado (una hoja sin cargar saldría vacía).
  List<SheetContent> splitBySheet() {
    assert(allLoaded, 'splitBySheet con hojas sin cargar');
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
  /// Las hojas SIN CARGAR no aparecen nunca (su contenido no está en memoria: no se puede guardar).
  Map<String, SheetContent> splitSheets(Set<String> ids) {
    final out = <int, SheetContent>{};
    for (var k = 0; k < sheets.length; k++) {
      if (ids.contains(sheets[k].id) && _loaded.contains(sheets[k].id)) out[k] = SheetContent();
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
  /// Con [keepZ] los [Layered.z] se dejan como vienen (son los globales de cuando se sacó la hoja).
  void _place(SheetContent c, double top, {bool keepZ = false}) {
    if (!keepZ) {
      var z = nextZ();
      for (final e in sortByZ([...c.items, ...c.strokes, ...c.texts])) {
        e.z = z++;
      }
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
