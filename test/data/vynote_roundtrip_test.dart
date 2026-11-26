import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/data/vynote_file.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exportar un cuaderno a `.vynote` e importarlo tiene que devolver EXACTAMENTE lo mismo (hojas, orden, secciones, fondos,
/// archivos de hojas, media), con cuadernos generados al azar (semillas fijas, reproducibles).
void main() {
  late Directory root;
  late Storage store;

  setUpAll(() => Storage.useIsolates = false);
  tearDownAll(() => Storage.useIsolates = true);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('apuntes_vyn');
    store = Storage(root: root);
    await store.init();
  });
  tearDown(() => root.delete(recursive: true));

  const bgs = ['blank', 'lined', 'grid', 'dots', 'mm', 'axes', 'cornell', 'todo', 'staff', 'weekly', 'monthly'];
  const sizes = ['a4', 'a3', 'a5'];

  /// Un cuaderno al azar guardado en disco: 1 a 3 secciones de 1 a 6 hojas, con trazos, textos, notas, links, imágenes y audios.
  Future<Notebook> randomNotebook(Random r, {bool canvas = false}) async {
    final nb = Notebook.create('Cuaderno ${r.nextInt(1000)} ñ/é', canvas: canvas)
      ..bg = canvas ? 'blank' : bgs[r.nextInt(bgs.length)]
      ..paper = ['#fffefb', '#fde68a', '#dbeafe'][r.nextInt(3)]
      ..size = canvas ? 'a4' : sizes[r.nextInt(3)];
    final nSec = canvas ? 1 : 1 + r.nextInt(3);
    final secs = [nb.activeSection, for (var i = 1; i < nSec; i++) nb.addSection('Sec ${i + 1} "x"')];
    nb.otherSheets.clear();
    nb.sheets.clear();
    final media = <String>[];
    for (var i = 0; i < 3; i++) {
      media.add(await store.addMedia(List.generate(40 + r.nextInt(300), (_) => r.nextInt(256)), i == 0 ? 'm4a' : 'png'));
    }
    for (var si = 0; si < nSec; si++) {
      final n = canvas ? 3 : 1 + r.nextInt(6);
      final list = <SheetMeta>[];
      for (var k = 0; k < n; k++) {
        final m = nb.newSheet(section: secs[si].id)
          ..bg = canvas ? 'blank' : bgs[r.nextInt(bgs.length)]
          ..paper = ['#fffefb', '#fde68a', '#ffffff'][r.nextInt(3)]
          ..size = canvas ? 'a4' : sizes[r.nextInt(3)]
          ..title = r.nextBool() ? 'Hoja $si.$k' : ''
          ..bookmark = r.nextInt(4) == 0;
        list.add(m);
      }
      if (si == 0) {
        nb.sheets.addAll(list);
      } else {
        nb.otherSheets.addAll(list);
      }
    }
    // se escribe sección por sección (cada una abierta como activa)
    final first = nb.activeSection.id;
    for (final s in secs) {
      nb.activate(s.id);
      final d = NotebookDoc(nb);
      for (var k = 0; k < nb.sheets.length; k++) {
        final top = k * kSheetStep;
        for (var j = 0; j < r.nextInt(4); j++) {
          final x = 100.0 + r.nextInt(500), y = top + 100 + r.nextInt(900);
          final id = 's${s.id}$k$j';
          d.strokes[id] = Stroke(id, 'pen', '#22211e', 2.6, [x, y, .5, x + 20, y + 5, .5, x + 40, y + 9, .6])..z = d.nextZ();
        }
        if (r.nextBool()) d.texts['t${s.id}$k'] = TextBlock('t${s.id}$k', 90, d.snapTextY(top + 200), 800, 'Texto ñ "$k" \n 2')..z = d.nextZ();
        if (r.nextBool()) d.items['n${s.id}$k'] = Item('n${s.id}$k', 'sticky', 100, top + 700, 200, 150, text: 'nota $k')..z = d.nextZ();
        if (r.nextBool()) d.items['l${s.id}$k'] = Item('l${s.id}$k', 'link', 100, top + 900, 200, 50, text: 'https://ejemplo.com/$k')..z = d.nextZ();
        if (r.nextBool()) d.items['i${s.id}$k'] = Item('i${s.id}$k', 'image', 300, top + 300, 200, 150, file: media[1])..z = d.nextZ();
        if (r.nextInt(3) == 0) d.items['a${s.id}$k'] = Item('a${s.id}$k', 'audio', 300, top + 1100, 200, 60, file: media[0])..z = d.nextZ();
      }
      await store.saveNotebook(d);
    }
    nb.activate(first);
    return nb;
  }

  Future<Map<String, Uint8List>> sheetBytes(Notebook nb) async => {
        for (final m in nb.allSheets)
          m.id: await store.sheetFile(nb.id, m.id).exists() ? await store.sheetFile(nb.id, m.id).readAsBytes() : Uint8List(0),
      };

  void expectSame(Notebook a, Notebook b, Map<String, Uint8List> aBytes, Map<String, Uint8List> bBytes, String why) {
    expect(b.id, isNot(a.id), reason: 'el importado es un cuaderno NUEVO ($why)');
    expect([for (final s in b.sections) (s.id, s.name)], [for (final s in a.sections) (s.id, s.name)], reason: 'secciones $why');
    expect(b.activeSection.id, a.activeSection.id, reason: 'sección abierta $why');
    expect([for (final m in b.allSheets) m.id], [for (final m in a.allSheets) m.id], reason: 'orden de hojas $why');
    expect(jsonEncode(b.sheetsJson()), jsonEncode(a.sheetsJson()), reason: 'datos de las hojas (fondo, papel, tamaño, título, índice) $why');
    expect([b.bg, b.paper, b.spacing, b.size, b.canvas, b.canvasW], [a.bg, a.paper, a.spacing, a.size, a.canvas, a.canvasW], reason: 'estilo $why');
    for (final id in aBytes.keys) {
      expect(bBytes[id], aBytes[id], reason: 'el archivo de la hoja $id debe ser idéntico $why');
    }
  }

  for (final seed in [1, 2, 3, 4, 5, 6, 7, 8]) {
    test('ida y vuelta exacta (semilla $seed)', () async {
      final r = Random(seed);
      final nb = await randomNotebook(r);
      final bytes = await exportNotebookBytes(store, nb);
      final imp = await importNotebookBytes(store, bytes, taken: {});
      expectSame(nb, imp, await sheetBytes(nb), await sheetBytes(imp), 'semilla $seed');
      expect(imp.name, nb.name);
      // y lo importado se abre y reexporta igual
      final again = await importNotebookBytes(store, await exportNotebookBytes(store, imp), taken: {});
      expectSame(imp, again, await sheetBytes(imp), await sheetBytes(again), 'segunda vuelta, semilla $seed');
      // media: todo lo que usan las hojas viaja en el archivo
      final zip = ZipDecoder().decodeBytes(bytes);
      final inZip = {for (final f in zip) if (f.isFile && f.name.startsWith('media/')) f.name.substring(6)};
      for (final m in nb.allSheets) {
        final d = await store.sheetFile(nb.id, m.id).exists() ? await store.sheetFile(nb.id, m.id).readAsBytes() : null;
        expect(d, isNotNull);
      }
      expect(inZip, isNotEmpty);
      for (final name in inZip) {
        expect(await store.media(name).readAsBytes(), zip.findFile('media/$name')!.content);
      }
    });
  }

  test('lienzo infinito: ancho y tipo se conservan', () async {
    final nb = await randomNotebook(Random(9), canvas: true);
    nb.canvasW = 3500;
    final imp = await importNotebookBytes(store, await exportNotebookBytes(store, nb), taken: {});
    expect(imp.canvas, isTrue);
    expect(imp.canvasW, 3500);
  });

  test('con el documento perezoso y hojas sucias guardadas antes de exportar, lo importado trae lo editado', () async {
    final nb = await randomNotebook(Random(11));
    final doc = await store.openNotebook(nb, radius: 0);
    final n = doc.sheetCount;
    final k = n - 1;
    await store.loadSheets(doc, [doc.sheets[k].id]);
    doc.texts['nuevo'] = TextBlock('nuevo', 90, doc.snapTextY(k * kSheetStep + 300), 800, 'lo último que escribí')..z = doc.nextZ();
    doc.markDirtyElement(doc.texts['nuevo']!);
    await store.saveNotebook(doc); // la pantalla hace flush antes de exportar
    final imp = await importNotebookBytes(store, await exportNotebookBytes(store, nb), taken: {});
    final d2 = await store.openNotebook(imp, radius: 1000);
    expect(d2.texts.values.any((t) => t.text == 'lo último que escribí'), isTrue);
    expect([for (final m in imp.allSheets) m.id], [for (final m in nb.allSheets) m.id]);
  });

  test('nombres repetidos al importar: "(importado)" y sin pisar nada', () async {
    final nb = await randomNotebook(Random(12));
    final bytes = await exportNotebookBytes(store, nb);
    final a = await importNotebookBytes(store, bytes, taken: {nb.name});
    expect(a.name, '${nb.name} (importado)');
    final b = await importNotebookBytes(store, bytes, taken: {nb.name, a.name});
    expect(b.name, isNot(a.name));
    expect(b.id, isNot(a.id));
  });
}
