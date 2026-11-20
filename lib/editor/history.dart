import '../domain/domain.dart';

/// Una acción deshacible: trazos que salieron/entraron y cómo estaban textos y elementos antes/después.
/// En los mapas, null = no existía (antes) o ya no existe (después).
class EditAction {
  final List<Stroke> removed, added;
  final Map<String, TextBlock?> textBefore, textAfter;
  final Map<String, Item?> itemBefore, itemAfter;

  /// Cambios de orden de dibujo: [z] de cada elemento (por id) antes y después.
  final Map<String, int> zBefore, zAfter;
  const EditAction({
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
    final out = <String>{};
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

/// Mapa "no existía / ya no existe" para esos ids.
Map<String, T?> absent<T>(Iterable<String> ids) => {for (final id in ids) id: null};

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

  /// La acción que haría [undo] / [redo], sin hacerla.
  EditAction? peek({required bool undo}) => (undo ? _undo : _redo).lastOrNull;

  /// Ids de las hojas que tocan las acciones del historial (deshacer y rehacer).
  Set<String> sheetIds(NotebookDoc doc) => {
        for (final a in _undo) ...a.sheetIds(doc),
        for (final a in _redo) ...a.sheetIds(doc),
      };

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
