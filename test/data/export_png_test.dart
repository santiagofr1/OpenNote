import 'dart:io';

import 'package:apuntes/data/export.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exportar "Imágenes (PNG)": un PNG por hoja dentro de un ZIP, o el PNG directo si hay una sola hoja.
void main() {
  late Directory root;
  late Storage store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('apuntes_png');
    store = Storage(root: root);
    await store.init();
  });
  tearDown(() => root.delete(recursive: true));

  NotebookDoc sample(int n, String name) {
    final nb = Notebook.create(name);
    while (nb.sheets.length < n) {
      nb.sheets.add(nb.newSheet());
    }
    return NotebookDoc(nb)..texts['t'] = TextBlock('t', 90, 44, 800, 'Hola');
  }

  bool isPng(List<int> b) => b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;

  testWidgets('varias hojas: un ZIP con un PNG por hoja y nombres con ceros', (t) async {
    final doc = sample(3, 'Mi: cuaderno');
    final progress = <int>[];
    final r = await t.runAsync(() => buildNotebookPngs(store, doc, onProgress: (a, b) => progress.add(a)));
    expect(r!.zip, isTrue);
    expect(progress, [0, 1, 2, 3]);
    final files = ZipDecoder().decodeBytes(r.bytes).where((f) => f.isFile).toList();
    expect(files.map((f) => f.name), ['Mi- cuaderno - hoja 01.png', 'Mi- cuaderno - hoja 02.png', 'Mi- cuaderno - hoja 03.png']);
    expect(files.every((f) => isPng(f.content)), isTrue);
  });

  testWidgets('más de 99 hojas: el relleno de ceros crece', (t) async {
    final doc = sample(100, 'Largo');
    final r = await t.runAsync(() => buildNotebookPngs(store, doc));
    final names = ZipDecoder().decodeBytes(r!.bytes).map((f) => f.name).toList();
    expect(names.length, 100);
    expect([names.first, names.last], ['Largo - hoja 001.png', 'Largo - hoja 100.png']);
  });

  testWidgets('una sola hoja: devuelve el PNG directo, sin ZIP', (t) async {
    final r = await t.runAsync(() => buildNotebookPngs(store, sample(1, 'Una')));
    expect(r!.zip, isFalse);
    expect(isPng(r.bytes), isTrue);
  });

  testWidgets('cancelar corta la exportación y no devuelve nada', (t) async {
    final r = await t.runAsync(() => buildNotebookPngs(store, sample(3, 'Cancela'), cancelled: () => true));
    expect(r, isNull);
  });
}
