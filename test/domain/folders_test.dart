import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Inicio ─ Facultad ─ Análisis ─ Parciales
  //        └ Casa
  late NotesIndex idx;
  late Folder fac, ana, par, casa;
  late Notebook a, b, c;

  setUp(() {
    fac = Folder('f1', 'Facultad');
    ana = Folder('f2', 'Análisis', parent: 'f1');
    par = Folder('f3', 'Parciales', parent: 'f2');
    casa = Folder('f4', 'Casa');
    a = Notebook('n1', 'Álgebra', folder: 'f2');
    b = Notebook('n2', 'Recetas', folder: 'f4');
    c = Notebook('n3', 'Suelto');
    idx = NotesIndex(notebooks: [a, b, c], folders: [fac, ana, par, casa]);
  });

  test('childrenOf y notebooksIn: directos, por nombre; null es el inicio', () {
    expect(idx.childrenOf(null).map((f) => f.name), ['Casa', 'Facultad']);
    expect(idx.childrenOf('f1').map((f) => f.id), ['f2']);
    expect(idx.notebooksIn(null), [c]);
    expect(idx.notebooksIn('f2'), [a]);
  });

  test('cuenta de cuadernos incluye las subcarpetas', () {
    expect(idx.notebookCount('f1'), 1);
    expect(idx.notebookCount('f3'), 0);
  });

  test('camino y texto de la ruta', () {
    expect(idx.pathOf('f3').map((f) => f.id), ['f1', 'f2', 'f3']);
    expect(idx.pathOf(null), isEmpty);
    expect(idx.pathLabel('f3'), 'Inicio / Facultad / Análisis / Parciales');
    expect(idx.pathLabel(null), 'Inicio');
  });

  test('mover un cuaderno', () {
    idx.moveNotebook(c, 'f3');
    expect(idx.notebooksIn('f3'), [c]);
    idx.moveNotebook(c, null);
    expect(c.folder, isNull);
  });

  test('mover una carpeta: no se puede meter en sí misma ni en una hija', () {
    expect(idx.moveFolder(fac, 'f1'), isFalse);
    expect(idx.moveFolder(fac, 'f3'), isFalse);
    expect(fac.parent, isNull);
    expect(idx.moveFolder(par, 'f4'), isTrue);
    expect(par.parent, 'f4');
    expect(idx.moveFolder(par, null), isTrue);
    expect(par.parent, isNull);
  });

  test('borrar sacando el contenido: pasa a la carpeta de arriba', () {
    final removed = idx.deleteFolder(ana, FolderDelete.moveContentsToParent);
    expect(removed, isEmpty);
    expect(idx.folders, isNot(contains(ana)));
    expect(par.parent, 'f1');
    expect(a.folder, 'f1');
    expect(idx.notebooks.length, 3);
  });

  test('borrar sacando el contenido de una carpeta del inicio lo manda al inicio', () {
    idx.deleteFolder(fac, FolderDelete.moveContentsToParent);
    expect(ana.parent, isNull);
  });

  test('borrar todo: se van subcarpetas y cuadernos, devuelve los cuadernos', () {
    final removed = idx.deleteFolder(fac, FolderDelete.deleteContents);
    expect(removed, [a]);
    expect(idx.folders, [casa]);
    expect(idx.notebooks, [b, c]);
  });

  test('normalizeSearch: sin tildes ni mayúsculas', () {
    expect(normalizeSearch('ÁLGEBRA Ñandú Pingüino'), 'algebra nandu pinguino');
  });

  test('buscar: en todas las carpetas, sin tildes ni mayúsculas', () {
    final h = idx.search('analisis');
    expect(h.folders, [ana]);
    expect(h.notebooks, isEmpty);
    expect(idx.search('ALGEBRA').notebooks, [a]);
    expect(idx.search('  ').isEmpty, isTrue);
    expect(idx.search('zzz').isEmpty, isTrue);
  });

  test('JSON: ida y vuelta, y los índices sin carpetas siguen cargando', () {
    ana.color = '#336699';
    final j = idx.toJson();
    expect(j['format'], 3);
    final back = NotesIndex.fromJson(j);
    expect(back.folders.map((f) => (f.id, f.name, f.parent, f.color)),
        [('f1', 'Facultad', null, null), ('f2', 'Análisis', 'f1', '#336699'), ('f3', 'Parciales', 'f2', null), ('f4', 'Casa', null, null)]);
    expect(back.notebooks.map((n) => n.folder), ['f2', 'f4', null]);

    final old = NotesIndex.fromJson({'format': 3, 'rev': 1, 'notebooks': [{'id': 'n9', 'name': 'Viejo'}]});
    expect(old.folders, isEmpty);
    expect(old.notebooks.single.folder, isNull);
    expect(NotesIndex().toJson().containsKey('folders'), isFalse);
  });

  test('referencias rotas se reparan al leer', () {
    final j = {
      'format': 3,
      'notebooks': [{'id': 'n1', 'name': 'X', 'folder': 'nada'}],
      'folders': [
        {'id': 'a', 'name': 'A', 'parent': 'b'},
        {'id': 'b', 'name': 'B', 'parent': 'a'},
        {'id': 'c', 'name': 'C', 'parent': 'perdida'},
      ],
    };
    final i = NotesIndex.fromJson(j);
    expect(i.notebooks.single.folder, isNull);
    expect(i.folderById('c')!.parent, isNull);
    for (final f in i.folders) {
      expect(i.pathOf(f.id).length, lessThanOrEqualTo(2));
    }
    expect(i.folders.where((f) => f.parent == null).length, greaterThanOrEqualTo(2));
  });
}
