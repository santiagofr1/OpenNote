import '../../data/storage.dart';
import '../../domain/domain.dart';

/// Miniaturas de las hojas SIN cargar: se leen de disco (una sola hoja, sin cargar el cuaderno) y se guardan
/// las últimas [max] en memoria. La clave incluye `rev` (sube cada vez que se escribe la hoja): si la hoja se
/// cargó, se editó y se guardó, la miniatura vieja ya no sirve.
class SheetThumbCache {
  SheetThumbCache(this.store, {this.max = 16});
  final Storage store;
  final int max;
  final _docs = <String, NotebookDoc>{}; // (en orden de uso: la más vieja primero)
  final _pending = <String, Future<NotebookDoc?>>{};

  String _key(Notebook nb, SheetMeta m) => '${nb.id}/${m.id}#${m.rev}';

  /// Lo que ya hay en la caché (sin leer nada).
  NotebookDoc? peek(Notebook nb, SheetMeta m) {
    final k = _key(nb, m), d = _docs.remove(k);
    if (d != null) _docs[k] = d; // la más reciente al final
    return d;
  }

  /// El documento de una sola hoja de [m] (índice 0 en él); lo lee de disco si no está.
  Future<NotebookDoc?> get(Notebook nb, SheetMeta m) {
    final hit = peek(nb, m);
    if (hit != null) return Future.value(hit);
    final k = _key(nb, m);
    return _pending[k] ??= () async {
      try {
        final d = await store.loadSheetDoc(nb, nb.sheets.indexOf(m));
        if (d != null) {
          _docs[k] = d;
          while (_docs.length > max) {
            _docs.remove(_docs.keys.first);
          }
        }
        return d;
      } finally {
        _pending.remove(k);
      }
    }();
  }

  int get length => _docs.length;
  void clear() => _docs.clear();
}
