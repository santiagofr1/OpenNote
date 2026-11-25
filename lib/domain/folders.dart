import 'notebook.dart';
import 'values.dart';

/// Qué hacer con lo que hay adentro de una carpeta al borrarla.
enum FolderDelete { moveContentsToParent, deleteContents }

/// Una carpeta de la biblioteca. Puede estar adentro de otra ([parent]); null = en el inicio.
class Folder {
  final String id;
  String name;
  String? parent;
  int updated; // ms epoch
  String? color; // '#rrggbb' opcional

  Folder(this.id, this.name, {this.parent, this.updated = 0, this.color});

  /// Carpeta nueva con id propio.
  factory Folder.create(String name, {String? parent}) =>
      Folder(newId('f'), name, parent: parent, updated: DateTime.now().millisecondsSinceEpoch);

  void touch() => updated = DateTime.now().millisecondsSinceEpoch;

  factory Folder.fromJson(Map j) => Folder(
        j['id'] as String,
        (j['name'] ?? '') as String,
        parent: j['parent'] as String?,
        updated: (j['updated'] ?? 0) as int,
        color: j['color'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (parent != null) 'parent': parent,
        'updated': updated,
        if (color != null) 'color': color,
      };
}

/// Minúsculas y sin tildes, para buscar sin importar cómo se escribió ("Análisis" = "analisis").
String normalizeSearch(String s) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final b = StringBuffer();
  for (final r in s.toLowerCase().runes) {
    final c = String.fromCharCode(r);
    final i = from.indexOf(c);
    b.write(i >= 0 ? to[i] : c);
  }
  return b.toString();
}

/// Resultado de buscar en la biblioteca: carpetas y cuadernos que coinciden.
class LibraryHits {
  final List<Folder> folders;
  final List<Notebook> notebooks;
  const LibraryHits(this.folders, this.notebooks);
  bool get isEmpty => folders.isEmpty && notebooks.isEmpty;
}

/// Operaciones de carpetas sobre el índice (datos puros, sin disco).
extension FolderOps on NotesIndex {
  Folder? folderById(String? id) {
    if (id == null) return null;
    for (final f in folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Subcarpetas directas de [parent] (null = inicio), por nombre.
  List<Folder> childrenOf(String? parent) => [for (final f in folders) if (f.parent == parent) f]
    ..sort((a, b) => normalizeSearch(a.name).compareTo(normalizeSearch(b.name)));

  /// Cuadernos que están directamente en [folder] (null = inicio), en el orden del índice.
  List<Notebook> notebooksIn(String? folder) => [for (final n in notebooks) if (n.folder == folder) n];

  /// Ids de todo lo que cuelga de [id] (hijos, nietos…), sin incluirlo.
  Set<String> descendantIds(String id) {
    final out = <String>{};
    final pending = [id];
    while (pending.isNotEmpty) {
      final p = pending.removeLast();
      for (final f in folders) {
        if (f.parent == p && out.add(f.id)) pending.add(f.id);
      }
    }
    return out;
  }

  /// Cuántos cuadernos hay en la carpeta, contando las subcarpetas.
  int notebookCount(String id) {
    final ids = {id, ...descendantIds(id)};
    return notebooks.where((n) => ids.contains(n.folder)).length;
  }

  /// De la raíz hasta [id] (vacía para el inicio): las migas de pan.
  List<Folder> pathOf(String? id) {
    final out = <Folder>[];
    var f = folderById(id);
    while (f != null && !out.contains(f)) {
      out.insert(0, f);
      f = folderById(f.parent);
    }
    return out;
  }

  /// "Inicio" o "Inicio / Facultad / Análisis".
  String pathLabel(String? id, {String home = 'Inicio'}) => [home, ...pathOf(id).map((f) => f.name)].join(' / ');

  /// Mueve un cuaderno a [folder] (null = inicio).
  void moveNotebook(Notebook nb, String? folder) => nb.folder = folder;

  /// Mueve una carpeta adentro de [parent] (null = inicio). false si haría un ciclo
  /// (adentro de sí misma o de una subcarpeta suya) y no cambia nada.
  bool moveFolder(Folder f, String? parent) {
    if (parent == f.id || (parent != null && descendantIds(f.id).contains(parent))) return false;
    f.parent = parent;
    f.touch();
    return true;
  }

  /// Borra la carpeta. Con [FolderDelete.moveContentsToParent] sus cuadernos y subcarpetas pasan a la carpeta
  /// de arriba; con [FolderDelete.deleteContents] se borra todo lo de adentro.
  /// Devuelve los cuadernos que se sacaron del índice (para borrarles los archivos).
  List<Notebook> deleteFolder(Folder f, FolderDelete mode) {
    final removed = <Notebook>[];
    if (mode == FolderDelete.moveContentsToParent) {
      for (final c in folders.where((c) => c.parent == f.id)) {
        c.parent = f.parent;
      }
      for (final n in notebooks.where((n) => n.folder == f.id)) {
        n.folder = f.parent;
      }
    } else {
      final ids = {f.id, ...descendantIds(f.id)};
      removed.addAll(notebooks.where((n) => ids.contains(n.folder)));
      notebooks.removeWhere(removed.contains);
      folders.removeWhere((c) => ids.contains(c.id));
    }
    folders.remove(f);
    return removed;
  }

  /// Busca en TODAS las carpetas por nombre de carpeta y de cuaderno (sin mayúsculas ni tildes).
  LibraryHits search(String query) {
    final q = normalizeSearch(query.trim());
    if (q.isEmpty) return const LibraryHits([], []);
    bool hit(String name) => normalizeSearch(name).contains(q);
    return LibraryHits(
      [for (final f in folders) if (hit(f.name)) f]..sort((a, b) => normalizeSearch(a.name).compareTo(normalizeSearch(b.name))),
      [for (final n in notebooks) if (hit(n.name)) n],
    );
  }

  /// Arregla referencias rotas (carpeta o padre que ya no existe → inicio, ciclos → inicio).
  void repairFolders() {
    final ids = {for (final f in folders) f.id};
    for (final f in folders) {
      if (f.parent != null && !ids.contains(f.parent)) f.parent = null;
    }
    for (final f in folders) {
      if (pathOf(f.id).length != _depth(f)) f.parent = null; // ciclo
    }
    for (final n in notebooks) {
      if (n.folder != null && !ids.contains(n.folder)) n.folder = null;
    }
  }

  int _depth(Folder f) {
    var d = 1;
    var p = folderById(f.parent);
    while (p != null && d <= folders.length) {
      d++;
      p = folderById(p.parent);
    }
    return d;
  }
}
