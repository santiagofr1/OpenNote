import 'dart:convert';
import 'dart:io';

import 'package:apuntes/data/export.dart';
import 'package:apuntes/data/opennote_file.dart';
import 'package:apuntes/data/sheet_codec.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/sync/sync_merge.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

/// Secciones dentro de un cuaderno: modelo, notebook.json, REGLA DE ORO (nunca borrar ni pisar las hojas de otra sección),
/// duplicar, `.opennote`, exportar y fusión de la sync.
void main() {
  late Directory root;
  late Storage store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('apuntes_sections');
    store = Storage(root: root);
    await store.init();
  });
  tearDown(() => root.delete(recursive: true));

  File nbJson(Notebook nb) => File('${store.nbDir(nb.id).path}/notebook.json');
  Map readJson(Notebook nb) => jsonDecode(nbJson(nb).readAsStringSync()) as Map;

  /// Cuaderno con la sección "General" (con un trazo en su hoja) abierto, y su doc.
  Future<(Notebook, NotebookDoc)> make() async {
    final nb = Notebook.create('Física');
    final d = NotebookDoc(nb);
    d.strokes['a0'] = Stroke('a0', 'pen', '#22211e', 2.6, [10, 100, .5, 50, 130, .8]);
    await store.saveNotebook(d);
    return (nb, d);
  }

  /// Agrega la sección [name] con un trazo `id` en su hoja y la deja guardada; vuelve a abrir la sección [back].
  Future<Section> addWithStroke(Notebook nb, String name, String id, {required String back}) async {
    final s = nb.addSection(name);
    var d = await store.openSection(nb, s.id);
    d.strokes[id] = Stroke(id, 'pen', '#cc0000', 3, [20, 200, .5, 90, 240, .8]);
    d.markDirtyElement(d.strokes[id]!);
    await store.saveNotebook(d);
    d = await store.openSection(nb, back);
    return s;
  }

  group('modelo y notebook.json', () {
    test('ida y vuelta con secciones, hojas agrupadas y la activa', () async {
      final (nb, _) = await make();
      final b = nb.addSection('Práctica')..last = 0;
      nb.activate(b.id);
      nb.sheets.add(nb.newSheet());
      nb.last = 1;
      final j = jsonDecode(jsonEncode(nb.sheetsJson())) as Map;
      expect((j['sections'] as List).map((e) => (e as Map)['name']), ['General', 'Práctica']);
      expect(j['active'], b.id);
      expect((j['sheets'] as List).map((e) => (e as Map)['section']), [kGeneralSection, b.id, b.id]);

      final back = Notebook('x', 'Otro')..loadSheetsJson(j);
      expect(back.sections.map((s) => s.name), ['General', 'Práctica']);
      expect(back.active, b.id);
      expect(back.sheets.length, 2);
      expect(back.otherSheets.length, 1);
      expect(back.totalSheets, 3);
      expect(back.activeSection.last, 1);
      expect(back.last, 1);
      expect(back.allSheets.map((m) => m.id), (j['sheets'] as List).map((e) => (e as Map)['id']));
    });

    test('archivo viejo sin secciones: una sola "General" con id fijo y todas las hojas', () {
      final nb = Notebook('x', 'Viejo')
        ..loadSheetsJson({
          'format': 3,
          'sheets': [
            {'id': 'h1', 'bg': 'lined'},
            {'id': 'h2', 'bg': 'grid'},
          ],
        });
      expect(nb.sections.map((s) => (s.id, s.name)), [(kGeneralSection, 'General')]);
      expect(nb.active, kGeneralSection);
      expect(nb.sheets.map((m) => m.id), ['h1', 'h2']);
      expect(nb.otherSheets, isEmpty);
      expect(nb.sheets.every((m) => m.section == kGeneralSection), isTrue);
    });

    test('hoja con sección inexistente (o sin sección) es de la primera', () {
      final nb = Notebook('x', 'N')
        ..loadSheetsJson({
          'sections': [
            {'id': 'a', 'name': 'A'},
            {'id': 'b', 'name': 'B'},
          ],
          'active': 'b',
          'sheets': [
            {'id': 'h1', 'section': 'b'},
            {'id': 'h2', 'section': 'fantasma'},
            {'id': 'h3'},
          ],
        });
      expect(nb.sheetsOf('a').map((m) => m.id), ['h2', 'h3']);
      expect(nb.sheetsOf('b').map((m) => m.id), ['h1']);
      expect(nb.sheets.map((m) => m.id), ['h1'], reason: 'la activa es B');
    });

    test('reagrupado estable: la fusión de la sync pudo intercalar las hojas', () {
      final nb = Notebook('x', 'N')
        ..loadSheetsJson({
          'sections': [
            {'id': 'a', 'name': 'A'},
            {'id': 'b', 'name': 'B'},
          ],
          'active': 'a',
          'sheets': [
            {'id': 'a1', 'section': 'a'},
            {'id': 'b1', 'section': 'b'},
            {'id': 'a2', 'section': 'a'},
            {'id': 'b2', 'section': 'b'},
          ],
        });
      expect(nb.allSheets.map((m) => m.id), ['a1', 'a2', 'b1', 'b2']);
      final out = jsonDecode(jsonEncode(nb.sheetsJson())) as Map;
      expect((out['sheets'] as List).map((e) => (e as Map)['id']), ['a1', 'a2', 'b1', 'b2']);
    });

    test('active inexistente cae en la primera; sin hojas ni secciones no se rompe', () {
      final nb = Notebook('x', 'N')
        ..loadSheetsJson({
          'sections': [
            {'id': 'a', 'name': 'A'}
          ],
          'active': 'zzz',
          'sheets': [],
        });
      expect(nb.active, 'a');
      expect(nb.sheets, isEmpty);
    });

    test('mover, renombrar y borrar secciones; no se borra la última ni la activa', () {
      final nb = Notebook.create('N');
      final b = nb.addSection('B'), c = nb.addSection('C');
      expect(nb.moveSection(c.id, -1), isTrue);
      expect(nb.sections.map((s) => s.name), ['General', 'C', 'B']);
      expect(nb.moveSection(nb.sections.first.id, -1), isFalse);
      expect(nb.allSheets.map((m) => m.section), [kGeneralSection, c.id, b.id], reason: 'las hojas siguen el orden de las secciones');
      nb.renameSection(b.id, 'Teoría');
      expect(nb.sectionById(b.id)!.name, 'Teoría');
      expect(nb.removeSection(kGeneralSection), isNull, reason: 'es la activa');
      expect(nb.removeSection(b.id)!.length, 1);
      expect(nb.sections.map((s) => s.name), ['General', 'C']);
      expect(nb.removeSection(c.id), isNotNull);
      expect(nb.removeSection(kGeneralSection), isNull, reason: 'es la última');
    });

    test('activar guarda la última hoja vista de la sección que se deja', () {
      final nb = Notebook.create('N');
      nb.sheets.add(nb.newSheet());
      nb.last = 1;
      final b = nb.addSection('B');
      nb.activate(b.id);
      expect(nb.last, 0);
      expect(nb.sheets.length, 1);
      expect(nb.sectionById(kGeneralSection)!.last, 1);
      nb.activate(kGeneralSection);
      expect(nb.last, 1);
      expect(nb.sheets.length, 2);
    });
  });

  group('regla de oro: nunca borrar ni pisar las hojas de otras secciones', () {
    test('guardar con la sección A abierta no toca los archivos de B', () async {
      final (nb, _) = await make();
      final b = await addWithStroke(nb, 'Práctica', 'b0', back: kGeneralSection);
      final bSheet = nb.sheetsOf(b.id).single;
      final f = store.sheetFile(nb.id, bSheet.id);
      expect(await f.exists(), isTrue);
      final before = await f.readAsBytes();
      final mtime = f.statSync().modified;

      // edito y guardo en A: con un doc recién abierto, y también con todo sucio
      var d = await store.openNotebook(nb, around: 0);
      d.strokes['a1'] = Stroke('a1', 'pen', '#22211e', 2.6, [30, 300, .5, 70, 340, .8]);
      d.markDirtyElement(d.strokes['a1']!);
      await store.saveNotebook(d);
      d.markAllDirty();
      await store.saveNotebook(d);

      expect(await f.exists(), isTrue, reason: 'el archivo de B sigue');
      expect(await f.readAsBytes(), before, reason: 'y no cambió ni un byte');
      expect(f.statSync().modified, mtime, reason: 'ni se reescribió');
      // y el contenido de B es el mismo
      final content = await store.readSheetContent(nb, bSheet);
      expect(content.strokes.map((s) => s.id), ['b0']);
      // notebook.json las lista todas
      expect((readJson(nb)['sheets'] as List).length, 2);

      // al abrir de nuevo (la limpieza de sobrantes) tampoco se borra
      d = await store.openNotebook(nb, around: 0);
      expect(await f.exists(), isTrue);
    });

    test('un Storage nuevo (otra sesión) lee las secciones y no pierde nada', () async {
      final (nb, _) = await make();
      final b = await addWithStroke(nb, 'Práctica', 'b0', back: kGeneralSection);
      final idx = NotesIndex(notebooks: [nb]);
      await store.saveIndex(idx);

      final store2 = Storage(root: root);
      await store2.init();
      final idx2 = await store2.loadIndex();
      final nb2 = idx2.notebooks.single;
      expect(nb2.sections.map((s) => s.name), ['General', 'Práctica']);
      expect(nb2.sheets.length, 1);
      expect(nb2.otherSheets.length, 1);
      // abrir la otra sección: su contenido está
      final d = await store2.openSection(nb2, b.id);
      expect(d.strokes.keys, ['b0']);
      final d2 = await store2.openSection(nb2, kGeneralSection);
      expect(d2.strokes.keys, ['a0']);
    });

    test('borrar una sección borra solo sus archivos', () async {
      final (nb, _) = await make();
      final b = await addWithStroke(nb, 'Práctica', 'b0', back: kGeneralSection);
      final c = await addWithStroke(nb, 'Otra', 'c0', back: kGeneralSection);
      final fa = store.sheetFile(nb.id, nb.sheets.single.id);
      final fb = store.sheetFile(nb.id, nb.sheetsOf(b.id).single.id);
      final fc = store.sheetFile(nb.id, nb.sheetsOf(c.id).single.id);
      expect(await fb.exists() && await fc.exists() && await fa.exists(), isTrue);

      final d = await store.openNotebook(nb, around: 0);
      expect(nb.removeSection(b.id), isNotNull);
      await store.saveNotebook(d);
      expect(await fb.exists(), isFalse);
      expect(await fa.exists(), isTrue);
      expect(await fc.exists(), isTrue);
      expect(readJson(nb)['sections'], hasLength(2));
      expect(((readJson(nb)['sheets']) as List).length, 2);
    });

    test('borrar la sección activa (pasando antes a otra) borra solo sus archivos', () async {
      final (nb, _) = await make();
      final b = await addWithStroke(nb, 'Práctica', 'b0', back: kGeneralSection);
      final fa = store.sheetFile(nb.id, nb.sheets.single.id);
      final fb = store.sheetFile(nb.id, nb.sheetsOf(b.id).single.id);
      final d = await store.openSection(nb, b.id);
      final d2 = await store.openSection(nb, kGeneralSection);
      expect(d2.strokes.keys, ['a0']);
      expect(d.nb, same(nb));
      nb.removeSection(b.id);
      await store.saveNotebook(d2);
      expect(await fa.exists(), isTrue);
      expect(await fb.exists(), isFalse);
    });

    test('la sección activa y su última hoja vista se recuerdan en disco', () async {
      final (nb, _) = await make();
      final b = nb.addSection('Práctica');
      final d = await store.openSection(nb, b.id);
      expect(d.sheetCount, 1);
      expect(readJson(nb)['active'], b.id, reason: 'se escribió al cambiar');
      final j = Notebook('x', 'x')..loadSheetsJson(readJson(nb));
      expect(j.active, b.id);
    });

    test('duplicar el cuaderno copia los archivos de todas las secciones', () async {
      final (nb, _) = await make();
      final b = await addWithStroke(nb, 'Práctica', 'b0', back: kGeneralSection);
      final copy = Notebook('copia', 'Física (copia)')..copySectionsFrom(nb);
      await store.copyNotebookFiles(nb, copy);
      expect(copy.sections.map((s) => s.name), ['General', 'Práctica']);
      expect(copy.totalSheets, 2);
      for (final m in copy.allSheets) {
        expect(await store.sheetFile(copy.id, m.id).exists(), isTrue);
      }
      final j = Notebook('x', 'x')..loadSheetsJson(readJson(copy));
      expect(j.sections.map((s) => s.name), ['General', 'Práctica']);
      expect(j.sheetsOf(b.id).length, 1);
    });
  });

  group('.opennote y exportar', () {
    test('.opennote conserva las secciones al exportar e importar', () async {
      final (nb, _) = await make();
      final b = await addWithStroke(nb, 'Práctica', 'b0', back: kGeneralSection);
      final bytes = await exportNotebookBytes(store, nb);
      final zip = ZipDecoder().decodeBytes(bytes);
      final names = {for (final f in zip) f.name};
      expect(names.where((n) => n.startsWith('sheets/')).length, 2, reason: 'las hojas de las dos secciones');

      final imp = await importNotebookBytes(store, bytes, taken: {});
      expect(imp.sections.map((s) => (s.id, s.name)), [(kGeneralSection, 'General'), (b.id, 'Práctica')]);
      expect(imp.active, kGeneralSection);
      expect(imp.totalSheets, 2);
      final d = await store.openSection(imp, b.id);
      expect(d.strokes.keys, ['b0']);
    });

    test('importar un .opennote viejo (sin secciones) lo deja en "General"', () async {
      final (nb, _) = await make();
      final bytes = await exportNotebookBytes(store, nb);
      // se le saca lo nuevo al notebook.json, como lo escribía la versión anterior
      final zip = ZipDecoder().decodeBytes(bytes);
      final out = Archive();
      for (final f in zip) {
        if (f.name == 'notebook.json') {
          final j = jsonDecode(utf8.decode(f.readBytes()!)) as Map;
          j.remove('sections');
          j.remove('active');
          for (final s in (j['sheets'] as List)) {
            (s as Map).remove('section');
          }
          out.add(ArchiveFile.bytes(f.name, utf8.encode(jsonEncode(j))));
        } else {
          out.add(ArchiveFile.bytes(f.name, f.readBytes()!));
        }
      }
      final imp = await importNotebookBytes(store, ZipEncoder().encodeBytes(out), taken: {});
      expect(imp.sections.single.id, kGeneralSection);
      expect(imp.sections.single.name, 'General');
      expect(imp.sheets.length, 1);
    });

    test('PNG: elegir secciones; con varias, el nombre lleva la sección', () async {
      Storage.useIsolates = false;
      addTearDown(() => Storage.useIsolates = true);
      final (nb, _) = await make();
      final b = await addWithStroke(nb, 'Práctica', 'b0', back: kGeneralSection);
      final d = await store.openNotebook(nb, radius: 0);

      final all = await buildNotebookPngs(store, d);
      expect(all!.zip, isTrue);
      final names = ZipDecoder().decodeBytes(all.bytes).map((f) => f.name).toList();
      expect(names, ['Física - General - hoja 01.png', 'Física - Práctica - hoja 01.png']);

      final onlyB = await buildNotebookPngs(store, d, sections: {b.id});
      expect(onlyB!.zip, isFalse, reason: 'una sola hoja: el PNG directo');
      expect(exportSheets(nb, sections: {b.id}).single.section.id, b.id);
      expect(exportSheets(nb, sections: {kGeneralSection, b.id}).length, 2);
      expect(exportSheets(nb, only: [0]).single.section.id, kGeneralSection);
    });
  });

  group('fusión de la sync', () {
    Map sec(String id, String name, {int updated = 0}) => {'id': id, 'name': name, 'updated': updated, 'last': 0};
    Map sh(String id, String section) => {'id': id, 'section': section, 'updated': 1};
    String nbj(List<Map> secs, List<Map> sheets, {String active = 'a'}) =>
        jsonEncode({'format': 3, 'sections': secs, 'active': active, 'sheets': sheets});
    Map merge(String b, String l, String r) => jsonDecode(mergeNotebookJson(b, l, r)) as Map;

    test('una sección nueva de cada lado: quedan las dos; active es el local', () {
      final base = nbj([sec('a', 'A')], [sh('h1', 'a')]);
      final local = nbj([sec('a', 'A'), sec('b', 'B')], [sh('h1', 'a'), sh('h2', 'b')]);
      final remote = nbj([sec('a', 'A'), sec('c', 'C')], [sh('h1', 'a'), sh('h3', 'c')], active: 'c');
      final m = merge(base, local, remote);
      expect((m['sections'] as List).map((e) => (e as Map)['id']).toSet(), {'a', 'b', 'c'});
      expect(m['active'], 'a');
      expect((m['sheets'] as List).map((e) => (e as Map)['id']).toSet(), {'h1', 'h2', 'h3'});
    });

    test('renombrada de un lado y sin cambios del otro: gana la renombrada; en los dos: la más nueva', () {
      final base = nbj([sec('a', 'A')], [sh('h1', 'a')]);
      final remote = nbj([sec('a', 'Teoría', updated: 5)], [sh('h1', 'a')]);
      expect(((merge(base, base, remote)['sections'] as List).single as Map)['name'], 'Teoría');
      final local = nbj([sec('a', 'Mía', updated: 9)], [sh('h1', 'a')]);
      expect(((merge(base, local, remote)['sections'] as List).single as Map)['name'], 'Mía');
    });

    test('borrada de un lado y sin cambios del otro: se borra', () {
      final base = nbj([sec('a', 'A'), sec('b', 'B')], [sh('h1', 'a'), sh('h2', 'b')]);
      final local = nbj([sec('a', 'A')], [sh('h1', 'a')]);
      final m = merge(base, local, base);
      expect((m['sections'] as List).map((e) => (e as Map)['id']), ['a']);
      expect((m['sheets'] as List).map((e) => (e as Map)['id']), ['h1']);
    });

    test('un notebook.json viejo (sin secciones) sigue fusionando', () {
      final old = jsonEncode({'format': 3, 'sheets': [sh('h1', '')..remove('section')]});
      final m = merge(old, old, old);
      expect(m.containsKey('sections'), isFalse);
      expect((m['sheets'] as List).length, 1);
    });
  });

  test('SheetMeta conserva la sección en copy / toJson / fromJson', () {
    final m = SheetMeta('h1', section: 'x');
    expect(m.copy().section, 'x');
    expect(SheetMeta.fromJson(m.toJson()).section, 'x');
    expect(SheetMeta('h2').toJson().containsKey('section'), isFalse);
    expect(SheetMeta.fromJson({'id': 'h3'}).section, '');
  });

  test('decodeSheet sigue andando con las hojas de una sección (el formato de .sheet no cambia)', () async {
    final (nb, _) = await make();
    final bytes = await store.sheetFile(nb.id, nb.sheets.single.id).readAsBytes();
    expect(decodeSheet(bytes).strokes.map((s) => s.id), ['a0']);
  });
}
