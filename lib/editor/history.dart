import 'dart:ui' show Offset;

import '../domain/domain.dart';

/// Un elemento de una acción puesto en SU hoja: [v] es una copia en coordenadas LOCALES de la hoja [sheet] (y = 0 es el
/// borde de arriba de esa hoja). Al aplicar la acción se vuelve a global contra el documento de ese momento, sin
/// importar dónde esté la hoja ni qué pasó con las demás. [top] es el lugar de la hoja cuando se tomó la copia: solo se usa
/// si la hoja ya no existe (por ejemplo, la última vacía que el editor quitó sola).
class _At<T> {
  final String sheet;
  final double top;
  final T v;
  const _At(this.sheet, this.top, this.v);

  /// Desplazamiento de local a global en [doc] ahora.
  double shift(NotebookDoc doc) {
    final k = doc.indexOfSheet(sheet);
    return k < 0 ? top : k * kSheetStep;
  }
}

/// Una acción deshacible: trazos que salieron/entraron y cómo estaban textos y elementos antes/después.
/// En los mapas, null = no existía (antes) o ya no existe (después).
///
/// La acción NO guarda objetos del documento: cada trazo, texto y elemento queda como una copia en coordenadas locales
/// de su hoja (id de hoja + posición dentro de ella), tomada al crearla. Al deshacer o rehacer se resuelve contra el
/// documento de ese momento (hoja por id, elemento por id). Así las operaciones de hojas que corren o restauran
/// copias (mover, borrar, restaurar) no pueden dejar nada corrido. Como deshacer y rehacer se aplican siempre en
/// orden estricto, el documento al aplicar una acción es el mismo que cuando se hizo.
/// Una acción con [sheetOps] no mezcla elementos (las operaciones de hojas van solas).
class EditAction {
  /// Operaciones de hojas (agregar, duplicar, mover, borrar). Se hacen en este orden al rehacer y al revés al deshacer.
  final List<SheetOp> sheetOps;
  final List<_At<Stroke>> _removed, _added;
  final Map<String, _At<TextBlock>?> _textBefore, _textAfter;
  final Map<String, _At<Item>?> _itemBefore, _itemAfter;

  /// Cambios de orden de dibujo: [z] de cada elemento (por id) antes y después.
  final Map<String, int> zBefore, zAfter;

  /// Hoja de cada elemento de [zBefore] / [zAfter] cuando se creó la acción.
  final Map<String, String> _zSheet;

  const EditAction._(this.sheetOps, this._removed, this._added, this._textBefore, this._textAfter, this._itemBefore,
      this._itemAfter, this.zBefore, this.zAfter, this._zSheet);

  /// Acción sin nada (relleno en pruebas).
  const EditAction.empty() : this._(const [], const [], const [], const {}, const {}, const {}, const {}, const {}, const {}, const {});

  /// Arma la acción DESPUÉS de hacer el cambio en [doc]: los elementos se toman en las hojas donde están ahora o
  /// donde estaban (el reparto de hojas es el mismo, porque las operaciones de hojas van solas).
  factory EditAction(
    NotebookDoc doc, {
    List<SheetOp> sheetOps = const [],
    List<Stroke> removed = const [],
    List<Stroke> added = const [],
    Map<String, TextBlock?> textBefore = const {},
    Map<String, TextBlock?> textAfter = const {},
    Map<String, Item?> itemBefore = const {},
    Map<String, Item?> itemAfter = const {},
    Map<String, int> zBefore = const {},
    Map<String, int> zAfter = const {},
  }) {
    assert(
        sheetOps.isEmpty ||
            (removed.isEmpty && added.isEmpty && textBefore.isEmpty && textAfter.isEmpty && itemBefore.isEmpty && itemAfter.isEmpty && zBefore.isEmpty),
        'las operaciones de hojas no se mezclan con elementos en una misma acción');
    _At<Stroke> stroke(Stroke s) {
      final k = doc.sheetOfElement(s), top = k * kSheetStep;
      return _At(doc.sheets[k].id, top, s.moved(Offset(0, -top)));
    }

    _At<TextBlock>? text(TextBlock? t) {
      if (t == null) return null;
      final k = doc.sheetOfY(t.y), top = k * kSheetStep;
      return _At(doc.sheets[k].id, top, t.copy(d: Offset(0, -top)));
    }

    _At<Item>? item(Item? it) {
      if (it == null) return null;
      final k = doc.sheetOfY(it.y), top = k * kSheetStep;
      return _At(doc.sheets[k].id, top, it.copy(d: Offset(0, -top)));
    }

    final zs = <String, String>{};
    for (final id in zBefore.keys.followedBy(zAfter.keys)) {
      final sh = doc.sheetIdOfElementId(id);
      if (sh != null) zs[id] = sh;
    }
    return EditAction._(
      sheetOps,
      [for (final s in removed) stroke(s)],
      [for (final s in added) stroke(s)],
      {for (final e in textBefore.entries) e.key: text(e.value)},
      {for (final e in textAfter.entries) e.key: text(e.value)},
      {for (final e in itemBefore.entries) e.key: item(e.value)},
      {for (final e in itemAfter.entries) e.key: item(e.value)},
      Map.of(zBefore),
      Map.of(zAfter),
      zs,
    );
  }

  /// Los elementos que la acción deja antes / después (copias locales; null = no existía / ya no existe). Para mirar
  /// qué toca la acción (sus ids), no para ponerlos en el documento.
  Map<String, Item?> get itemBefore => {for (final e in _itemBefore.entries) e.key: e.value?.v};
  Map<String, Item?> get itemAfter => {for (final e in _itemAfter.entries) e.key: e.value?.v};

  /// Cambia el trazo [id] de lo que la acción pone ([added]) por lo que devuelve [f] (que recibe la copia LOCAL y la
  /// devuelve ya cambiada, en la misma posición). Lo usa el corrector cuando llega el color de un trazo ya confirmado.
  void mapAdded(String id, Stroke Function(Stroke local) f) {
    final i = _added.indexWhere((a) => a.v.id == id);
    if (i < 0) return;
    final a = _added[i];
    _added[i] = _At(a.sheet, a.top, f(a.v));
  }

  /// Ids de las hojas que toca esta acción: donde están (antes y después) sus elementos, y las de sus operaciones de
  /// hojas. Solo cuenta las que existen ahora. Mientras la acción esté en el historial esas hojas no se pueden
  /// descargar: deshacer/rehacer las necesita en memoria.
  Set<String> sheetIds(NotebookDoc doc) {
    final out = <String>{for (final op in sheetOps) ...op.sheetIds(doc)};
    void add(String id) {
      if (!out.contains(id) && doc.indexOfSheet(id) >= 0) out.add(id);
    }

    for (final a in _removed.followedBy(_added)) {
      add(a.sheet);
    }
    for (final m in [_textBefore, _textAfter]) {
      for (final a in m.values) {
        if (a != null) add(a.sheet);
      }
    }
    for (final m in [_itemBefore, _itemAfter]) {
      for (final a in m.values) {
        if (a != null) add(a.sheet);
      }
    }
    _zSheet.values.forEach(add);
    return out;
  }

  /// Vuelve la página a como estaba antes ([undo]) o después de la acción.
  /// Los textos pasan por [putText] para que sus campos de edición se enteren.
  void apply(NotebookDoc doc, {required bool undo, required void Function(String id, TextBlock? t) putText}) {
    for (final op in undo ? sheetOps.reversed : sheetOps) {
      op.apply(doc, undo: undo);
    }
    for (final a in undo ? _added : _removed) {
      doc.strokes.remove(a.v.id);
    }
    for (final a in undo ? _removed : _added) {
      doc.strokes[a.v.id] = a.v.moved(Offset(0, a.shift(doc))); // copia: lo guardado en la acción no se toca
    }
    (undo ? _textBefore : _textAfter).forEach((id, a) {
      final cur = doc.texts[id];
      if (cur != null) doc.markDirtyElement(cur); // la hoja de donde sale
      final t = a == null ? null : a.v.copy(d: Offset(0, a.shift(doc)));
      putText(id, t);
      if (t != null) doc.markDirtyElement(t); // y la de donde queda
    });
    (undo ? _itemBefore : _itemAfter).forEach((id, a) {
      if (a == null) {
        doc.items.remove(id);
      } else {
        doc.items[id] = a.v.copy(d: Offset(0, a.shift(doc)));
      }
    });
    (undo ? zBefore : zAfter).forEach(doc.setZ);
  }
}

/// Copia de la acción sin lo que toca al elemento [id]; null si no queda nada por hacer.
extension EditActionForget on EditAction {
  EditAction? withoutItem(String id) {
    Map<String, T> drop<T>(Map<String, T> m) => {
          for (final e in m.entries)
            if (e.key != id) e.key: e.value,
        };
    final a = EditAction._(sheetOps, _removed, _added, _textBefore, _textAfter, drop(_itemBefore), drop(_itemAfter),
        drop(zBefore), drop(zAfter), drop(_zSheet));
    final empty = a.sheetOps.isEmpty &&
        a._removed.isEmpty &&
        a._added.isEmpty &&
        a._textBefore.isEmpty &&
        a._textAfter.isEmpty &&
        a._itemBefore.isEmpty &&
        a._itemAfter.isEmpty &&
        a.zBefore.isEmpty &&
        a.zAfter.isEmpty;
    return empty ? null : a;
  }
}

/// Hoja a mostrar después de aplicar la acción (la de la última operación de hojas); null si no toca hojas.
extension EditActionSheets on EditAction {
  int? sheetFocus(NotebookDoc doc, {required bool undo}) =>
      sheetOps.isEmpty ? null : (undo ? sheetOps.first : sheetOps.last).focus(doc, undo: undo);
}

/// Operación de hojas deshacible. El contenido va en coordenadas locales de la hoja, así que mover hojas no toca los
/// trazos: solo se corren en el documento global (`NotebookDoc.moveSheet`), que ya conserva lo local.
sealed class SheetOp {
  const SheetOp();

  /// Hace ([undo] false) o deshace la operación.
  void apply(NotebookDoc doc, {required bool undo});

  /// Hojas que tienen que estar cargadas para poder aplicarla (se fijan en memoria mientras la acción esté en el historial).
  Set<String> sheetIds(NotebookDoc doc) => const {};

  /// Índice de la hoja que conviene mostrar después de aplicarla.
  int focus(NotebookDoc doc, {required bool undo});
}

/// Mover la hoja [from] a la posición [to].
class SheetMoveOp extends SheetOp {
  final int from, to;
  const SheetMoveOp(this.from, this.to);

  /// Mueve la hoja [from] a [to] en [doc] y devuelve la operación (null si no cambia nada).
  static SheetMoveOp? run(NotebookDoc doc, int from, int to) {
    if (from == to || from < 0 || to < 0 || from >= doc.sheetCount || to >= doc.sheetCount) return null;
    doc.moveSheet(from, to);
    return SheetMoveOp(from, to);
  }

  @override
  void apply(NotebookDoc doc, {required bool undo}) => undo ? doc.moveSheet(to, from) : doc.moveSheet(from, to);

  @override
  int focus(NotebookDoc doc, {required bool undo}) => undo ? from : to;
}

/// Una hoja que se agregó (o duplicó: [added] true) o se borró ([added] false). Guarda la hoja entera (datos y contenido local) para
/// poder volver a ponerla en su lugar; al sacarla de nuevo se vuelve a tomar lo que tenga en ese momento.
/// Una hoja borrada que se puede restaurar vive solo acá, en memoria, hasta que el historial la suelte
/// (el archivo `.sheet` lo borra el guardado como siempre): por eso borrar carga la hoja antes.
class SheetPresenceOp extends SheetOp {
  final bool added;
  int at;
  SheetMeta meta;
  SheetContent content;
  SheetPresenceOp._(this.added, this.at, this.meta, this.content);

  /// Registra una hoja [m] recién agregada o duplicada (ya está en [doc]).
  factory SheetPresenceOp.added(NotebookDoc doc, SheetMeta m) {
    final op = SheetPresenceOp._(true, 0, m, SheetContent());
    op._capture(doc, doc.indexOfSheet(m.id));
    return op;
  }

  /// Borra la hoja [i] (que tiene que estar cargada) y devuelve la operación; null si no se pudo borrar.
  static SheetPresenceOp? delete(NotebookDoc doc, int i) {
    if (doc.sheetCount < 2 || i < 0 || i >= doc.sheetCount || !doc.isLoadedAt(i)) return null;
    final op = SheetPresenceOp._(false, i, doc.sheets[i], SheetContent());
    op._capture(doc, i);
    return doc.deleteSheet(i) ? op : null;
  }

  void _capture(NotebookDoc doc, int i) {
    if (i < 0) return;
    final m = doc.sheets[i];
    at = i;
    meta = m.copy();
    if (doc.isLoaded(m.id)) content = doc.splitSheets({m.id})[m.id] ?? SheetContent();
  }

  @override
  void apply(NotebookDoc doc, {required bool undo}) {
    if (added != undo) {
      doc.insertSheet(at, meta: meta.copy(), content: content.copy(), keepZ: true); // con el z que tenía: deshacer deja el orden exacto
    } else {
      final i = doc.indexOfSheet(meta.id);
      if (i < 0) return;
      _capture(doc, i);
      doc.deleteSheet(i);
    }
  }

  @override
  Set<String> sheetIds(NotebookDoc doc) => doc.indexOfSheet(meta.id) >= 0 ? {meta.id} : const {};

  @override
  int focus(NotebookDoc doc, {required bool undo}) =>
      (added != undo ? doc.indexOfSheet(meta.id) : at).clamp(0, doc.sheetCount - 1);
}

/// Mapa "no existía / ya no existe" para esos ids.
Map<String, T?> absent<T>(Iterable<String> ids) => {for (final id in ids) id: null};

/// Tope de hojas lejanas fijadas SOLO por el historial. Pasado esto se descartan las acciones más viejas (ver
/// [History.trim]). 12: es lo que entra cómodo en memoria (una hoja cargada con tinta y mallas pesa unos pocos MB;
/// 12 más las ~11 cercanas que ya se mantienen quedan en el orden de lo medido, 240 a 409 MB de PSS con 34 hojas) y
/// alcanza para deshacer con holgura lo que se hizo en las últimas hojas trabajadas.
const kHistoryMaxFarSheets = 12;

/// Pilas de deshacer / rehacer.
class History {
  static const limit = 200;
  final _undo = <EditAction>[], _redo = <EditAction>[];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Cuántas acciones se pueden deshacer / rehacer.
  int get undoCount => _undo.length;
  int get redoCount => _redo.length;

  /// Una acción nueva borra lo que se podía rehacer.
  void push(EditAction a) {
    _undo.add(a);
    if (_undo.length > limit) _undo.removeAt(0);
    _redo.clear();
  }

  /// Cambia el elemento [id] en las copias guardadas del historial (deshacer y rehacer lo vuelven a poner con esos datos).
  /// Lo usa la grabación de voz: el audio se inserta con duración 0 y cuando termina se le pone la real.
  void patchItem(String id, void Function(Item it) f) {
    for (final a in [..._undo, ..._redo]) {
      for (final m in [a._itemBefore, a._itemAfter]) {
        final it = m[id];
        if (it != null) f(it.v);
      }
    }
  }

  /// Saca el elemento [id] de todo el historial, como si nunca hubiera existido (cancelar una grabación: el audio no
  /// tiene archivo, y deshacer no lo tiene que resucitar). Las acciones que quedan vacías se descartan.
  void forgetItem(String id) {
    List<EditAction> clean(List<EditAction> l) => [
          for (final a in l) ?a.withoutItem(id),
        ];
    final u = clean(_undo), r = clean(_redo);
    _undo
      ..clear()
      ..addAll(u);
    _redo
      ..clear()
      ..addAll(r);
  }

  /// La acción que haría [undo] / [redo], sin hacerla.
  EditAction? peek({required bool undo}) => (undo ? _undo : _redo).lastOrNull;

  /// Ids de las hojas que tocan las acciones del historial (deshacer y rehacer).
  Set<String> sheetIds(NotebookDoc doc) => {
        for (final a in _undo) ...a.sheetIds(doc),
        for (final a in _redo) ...a.sheetIds(doc),
      };

  /// Poda del historial para no fijar en memoria demasiadas hojas lejanas. Cuenta las hojas que tocan las acciones
  /// del historial y están en [far] (lejos de lo que se ve) y no en [exempt] (otras razones para tenerlas cargadas:
  /// sucias, seleccionadas, con foco...). Si son más de [maxFar], descarta las acciones de deshacer MÁS VIEJAS, una por
  /// una desde el fondo de la pila (recorte por el fondo: lo que queda sigue siendo consistente, porque cada acción
  /// se apoya en el estado que dejaron las anteriores, que ya está aplicado), hasta volver bajo el tope. Se corta antes
  /// de la primera acción que toque una hoja de [visible]: esa nunca se descarta. Si descartando todo lo posible
  /// sigue pasado el tope, se vacía lo que se puede rehacer. Devuelve true si descartó algo.
  bool trim(NotebookDoc doc, {required Set<String> far, required Set<String> exempt, required Set<String> visible, int maxFar = kHistoryMaxFarSheets}) {
    final undoSets = [for (final a in _undo) a.sheetIds(doc)];
    final redoSets = [for (final a in _redo) a.sheetIds(doc)];
    final counts = <String, int>{};
    void add(Set<String> ids, int d) {
      for (final id in ids) {
        if (far.contains(id) && !exempt.contains(id)) counts.update(id, (n) => n + d, ifAbsent: () => d);
        if (counts[id] == 0) counts.remove(id);
      }
    }

    for (final x in [...undoSets, ...redoSets]) {
      add(x, 1);
    }
    if (counts.length <= maxFar) return false;
    var cut = 0;
    while (cut < _undo.length && counts.length > maxFar && !undoSets[cut].any(visible.contains)) {
      add(undoSets[cut++], -1);
    }
    _undo.removeRange(0, cut);
    var dropped = cut > 0;
    if (counts.length > maxFar && _redo.isNotEmpty) {
      _redo.clear();
      dropped = true;
    }
    return dropped;
  }

  /// La acción a deshacer (queda para rehacer), o null si no hay.
  EditAction? undo() => _move(_undo, _redo);

  /// La acción a rehacer (queda para deshacer), o null si no hay.
  EditAction? redo() => _move(_redo, _undo);

  EditAction? _move(List<EditAction> from, List<EditAction> to) {
    if (from.isEmpty) return null;
    final a = from.removeLast();
    to.add(a);
    return a;
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}
