import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:apuntes/data/export.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as im;

import '../helpers/export_check.dart';

/// Exportar "Imágenes (PNG)": el PNG k tiene que ser la hoja k (comprobado en píxeles con una marca única por hoja), con
/// los nombres y el orden esperados, en cualquier estado de carga del documento.
void main() {
  late Directory root;
  late Storage store;

  setUpAll(() => Storage.useIsolates = false);
  tearDownAll(() => Storage.useIsolates = true);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('apuntes_png_marks');
    store = Storage(root: root);
    await store.init();
  });
  tearDown(() => root.delete(recursive: true));

  void rt(String name, Future<void> Function() body) => testWidgets(name, (t) async => t.runAsync(body));

  Future<NotebookDoc> saved(int n, {String name = 'Marcas', String bg = 'grid'}) async {
    final nb = Notebook.create(name)..bg = bg;
    nb.sheets.clear();
    while (nb.sheets.length < n) {
      nb.sheets.add(nb.newSheet());
    }
    final d = NotebookDoc(nb);
    for (var k = 0; k < n; k++) {
      Marks.add(d, k, k);
    }
    await store.saveNotebook(d);
    return d;
  }

  List<ArchiveFile> zipFiles(Uint8List b) => ZipDecoder().decodeBytes(b).where((f) => f.isFile).toList();
  im.Image png(ArchiveFile f) => im.decodePng(Uint8List.fromList(f.content as List<int>))!;

  rt('el PNG k es la hoja k, con y sin fondo, con huecos sin cargar', () async {
    final ref = await saved(9);
    for (final seed in [1, 2, 3]) {
      final r = Random(seed);
      final doc = await store.openNotebook(Notebook(ref.id, 'Marcas'), radius: 1000);
      for (var k = 0; k < 9; k++) {
        if (r.nextBool()) doc.detachSheet(doc.sheets[k].id);
      }
      for (final bg in [true, false]) {
        final res = (await buildNotebookPngs(store, doc, background: bg))!;
        expect(res.zip, isTrue);
        final files = zipFiles(res.bytes);
        expect([for (final f in files) f.name], [for (var k = 1; k <= 9; k++) 'Marcas - hoja 0$k.png']);
        for (var k = 0; k < 9; k++) {
          expect(Marks.found(png(files[k]), List.generate(9, (i) => i)), [k], reason: 'PNG ${k + 1} (semilla $seed, fondo $bg)');
        }
      }
    }
  });

  rt('una sola hoja: el PNG directo es esa hoja', () async {
    final doc = await saved(1);
    final res = (await buildNotebookPngs(store, doc))!;
    expect(res.zip, isFalse);
    expect(Marks.has(im.decodePng(res.bytes)!, 0), isTrue);
  });

  rt('varias secciones, con nombres repetidos y raros: nombres únicos y cada PNG con su hoja', () async {
    final nb = Notebook.create('Cuad/erno:?')..bg = 'lined';
    final a = nb.activeSection..name = 'Igual';
    final b = nb.addSection('Igual'), c = nb.addSection('a<b>|c');
    nb.otherSheets.clear();
    nb.sheets.clear();
    nb.sheets.addAll([nb.newSheet(), nb.newSheet()]);
    nb.otherSheets.addAll([nb.newSheet(section: b.id), nb.newSheet(section: c.id), nb.newSheet(section: c.id)]);
    for (final (sec, base, n) in [(a, 0, 2), (b, 10, 1), (c, 20, 2)]) {
      nb.activate(sec.id);
      final d = NotebookDoc(nb);
      for (var k = 0; k < n; k++) {
        Marks.add(d, k, base + k);
      }
      await store.saveNotebook(d);
    }
    nb.activate(a.id);
    final doc = await store.openNotebook(nb, radius: 0);
    final res = (await buildNotebookPngs(store, doc))!;
    final files = zipFiles(res.bytes);
    expect([for (final f in files) f.name], [
      'Cuad-erno-- - Igual - hoja 01.png',
      'Cuad-erno-- - Igual - hoja 02.png',
      'Cuad-erno-- - Igual - hoja 01 (2).png',
      'Cuad-erno-- - a-b--c - hoja 01.png',
      'Cuad-erno-- - a-b--c - hoja 02.png',
    ]);
    const marks = [0, 1, 10, 20, 21];
    for (var i = 0; i < 5; i++) {
      expect(Marks.found(png(files[i]), marks), [marks[i]], reason: 'PNG ${i + 1}');
    }
    // solo algunas secciones
    final some = zipFiles((await buildNotebookPngs(store, doc, sections: {c.id, a.id}))!.bytes);
    expect(some.length, 4);
    expect([for (final f in some) Marks.found(png(f), marks).single], [0, 1, 20, 21]);
  });

  rt('cancelar a mitad no devuelve nada, y el progreso cuenta hoja por hoja', () async {
    final doc = await saved(6);
    var seen = 0;
    final res = await buildNotebookPngs(store, doc, onProgress: (a, b) => seen = a, cancelled: () => seen >= 3);
    expect(res, isNull);
    expect(seen, 3);
    final progress = <int>[];
    await buildNotebookPngs(store, doc, onProgress: (a, b) => progress.add(a));
    expect(progress, [0, 1, 2, 3, 4, 5, 6]);
  });
}
