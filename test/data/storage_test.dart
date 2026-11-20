import 'dart:io';

import 'package:apuntes/data/sheet_codec.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Storage store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('apuntes_unit');
    store = Storage(root: root);
    await store.init();
  });
  tearDown(() => root.delete(recursive: true));

  /// Cuaderno de [n] hojas con un trazo y un texto en cada una.
  NotebookDoc sample(int n, {String name = 'Física'}) {
    final nb = Notebook.create(name);
    while (nb.sheets.length < n) {
      nb.sheets.add(nb.newSheet());
    }
    final d = NotebookDoc(nb);
    for (var k = 0; k < n; k++) {
      d.strokes['s$k'] = Stroke('s$k', 'pen', '#22211e', 2.6, [10, k * kSheetStep + 100, .5, 50, k * kSheetStep + 130, .8]);
      d.texts['t$k'] = TextBlock('t$k', 90, k * kSheetStep + 44, 800, 'hoja $k');
    }
    return d;
  }

  File sheet(Notebook nb, int k) => store.sheetFile(nb.id, nb.sheets[k].id);
  File nbJson(Notebook nb) => File('${store.nbDir(nb.id).path}/notebook.json');

  /// Fecha de modificación (con espera para que dos escrituras seguidas se distingan).
  Future<Map<String, DateTime>> mtimes(Notebook nb) async => {
        for (final e in store.nbDir(nb.id).listSync(recursive: true).whereType<File>()) e.path: e.statSync().modified,
      };

  test('carpetas: ida y vuelta por index.json, con el cuaderno dentro de su carpeta', () async {
    final d = sample(1, name: 'Dentro');
    final f1 = Folder.create('Facultad');
    final f2 = Folder.create('Análisis', parent: f1.id)..color = '#336699';
    d.nb.folder = f2.id;
    await store.saveNotebook(d);
    await store.saveIndex(NotesIndex(notebooks: [d.nb], folders: [f1, f2]));
    final idx = await store.loadIndex();
    expect(idx.folders.map((f) => (f.name, f.parent, f.color)), [('Facultad', null, null), ('Análisis', f1.id, '#336699')]);
    expect(idx.notebooks.single.folder, f2.id);
    expect(idx.pathLabel(f2.id), 'Inicio / Facultad / Análisis');
  });

  test('borrar una carpeta con todo adentro borra los archivos de sus cuadernos', () async {
    final d = sample(1);
    final f = Folder.create('Tmp');
    d.nb.folder = f.id;
    await store.saveNotebook(d);
    final idx = NotesIndex(notebooks: [d.nb], folders: [f]);
    await store.saveIndex(idx);
    for (final nb in idx.deleteFolder(f, FolderDelete.deleteContents)) {
      await store.removeNotebookFiles(nb.id);
    }
    await store.saveIndex(idx);
    expect(await store.nbDir(d.nb.id).exists(), isFalse);
    final back = await store.loadIndex();
    expect(back.notebooks, isEmpty);
    expect(back.folders, isEmpty);
  });

  test('primera vez: crea un cuaderno de ejemplo con una hoja', () async {
    final idx = await store.loadIndex();
    final nb = idx.notebooks.single;
    expect(nb.name, 'Mi cuaderno');
    expect(nb.sheets.length, 1);
    expect(idx.last, nb.id);
    expect(await File('${root.path}/index.json').exists(), isTrue);
    expect(await sheet(nb, 0).exists(), isTrue);
    final again = await store.loadIndex();
    expect(again.notebooks.single.id, nb.id, reason: 'la segunda vez lo lee');
    expect(again.notebooks.single.sheets.single.id, nb.sheets.single.id, reason: 'las hojas vienen de notebook.json');
  });

  test('layout en disco: index.json, notebook.json y un .sheet por hoja', () async {
    final d = sample(3);
    await store.saveNotebook(d);
    final idx = NotesIndex(notebooks: [d.nb]);
    await store.saveIndex(idx);
    final files = store.nbDir(d.nb.id).listSync(recursive: true).whereType<File>().map((f) => f.path.split('/${d.nb.id}/').last).toSet();
    expect(files, {'notebook.json', for (final s in d.sheets) 'sheets/${s.id}.sheet'});
    expect(await File('${root.path}/media').exists() || await Directory('${root.path}/media').exists(), isTrue);
    expect(await File('${root.path}/index.json').readAsString(), contains('"format":3'));
    expect(await File('${root.path}/index.json').readAsString(), isNot(contains('"sheets"')), reason: 'las hojas no van en el índice');
    expect(await nbJson(d.nb).readAsString(), contains('"format":3'));
    expect(store.nbDir(d.nb.id).listSync(recursive: true).where((e) => e.path.endsWith('.tmp')), isEmpty, reason: 'los temporales se renombran');
  });

  test('guardar y leer devuelve lo mismo (en el documento global)', () async {
    final d = sample(3);
    d.items['i'] = Item('i', 'sticky', 5, kSheetStep + 200, 100, 100, text: 'nota');
    d.sheets[1].title = 'Ohm';
    d.sheets[1].bookmark = true;
    await store.saveNotebook(d);
    await store.saveIndex(NotesIndex(notebooks: [d.nb]));

    final store2 = Storage(root: root);
    await store2.init();
    final idx = await store2.loadIndex();
    final nb = idx.notebooks.single;
    expect(nb.sheets.map((s) => s.id), d.sheets.map((s) => s.id));
    final back = await store2.loadNotebook(nb);
    expect(back.sheets[1].title, 'Ohm');
    expect(back.sheets[1].bookmark, isTrue);
    expect(back.sheets[1].rev, 1, reason: 'cada guardado de una hoja sube su rev');
    expect(back.sheets[1].updated, greaterThan(0));
    expect(back.strokes.keys.toSet(), d.strokes.keys.toSet());
    expect(back.strokes['s2']!.pts[1], closeTo(2 * kSheetStep + 100, .05));
    expect(back.texts['t1']!.y, kSheetStep + 44);
    expect(back.items['i']!.text, 'nota');
    expect(back.items['i']!.y, kSheetStep + 200);
  });

  test('guardar solo escribe las hojas que cambiaron (y notebook.json si cambió algo de las hojas)', () async {
    final d = sample(4);
    await store.saveNotebook(d);
    final before = await mtimes(d.nb);
    await Future<void>.delayed(const Duration(milliseconds: 1100));

    // sin cambios: no se escribe nada
    await store.saveNotebook(d);
    expect(await mtimes(d.nb), before, reason: 'nada cambió: ningún archivo se toca');

    // un trazo nuevo en la hoja 2
    d.strokes['nuevo'] = Stroke('nuevo', 'pen', '#22211e', 2, [20, 2 * kSheetStep + 300, .5, 90, 2 * kSheetStep + 310, .5]);
    await store.saveNotebook(d);
    final after = await mtimes(d.nb);
    final changed = {for (final e in after.entries) if (before[e.key] != e.value) e.key.split('/').last};
    expect(changed, {'${d.sheets[2].id}.sheet', 'notebook.json'}, reason: 'solo la hoja tocada y el rev en notebook.json');
    expect(d.sheets[2].rev, 2);
    expect(d.sheets[0].rev, 1);

    // cambio de datos de la hoja (marcador): solo notebook.json
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final b2 = await mtimes(d.nb);
    d.sheets[0].bookmark = true;
    await store.saveNotebook(d);
    final a2 = await mtimes(d.nb);
    expect({for (final e in a2.entries) if (b2[e.key] != e.value) e.key.split('/').last}, {'notebook.json'});
  });

  test('después de leer, guardar sin cambios tampoco escribe (releer y reencodear da los mismos bytes)', () async {
    final d = sample(3);
    await store.saveNotebook(d);
    final store2 = Storage(root: root);
    await store2.init();
    final nb = Notebook(d.nb.id, d.nb.name)..sheets.addAll(d.nb.sheets.map((s) => s.copy()));
    final loaded = await store2.loadNotebook(nb);
    final before = await mtimes(nb);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await store2.saveNotebook(loaded);
    expect(await mtimes(nb), before);
  });

  test('hojas borradas: se borra su archivo', () async {
    final d = sample(3);
    await store.saveNotebook(d);
    final gone = sheet(d.nb, 1);
    expect(await gone.exists(), isTrue);
    d.deleteSheet(1);
    await store.saveNotebook(d);
    expect(await gone.exists(), isFalse);
    expect(store.nbDir(d.nb.id).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.sheet')).length, 2);
  });

  test('mover hojas: cambia notebook.json y las hojas cuyo contenido corrió', () async {
    final d = sample(3);
    await store.saveNotebook(d);
    final ids = d.sheets.map((s) => s.id).toList();
    d.moveSheet(0, 2);
    await store.saveNotebook(d);
    final store2 = Storage(root: root);
    await store2.init();
    final nb = (await store2.loadNotebook(Notebook(d.nb.id, 'x')..sheets.addAll(d.sheets.map((s) => s.copy()))));
    expect(nb.sheets.map((s) => s.id), [ids[1], ids[2], ids[0]]);
    expect(nb.texts['t0']!.y, 2 * kSheetStep + 44);
  });

  test('guardados seguidos: se hacen de a uno y el último estado queda en disco', () async {
    final d = sample(2);
    final futures = <Future<void>>[];
    for (var i = 0; i < 8; i++) {
      d.texts['x$i'] = TextBlock('x$i', 0, 44 + i * 40, 100, 'x$i');
      futures.add(store.saveNotebook(d));
    }
    await Future.wait(futures);
    final nb = Notebook(d.nb.id, 'x')..sheets.addAll(d.sheets.map((s) => s.copy()));
    final s2 = Storage(root: root);
    await s2.init();
    final back = await s2.loadNotebook(nb);
    expect(back.texts.keys.where((k) => k.startsWith('x')).length, 8);
  });

  test('hoja que falta o está rota: vacía, y la rota se aparta en vez de pisarla', () async {
    final d = sample(3);
    await store.saveNotebook(d);
    await sheet(d.nb, 0).delete();
    await sheet(d.nb, 1).writeAsBytes([1, 2, 3, 4, 5]);
    final back = await store.loadNotebook(d.nb);
    expect(back.sheetCount, 3);
    expect(back.texts.keys, ['t2'], reason: 'solo queda la hoja sana');
    expect(await File('${sheet(d.nb, 1).path}.roto').exists(), isTrue);
    expect(() => decodeSheet(File('${sheet(d.nb, 1).path}.roto').readAsBytesSync()), throwsA(isA<SheetFormatException>()));
  });

  test('loadSheetDoc: una sola hoja para la miniatura', () async {
    final d = sample(3);
    await store.saveNotebook(d);
    final one = (await store.loadSheetDoc(d.nb, 2))!;
    expect(one.sheetCount, 1);
    expect(one.texts['t2']!.y, 44, reason: 'coordenadas de esa hoja');
    expect(await store.loadSheetDoc(d.nb, 9), isNull);
  });

  test('prefs', () async {
    expect(await store.loadPrefs(), isNull);
    await store.savePrefs((ToolState()..dock = 'right').toJson());
    expect((ToolState()..load(await store.loadPrefs())).dock, 'right');
  });

  test('deleteNotebook borra la carpeta y lo saca del índice', () async {
    final idx = await store.loadIndex();
    final nb = idx.notebooks.single;
    expect(await store.nbDir(nb.id).exists(), isTrue);
    await store.deleteNotebook(idx, nb);
    expect(await store.nbDir(nb.id).exists(), isFalse);
    expect((await store.loadIndex()).notebooks, isEmpty);
  });

  test('medios: se copian a media/ con nombre nuevo', () async {
    final name = await store.addMedia([1, 2, 3], 'png');
    expect(name, endsWith('.png'));
    expect(await store.media(name).readAsBytes(), [1, 2, 3]);
  });
}
