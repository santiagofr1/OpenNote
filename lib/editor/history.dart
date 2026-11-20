import '../domain/domain.dart';

/// Una acción deshacible: trazos que salieron/entraron y cómo estaban textos y elementos antes/después.
/// En los mapas, null = no existía (antes) o ya no existe (después).
class EditAction {
  final List<Stroke> removed, added;
  final Map<String, TextBlock?> textBefore, textAfter;
  final Map<String, Item?> itemBefore, itemAfter;
  const EditAction({
    this.removed = const [],
    this.added = const [],
    this.textBefore = const {},
    this.textAfter = const {},
    this.itemBefore = const {},
    this.itemAfter = const {},
  });

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
    (undo ? textBefore : textAfter).forEach((id, t) => putText(id, t?.copy()));
    (undo ? itemBefore : itemAfter).forEach((id, it) => it == null ? doc.items.remove(id) : doc.items[id] = it.copy());
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
