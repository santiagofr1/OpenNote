import '../domain/domain.dart';

/// Una acción deshacible: trazos que salieron/entraron y cómo estaban textos y elementos antes/después.
/// En los mapas, null = no existía (antes) o ya no existe (después).
class EditAction {
  final List<Stroke> removed, added;
  final Map<String, TextBlock?> textBefore, textAfter;
  final Map<String, Item?> itemBefore, itemAfter;

  /// Cambios de orden de dibujo: [z] de cada elemento (por id) antes y después.
  final Map<String, int> zBefore, zAfter;

  /// Operaciones de hojas (agregar, duplicar, mover, borrar). Se hacen en este orden al rehacer y al revés al deshacer.
  final List<SheetOp> sheetOps;
  const EditAction({
    this.sheetOps = const [],
    this.removed = const [],
    this.added = const [],
    this.textBefore = const {},
    this.textAfter = const {},
    this.itemBefore = const {},
    this.itemAfter = const {},
    this.zBefore = const {},
    this.zAfter = const {},
  });

  /// Ids de las hojas que toca esta acción: donde están ahora y donde estaban (antes/después) sus elementos.
  /// Mientras la acción esté en el historial esas hojas no se pueden descargar: deshacer/rehacer las necesita en memoria.
  Set<String> sheetIds(NotebookDoc doc) {
    final out = <String>{for (final op in sheetOps) ...op.sheetIds(doc)};
    void byId(String id) {
      final s = doc.sheetIdOfElementId(id);
      if (s != null) out.add(s);
    }

    for (final s in [...removed, ...added]) {
      out.addAll(doc.sheetIdsOfRect(s.bounds));
      byId(s.id);
    }
    for (final m in [textBefore, textAfter]) {
      m.forEach((id, t) {
        if (t != null) out.add(doc.sheets[doc.sheetOfY(t.y)].id);
        byId(id);
      });
    }
    for (final m in [itemBefore, itemAfter]) {
      m.forEach((id, it) {
        if (it != null) out.add(doc.sheets[doc.sheetOfY(it.y)].id);
        byId(id);
      });
    }
    zBefore.keys.followedBy(zAfter.keys).forEach(byId);
    return out;
  }

  /// Vuelve la página a como estaba antes ([undo]) o después de la acción.
  /// Los textos pasan por [putText] para que sus campos de edición se enteren.
  void apply(NotebookDoc doc, {required bool undo, required void Function(String id, TextBlock? t) putText}) {
    for (final op in undo ? sheetOps.reversed : sheetOps) {
      op.apply(doc, undo: undo);
    }
    for (final s in undo ? added : removed) {
      doc.strokes.remove(s.id);
    }
    for (final s in undo ? removed : added) {
      doc.strokes[s.id] = s;
    }
    // se aplican copias: lo guardado en la acción no se toca al seguir editando
    (undo ? textBefore : textAfter).forEach((id, t) {
      final cur = doc.texts[id];
      if (cur != null) doc.markDirtyElement(cur); // la hoja de donde sale
      putText(id, t?.copy());
      if (t != null) doc.markDirtyElement(t); // y la de donde queda
    });
    (undo ? itemBefore : itemAfter).forEach((id, it) => it == null ? doc.items.remove(id) : doc.items[id] = it.copy());
    (undo ? zBefore : zAfter).forEach(doc.setZ);
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
      doc.insertSheet(at, meta: meta.copy(), content: content.copy());
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
      for (final m in [a.itemBefore, a.itemAfter]) {
        final it = m[id];
        if (it != null) f(it);
      }
    }
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
