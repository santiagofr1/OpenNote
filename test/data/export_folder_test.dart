import 'dart:io';

import 'package:apuntes/data/export_folder.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exportar una carpeta entera en un .zip: rutas de los cuadernos y armado del archivo.
void main() {
  List<String> paths(NotesIndex idx, String folder) =>
      [for (final e in folderExportEntries(idx, idx.folders.firstWhere((f) => f.id == folder))) e.path];

  group('folderExportEntries', () {
    test('cuadernos primero, después subcarpetas a fondo; nombres saneados', () {
      final idx = NotesIndex(
        folders: [
          Folder('f1', 'Facultad'),
          Folder('f3', 'Zeta', parent: 'f1'),
          Folder('f2', 'Análisis', parent: 'f1'),
          Folder('f4', 'Final', parent: 'f2'),
        ],
        notebooks: [
          Notebook('n4', 'Profundo', folder: 'f4'),
          Notebook('n3', 'Parcial 1', folder: 'f2'),
          Notebook('n1', 'a/b:c', folder: 'f1'),
          Notebook('n2', 'Teoría', folder: 'f1'),
          Notebook('n5', 'Afuera'),
          Notebook('n6', 'En Zeta', folder: 'f3'),
        ],
      );
      expect(paths(idx, 'f1'), [
        'Facultad/a-b-c',
        'Facultad/Teoría',
        'Facultad/Análisis/Parcial 1',
        'Facultad/Análisis/Final/Profundo',
        'Facultad/Zeta/En Zeta',
      ]);
    });

    test('repetidos sin importar mayúsculas llevan (2), (3); cuaderno y subcarpeta chocan', () {
      final idx = NotesIndex(
        folders: [Folder('f1', 'Raíz'), Folder('f2', 'Apuntes', parent: 'f1'), Folder('f3', 'apuntes', parent: 'f1')],
        notebooks: [
          Notebook('n1', 'Clase', folder: 'f1'),
          Notebook('n2', 'clase', folder: 'f1'),
          Notebook('n3', 'CLASE', folder: 'f1'),
          Notebook('n4', 'Apuntes', folder: 'f1'),
          Notebook('n5', 'Uno', folder: 'f2'),
          Notebook('n6', 'Dos', folder: 'f3'),
        ],
      );
      expect(paths(idx, 'f1'), [
        'Raíz/Clase',
        'Raíz/clase (2)',
        'Raíz/CLASE (3)',
        'Raíz/Apuntes',
        'Raíz/Apuntes (2)/Uno',
        'Raíz/apuntes (3)/Dos',
      ]);
    });

    test('nombres vacíos', () {
      final idx = NotesIndex(
        folders: [Folder('f1', '  '), Folder('f2', '', parent: 'f1')],
        notebooks: [Notebook('n1', '', folder: 'f1'), Notebook('n2', ' ', folder: 'f2')],
      );
      expect(paths(idx, 'f1'), ['Carpeta/Cuaderno', 'Carpeta/Carpeta/Cuaderno']);
    });
  });

  group('buildFolderZip', () {
    late Directory root, tmp;
    late Storage store;
    late NotesIndex idx;
    late Folder fac;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('apuntes_fzip');
      tmp = await Directory.systemTemp.createTemp('apuntes_fzip_tmp');
      store = Storage(root: root);
      await store.init();
      fac = Folder('f1', 'Facultad');
      final ana = Folder('f2', 'Análisis', parent: 'f1');
      final a = Notebook.create('Álgebra')..folder = 'f1';
      final b = Notebook.create('Parcial')..folder = 'f2';
      b.sheets.add(b.newSheet());
      idx = NotesIndex(folders: [fac, ana], notebooks: [a, b, Notebook.create('Afuera')]);
      for (final nb in idx.notebooks) {
        await store.saveNotebook(NotebookDoc(nb)..texts['t'] = TextBlock('t', 90, 44, 800, 'Hola'));
      }
      await store.saveIndex(idx);
    });
    tearDown(() async {
      await root.delete(recursive: true);
      await tmp.delete(recursive: true);
    });

    Future<List<ArchiveFile>> zipOf(WidgetTester t, FolderExportFormat fmt, {List<(int, int, String)>? progress}) async {
      final f = await t.runAsync(() => buildFolderZip(store, idx, fac, fmt,
          tmp: tmp, onProgress: progress == null ? null : (a, b, n) => progress.add((a, b, n))));
      expect(f, isNotNull);
      final bytes = await t.runAsync(() => f!.readAsBytes());
      return ZipDecoder().decodeBytes(bytes!).where((e) => e.isFile).toList();
    }

    testWidgets('opennote: un .opennote por cuaderno respetando carpetas', (t) async {
      final progress = <(int, int, String)>[];
      final files = await zipOf(t, FolderExportFormat.opennote, progress: progress);
      expect(files.map((f) => f.name), ['Facultad/Álgebra.opennote', 'Facultad/Análisis/Parcial.opennote']);
      expect(files.every((f) => f.content.isNotEmpty), isTrue);
      expect(progress, [(0, 2, 'Álgebra'), (1, 2, 'Parcial'), (2, 2, '')]);
    });

    testWidgets('pdf: un PDF por cuaderno', (t) async {
      final files = await zipOf(t, FolderExportFormat.pdf);
      expect(files.map((f) => f.name), ['Facultad/Álgebra.pdf', 'Facultad/Análisis/Parcial.pdf']);
      for (final f in files) {
        expect(String.fromCharCodes(f.content.take(4)), '%PDF');
      }
    });

    testWidgets('png: una carpeta por cuaderno con una imagen por hoja', (t) async {
      final files = await zipOf(t, FolderExportFormat.png);
      expect(files.map((f) => f.name), [
        'Facultad/Álgebra/Álgebra - hoja 01.png',
        'Facultad/Análisis/Parcial/Parcial - hoja 01.png',
        'Facultad/Análisis/Parcial/Parcial - hoja 02.png',
      ]);
      expect(files.every((f) => f.content.length > 8 && f.content[1] == 0x50), isTrue);
    });

    testWidgets('cancelar devuelve null y no deja el archivo', (t) async {
      final f = await t.runAsync(() => buildFolderZip(store, idx, fac, FolderExportFormat.opennote, tmp: tmp, cancelled: () => true));
      expect(f, isNull);
      final left = await t.runAsync(() => Directory('${tmp.path}/opennote-export').list().toList());
      expect(left, isEmpty);
    });
  });
}
