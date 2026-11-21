import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:apuntes/data/opennote_file.dart';
import 'package:apuntes/data/sheet_codec.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/history.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deshacer / rehacer las operaciones de hojas (agregar, duplicar, mover, borrar) sobre el modelo y el disco,
/// y exportar / importar un cuaderno entero como `.opennote`.
void main() {
  late Directory root;
  late Storage store;
  void noOp(String id, TextBlock? t) {}

  setUp(() async {
    Storage.useIsolates = false;
    root = await Directory.systemTemp.createTemp('apuntes_sheetops');
    store = Storage(root: root);
    await store.init();
  });
  tearDown(() async {
    Storage.useIsolates = true;
    await root.delete(recursive: true);
  });

  /// Cuaderno de [n] hojas con un trazo y un texto en cada una (y título distinto).
  NotebookDoc sample(int n, {String name = 'Física'}) {
    final nb = Notebook.create(name);
    while (nb.sheets.length < n) {
      nb.sheets.add(nb.newSheet());
    }
    for (var k = 0; k < n; k++) {
      nb.sheets[k].title = 'T$k';
    }
    nb.sheets[1].bookmark = true;
    final d = NotebookDoc(nb);
    for (var k = 0; k < n; k++) {
      d.strokes['s$k'] = Stroke('s$k', 'pen', '#22211e', 2.6, [10, k * kSheetStep + 100, .5, 50, k * kSheetStep + 130, .8]);
      d.texts['t$k'] = TextBlock('t$k', 90, k * kSheetStep + 44, 800, 'hoja $k');
    }
    return d;
  }

  /// Orden de las hojas con su contenido local (huella) y sus datos.
  List<String> shape(NotebookDoc d) {
    final parts = d.allLoaded ? d.splitBySheet() : null;
    return [
      for (var k = 0; k < d.sheetCount; k++)
        '${d.sheets[k].id}|${d.sheets[k].title}|${d.sheets[k].bookmark}|${parts == null ? '?' : sheetDigest(parts[k])}'
    ];
  }

  void run(History h, NotebookDoc d, List<SheetOp> ops) => h.push(EditAction(sheetOps: ops));
  void undo(History h, NotebookDoc d) => h.undo()!.apply(d, undo: true, putText: noOp);
  void redo(History h, NotebookDoc d) => h.redo()!.apply(d, undo: false, putText: noOp);

  /// Guarda y lee con otra Storage (todo cargado): lo que hay en disco.
  Future<NotebookDoc> fromDisk(NotebookDoc d) async {
    final s2 = Storage(root: root);
    await s2.init();
    return s2.loadNotebook(Notebook(d.nb.id, d.nb.name)..sheets.addAll(d.sheets.map((m) => m.copy())));
  }

  test('mover: deshacer y rehacer; los trazos no se tocan (son locales a cada hoja)', () {
    final d = sample(4), h = History();
    final before = shape(d), strokesBefore = [for (final s in d.splitBySheet()) sheetDigest(s)];
    run(h, d, [SheetMoveOp.run(d, 0, 2)!]);
    final moved = shape(d);
    expect(moved, isNot(before));
    expect(d.sheets.map((m) => m.title), ['T1', 'T2', 'T0', 'T3']);
    // el contenido de cada hoja es el mismo (solo cambió de lugar)
    expect({for (final s in d.splitBySheet()) sheetDigest(s)}, strokesBefore.toSet());
    undo(h, d);
    expect(shape(d), before);
    redo(h, d);
    expect(shape(d), moved);
    undo(h, d);
    expect(shape(d), before);
  });

  test('agregar y duplicar: deshacer quita la hoja, rehacer la vuelve con su contenido', () {
    final d = sample(3), h = History();
    final before = shape(d);
    final added = d.insertSheet(1);
    run(h, d, [SheetPresenceOp.added(d, added)]);
    final afterAdd = shape(d);
    expect(d.sheetCount, 4);
    final dup = d.duplicateSheet(0);
    run(h, d, [SheetPresenceOp.added(d, dup)]);
    final afterDup = shape(d);
    expect(d.sheetCount, 5);
    expect(d.texts.length, 4);
    undo(h, d);
    expect(shape(d), afterAdd, reason: 'la copia se fue');
    expect(d.texts.length, 3);
    undo(h, d);
    expect(shape(d), before);
    redo(h, d);
    redo(h, d);
    expect(shape(d), afterDup, reason: 'la copia vuelve con su contenido y ids');
    expect(d.texts.length, 4);
  });

  test('borrar: deshacer restaura la hoja con contenido, estilo, título y marcador en su posición', () {
    final d = sample(4), h = History();
    d.nb.sheets[1].bg = 'grid';
    d.nb.sheets[1].paper = '#ffeecc';
    final before = shape(d), meta = d.sheets[1].copy();
    final op = SheetPresenceOp.delete(d, 1)!;
    run(h, d, [op]);
    expect(d.sheetCount, 3);
    expect(d.texts.containsKey('t1'), isFalse);
    // las de abajo subieron: su texto corrió
    expect(d.texts['t2']!.y, 1 * kSheetStep + 44);
    final afterDelete = shape(d);
    undo(h, d);
    expect(shape(d), before);
    final back = d.sheets[1];
    expect((back.id, back.title, back.bookmark, back.bg, back.paper), (meta.id, meta.title, meta.bookmark, meta.bg, meta.paper));
    expect(d.texts['t1']!.text, 'hoja 1');
    expect(d.texts['t1']!.y, 1 * kSheetStep + 44);
    expect(d.strokes.containsKey('s1'), isTrue);
    expect(d.isSheetDirty(back.id), isTrue, reason: 'hay que escribirla de nuevo');
    redo(h, d);
    expect(shape(d), afterDelete);
    undo(h, d);
    expect(shape(d), before);
  });

  test('borrar la primera y la última hoja también se deshace', () {
    for (final i in [0, 3]) {
      final d = sample(4), h = History();
      final before = shape(d);
      run(h, d, [SheetPresenceOp.delete(d, i)!]);
      undo(h, d);
      expect(shape(d), before, reason: 'hoja $i');
    }
  });

  test('no se borra una hoja sin cargar (hay que cargarla antes) ni la única', () {
    final lazy = NotebookDoc.lazy(sample(3).nb);
    expect(SheetPresenceOp.delete(lazy, 1), isNull);
    expect(SheetPresenceOp.delete(NotebookDoc(Notebook.create('x')), 0), isNull);
  });

  test('las hojas de una operación quedan fijadas mientras la acción esté en el historial', () {
    final d = sample(3), h = History();
    final op = SheetPresenceOp.delete(d, 2)!;
    run(h, d, [op]);
    expect(h.sheetIds(d), isEmpty, reason: 'la hoja borrada vive en la acción, no en el documento');
    undo(h, d);
    expect(h.sheetIds(d), {d.sheets[2].id}, reason: 'rehacer la necesita en memoria');
  });

  test('guardado consistente: lo que hay en disco coincide tras borrar, deshacer y rehacer', () async {
    final d = sample(4), h = History();
    await store.saveNotebook(d);
    final goneFile = store.sheetFile(d.id, d.sheets[2].id);
    final before = shape(d);

    run(h, d, [SheetPresenceOp.delete(d, 2)!]);
    await store.saveNotebook(d);
    expect(await goneFile.exists(), isFalse);
    expect(shape(await fromDisk(d)), shape(d));

    undo(h, d);
    await store.saveNotebook(d);
    expect(await goneFile.exists(), isTrue, reason: 'el archivo de la hoja restaurada se escribió de nuevo');
    expect(shape(await fromDisk(d)), before);

    redo(h, d);
    await store.saveNotebook(d);
    expect(shape(await fromDisk(d)), shape(d));
    undo(h, d);
    await store.saveNotebook(d);
    expect(shape(await fromDisk(d)), before);
  });

  test('deshacer antes de guardar el borrado: la hoja vuelve igual aunque en disco hubiera algo viejo', () async {
    final d = sample(3), h = History();
    await store.saveNotebook(d);
    // se edita la hoja 1 (sin guardar) y se la borra; deshacer tiene que escribir lo editado, no lo viejo
    d.texts['t1']!.text = 'editada';
    d.markDirtyElement(d.texts['t1']!);
    run(h, d, [SheetPresenceOp.delete(d, 1)!]);
    undo(h, d);
    await store.saveNotebook(d);
    expect((await fromDisk(d)).texts['t1']!.text, 'editada');
  });

  test('mover, agregar y duplicar: el disco coincide después de cada deshacer / rehacer', () async {
    final d = sample(3), h = History();
    await store.saveNotebook(d);
    run(h, d, [SheetMoveOp.run(d, 2, 0)!]);
    await store.saveNotebook(d);
    expect(shape(await fromDisk(d)), shape(d));
    run(h, d, [SheetPresenceOp.added(d, d.duplicateSheet(1))]);
    await store.saveNotebook(d);
    expect(shape(await fromDisk(d)), shape(d));
    undo(h, d);
    undo(h, d);
    await store.saveNotebook(d);
    final disk = await fromDisk(d);
    expect(shape(disk), shape(d));
    expect(disk.sheets.map((m) => m.title), ['T0', 'T1', 'T2']);
    redo(h, d);
    redo(h, d);
    await store.saveNotebook(d);
    expect(shape(await fromDisk(d)), shape(d));
    expect(Directory('${store.nbDir(d.id).path}/sheets').listSync().whereType<File>().length, 4);
  });

  test('borrar una hoja que no estaba cargada: se carga, se borra, y deshacer devuelve su contenido de disco', () async {
    final src = sample(6);
    await store.saveNotebook(src);
    final nb = Notebook(src.id, src.nb.name)..sheets.addAll(src.sheets.map((m) => m.copy()));
    final doc = await store.openNotebook(nb, radius: 0); // solo la hoja 0 cargada
    expect(doc.isLoadedAt(4), isFalse);
    final id = doc.sheets[4].id, disk = store.sheetFile(doc.id, id), bytes = await disk.readAsBytes();
    // igual que la pantalla: primero se carga
    await store.loadSheets(doc, [id]);
    final h = History();
    run(h, doc, [SheetPresenceOp.delete(doc, 4)!]);
    await store.saveNotebook(doc);
    expect(await disk.exists(), isFalse);
    undo(h, doc);
    await store.saveNotebook(doc);
    expect(await disk.exists(), isTrue);
    expect(sheetDigest(decodeSheet(await disk.readAsBytes())), sheetDigest(decodeSheet(bytes)));
    expect(doc.texts['t4']!.text, 'hoja 4');
    // las demás hojas sin cargar no se escribieron
    expect(doc.isLoadedAt(5), isFalse);
  });

  test('con hojas sin cargar: mover y deshacer no tocan los archivos de las no cargadas', () async {
    final src = sample(6);
    await store.saveNotebook(src);
    final nb = Notebook(src.id, src.nb.name)..sheets.addAll(src.sheets.map((m) => m.copy()));
    final doc = await store.openNotebook(nb, radius: 0);
    final before = {for (final m in doc.sheets) m.id: await store.sheetFile(doc.id, m.id).readAsBytes()};
    final h = History();
    run(h, doc, [SheetMoveOp.run(doc, 5, 0)!]);
    await store.saveNotebook(doc);
    undo(h, doc);
    await store.saveNotebook(doc);
    for (final m in doc.sheets) {
      expect(await store.sheetFile(doc.id, m.id).readAsBytes(), before[m.id], reason: 'hoja ${m.id}');
    }
    expect(doc.sheets.map((m) => m.id), src.sheets.map((m) => m.id));
  });

  group('.opennote', () {
    Future<NotebookDoc> seeded() async {
      final d = sample(3);
      d.items['i1'] = Item('i1', 'image', 20, kSheetStep + 50, 200, 100, file: 'm_foto.png');
      await store.media('m_foto.png').writeAsBytes([1, 2, 3, 4]);
      await store.media('m_otra.png').writeAsBytes([9, 9]);
      await store.saveNotebook(d);
      await store.saveIndex(NotesIndex(notebooks: [d.nb]));
      return d;
    }

    test('ida y vuelta: mismo contenido, id distinto, nombre "(importado)" si choca y media incluida', () async {
      final d = await seeded();
      final bytes = await exportNotebookBytes(store, d.nb);
      final names = ZipDecoder().decodeBytes(bytes).map((f) => f.name).toSet();
      expect(names, containsAll(['manifest.json', 'notebook.json', 'media/m_foto.png']));
      expect(names, isNot(contains('media/m_otra.png')), reason: 'solo la media que usa el cuaderno');
      expect(names.where((n) => n.endsWith('.sheet')).length, 3);

      // en otro almacenamiento (sin la media): se copia
      final root2 = await Directory.systemTemp.createTemp('apuntes_import');
      addTearDown(() => root2.delete(recursive: true));
      final store2 = Storage(root: root2);
      await store2.init();
      final nb2 = await importNotebookBytes(store2, bytes, taken: {}, folder: null);
      expect(nb2.id, isNot(d.nb.id));
      expect(nb2.name, 'Física');
      expect(await store2.media('m_foto.png').readAsBytes(), [1, 2, 3, 4]);
      final back = await store2.loadNotebook(Notebook(nb2.id, nb2.name)..sheets.addAll(nb2.sheets.map((m) => m.copy())));
      expect(shape(back), shape(d));
      expect(back.items['i1']!.file, 'm_foto.png');

      // en el mismo: el nombre choca
      final nb3 = await importNotebookBytes(store, bytes, taken: {'Física'});
      expect(nb3.name, 'Física (importado)');
      expect(nb3.id, isNot(d.nb.id));
      final nb4 = await importNotebookBytes(store, bytes, taken: {'Física', 'Física (importado)'});
      expect(nb4.name, 'Física (importado 2)');
      // el original no se tocó
      expect(shape(await fromDisk(d)), shape(d));
    });

    test('exporta las hojas sin cargar desde disco, sin cargarlas', () async {
      final d = await seeded();
      final nb = Notebook(d.id, d.nb.name)..sheets.addAll(d.sheets.map((m) => m.copy()));
      final doc = await store.openNotebook(nb, radius: 0);
      final bytes = await exportNotebookBytes(store, doc.nb);
      expect(doc.loadedSheets.length, 1);
      final nb2 = await importNotebookBytes(store, bytes, taken: {d.nb.name});
      final back = await store.loadNotebook(Notebook(nb2.id, nb2.name)..sheets.addAll(nb2.sheets.map((m) => m.copy())));
      expect(back.texts.length, 3);
    });

    test('archivos rotos se rechazan sin dejar nada en disco', () async {
      final d = await seeded();
      final good = await exportNotebookBytes(store, d.nb);
      final before = Directory('${root.path}/notebooks').listSync().length;

      Uint8List zipOf(Map<String, List<int>> files) {
        final a = Archive();
        files.forEach((k, v) => a.add(ArchiveFile.bytes(k, v)));
        return Uint8List.fromList(ZipEncoder().encode(a));
      }

      Map<String, List<int>> parts() => {for (final f in ZipDecoder().decodeBytes(good)) f.name: f.readBytes()!};
      List<int> json(Object o) => utf8.encode(jsonEncode(o));

      final bad = <String, Uint8List>{
        'no es un zip': Uint8List.fromList([1, 2, 3, 4, 5]),
        'vacío': Uint8List(0),
        'zip cortado': Uint8List.sublistView(good, 0, good.length ~/ 2),
        'sin manifest': zipOf({...parts()}..remove('manifest.json')),
        'manifest de otra app': zipOf({...parts(), 'manifest.json': json({'app': 'Otra', 'format': 1})}),
        'versión más nueva': zipOf({...parts(), 'manifest.json': json({'app': 'OpenNote', 'format': 99})}),
        'manifest ilegible': zipOf({...parts(), 'manifest.json': [0xff, 0xfe, 1]}),
        'sin notebook.json': zipOf({...parts()}..remove('notebook.json')),
        'sin hojas': zipOf({...parts(), 'notebook.json': json({'format': 3, 'sheets': []})}),
        'id de hoja con ruta': zipOf({
          ...parts(),
          'notebook.json': json({'format': 3, 'sheets': [{'id': '../../x'}]})
        }),
        'hoja rota': zipOf({
          for (final e in parts().entries) e.key: e.key.endsWith('.sheet') ? [1, 2, 3, 4, 5, 6, 7, 8] : e.value
        }),
        'media con ruta': zipOf({...parts(), 'media/../../evil.txt': [1]}),
      };
      for (final e in bad.entries) {
        expect(() => importNotebookBytes(store, e.value, taken: {}), throwsA(isA<OpennoteException>()), reason: e.key);
      }
      expect(Directory('${root.path}/notebooks').listSync().length, before, reason: 'no quedó ningún cuaderno a medias');
      expect(File('${root.path}/evil.txt').existsSync(), isFalse);
    });
  });
}
