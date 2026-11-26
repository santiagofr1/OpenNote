import 'dart:io';
import 'dart:typed_data';

import 'package:apuntes/data/export_folder.dart';
import 'package:apuntes/data/import_folder.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as im;

import '../helpers/export_check.dart';

/// Exportar una carpeta (PDF, PNG y .vynote) con subcarpetas, nombres repetidos o raros, cuadernos vacíos y un lienzo
/// infinito: cada archivo tiene SUS hojas en orden, y la carpeta en .vynote se importa de nuevo igual.
void main() {
  late Directory root, tmp;
  late Storage store;
  late NotesIndex idx;
  late Folder top;

  setUpAll(() => Storage.useIsolates = false);
  tearDownAll(() => Storage.useIsolates = true);

  void rt(String name, Future<void> Function() body, {bool skip = false}) => testWidgets(name, (t) async => t.runAsync(body), skip: skip);

  // cada cuaderno de la carpeta lleva marcas distintas: (nombre, carpeta, hojas, primera marca)
  Future<void> build() async {
    root = await Directory.systemTemp.createTemp('apuntes_fm');
    tmp = await Directory.systemTemp.createTemp('apuntes_fm_tmp');
    store = Storage(root: root);
    await store.init();
    top = Folder('f1', 'Facu/ltad');
    final sub = Folder('f2', 'Análisis', parent: 'f1'), sub2 = Folder('f3', 'analisis', parent: 'f1');
    final specs = <(String, String, int, int)>[
      ('Parcial', 'f1', 3, 0),
      ('parcial', 'f1', 2, 10), // mismo nombre sin importar mayúsculas
      ('???', 'f1', 1, 20), // nombre raro
      ('Vacío', 'f2', 1, -1), // sin marca
      ('Final', 'f2', 4, 30),
      ('Final', 'f3', 2, 40),
    ];
    final nbs = <Notebook>[];
    for (final (name, folder, n, base) in specs) {
      final nb = Notebook.create(name)
        ..folder = folder
        ..bg = 'dots';
      nb.sheets.clear();
      while (nb.sheets.length < n) {
        nb.sheets.add(nb.newSheet());
      }
      final d = NotebookDoc(nb);
      if (base >= 0) {
        for (var k = 0; k < n; k++) {
          Marks.add(d, k, base + k);
        }
      }
      await store.saveNotebook(d);
      nbs.add(nb);
    }
    final canvas = Notebook.create('Lienzo', canvas: true)..folder = 'f3';
    canvas.sheets.add(canvas.newSheet());
    final cd = NotebookDoc(canvas);
    final s = Marks.stroke('c0', 50, 0)..z = cd.nextZ();
    cd.strokes[s.id] = s;
    await store.saveNotebook(cd);
    nbs.add(canvas);
    idx = NotesIndex(folders: [top, sub, sub2], notebooks: nbs);
    await store.saveIndex(idx);
  }

  Future<List<ArchiveFile>> zipOf(FolderExportFormat f) async {
    final file = (await buildFolderZip(store, idx, top, f, tmp: tmp))!;
    return ZipDecoder().decodeBytes(await file.readAsBytes()).where((e) => e.isFile).toList();
  }

  tearDown(() async {
    await root.delete(recursive: true);
    await tmp.delete(recursive: true);
  });

  final skip = !hasPdfImages;

  rt('PDF: un PDF por cuaderno con sus hojas en orden', () async {
    await build();
    final files = await zipOf(FolderExportFormat.pdf);
    final names = [for (final f in files) f.name];
    expect(names, [
      'Facu-ltad/Parcial.pdf',
      'Facu-ltad/parcial (2).pdf',
      'Facu-ltad/---.pdf',
      'Facu-ltad/Análisis/Vacío.pdf',
      'Facu-ltad/Análisis/Final.pdf',
      'Facu-ltad/analisis/Final.pdf',
      'Facu-ltad/analisis/Lienzo.pdf',
    ]);
    final want = {
      'Parcial': [0, 1, 2],
      'parcial (2)': [10, 11],
      '---': [20],
      'Final': [30, 31, 32, 33],
    };
    for (final f in files) {
      final base = f.name.split('/').last.replaceAll('.pdf', '');
      final pdf = Uint8List.fromList(f.content as List<int>);
      if (f.name.contains('analisis/Final')) {
        expect(pdfPageCount(pdf), 2);
        final pages = await pdfPageImages(pdf);
        expect([for (final p in pages) Marks.found(p, [40, 41]).single], [40, 41]);
      } else if (base == 'Vacío') {
        expect(pdfPageCount(pdf), 1);
        expect(Marks.found((await pdfPageImages(pdf)).single, List.generate(60, (i) => i)), isEmpty);
      } else if (base == 'Lienzo') {
        expect(Marks.has((await pdfPageImages(pdf)).single, 50), isTrue);
      } else {
        final pages = await pdfPageImages(pdf);
        expect(pages.length, want[base]!.length, reason: base);
        for (var i = 0; i < pages.length; i++) {
          expect(Marks.found(pages[i], want[base]!), [want[base]![i]], reason: '$base página ${i + 1}');
        }
      }
    }
  }, skip: skip);

  rt('PNG: una carpeta por cuaderno y cada imagen es su hoja', () async {
    await build();
    final files = await zipOf(FolderExportFormat.png);
    final byName = {for (final f in files) f.name: f};
    expect(byName.keys, containsAll(['Facu-ltad/Parcial/Parcial - hoja 01.png', 'Facu-ltad/parcial (2)/parcial - hoja 02.png', 'Facu-ltad/Análisis/Final/Final - hoja 04.png']));
    const bases = {
      'Facu-ltad/Parcial': 0,
      'Facu-ltad/parcial (2)': 10,
      'Facu-ltad/---': 20,
      'Facu-ltad/Análisis/Final': 30,
      'Facu-ltad/analisis/Final': 40,
    };
    for (final e in byName.entries) {
      final m = RegExp(r'^(.*)/[^/]+ - (?:hoja|página) (\d+)\.png$').firstMatch(e.key);
      expect(m, isNotNull, reason: e.key);
      final base = bases[m!.group(1)];
      final img = im.decodePng(Uint8List.fromList(e.value.content as List<int>))!;
      if (base == null) {
        // el cuaderno vacío y el lienzo
        expect(Marks.found(img, List.generate(60, (i) => i)), m.group(1)!.endsWith('Lienzo') ? [50] : isEmpty, reason: e.key);
        continue;
      }
      expect(Marks.found(img, List.generate(60, (i) => i)), [base + int.parse(m.group(2)!) - 1], reason: e.key);
    }
    expect(files.length, 3 + 2 + 1 + 1 + 4 + 2 + 1);
  });

  rt('.vynote: la carpeta se importa de nuevo con los mismos cuadernos y hojas', () async {
    await build();
    final file = (await buildFolderZip(store, idx, top, FolderExportFormat.vynote, tmp: tmp))!;
    final bytes = await file.readAsBytes();
    final root2 = await Directory.systemTemp.createTemp('apuntes_fm2');
    final store2 = Storage(root: root2);
    await store2.init();
    final idx2 = NotesIndex();
    final r = await importFolderZip(store2, idx2, bytes);
    expect(r.failed, isEmpty);
    expect(r.imported, 7);
    for (final a in idx.notebooks) {
      final b = idx2.notebooks.singleWhere((n) => n.name == a.name && n.sheets.length == a.sheets.length && n.canvas == a.canvas && (idx2.folders.firstWhere((f) => f.id == n.folder).name.toLowerCase() == idx.folders.firstWhere((f) => f.id == a.folder).name.toLowerCase().replaceAll('/', '-')));
      for (var k = 0; k < a.sheets.length; k++) {
        expect(await store2.sheetFile(b.id, b.sheets[k].id).exists(), await store.sheetFile(a.id, a.sheets[k].id).exists());
        if (await store.sheetFile(a.id, a.sheets[k].id).exists()) {
          expect(await store2.sheetFile(b.id, b.sheets[k].id).readAsBytes(), await store.sheetFile(a.id, a.sheets[k].id).readAsBytes(), reason: '${a.name} hoja ${k + 1}');
        }
      }
    }
    await root2.delete(recursive: true);
  });
}
