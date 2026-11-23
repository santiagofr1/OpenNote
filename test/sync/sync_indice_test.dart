import 'dart:convert';
import 'dart:io';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/sync/fake_remote_store.dart';
import 'package:apuntes/sync/sync_engine.dart';
import 'package:apuntes/sync/sync_merge.dart';
import 'package:flutter_test/flutter_test.dart';

/// Los títulos del índice (`SheetMeta.heads`, dentro de `notebook.json`) viajan bien entre dos dispositivos.
void main() {
  setUpAll(() => Storage.useIsolates = false);
  tearDownAll(() => Storage.useIsolates = true);

  final dirs = <Directory>[];
  tearDown(() {
    for (final d in dirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    dirs.clear();
  });

  Future<Storage> device() async {
    final d = await Directory.systemTemp.createTemp('apuntes_indice');
    dirs.add(d);
    final s = Storage(root: d);
    await s.init();
    return s;
  }

  Future<void> sync(Storage s, FakeRemoteStore r) async {
    final rep = await SyncEngine(s, r, busy: () => const {}, account: 'a@b.c').sync();
    expect(rep.errors, isEmpty, reason: rep.toString());
  }

  /// Cuaderno nuevo con [n] hojas; la hoja k tiene un trazo 's<k>'.
  Future<Notebook> create(Storage s, String name, {int n = 2}) async {
    final nb = Notebook.create(name);
    while (nb.sheets.length < n) {
      nb.sheets.add(nb.newSheet());
    }
    final d = NotebookDoc(nb);
    for (var k = 0; k < n; k++) {
      final y = k * kSheetStep + 100;
      d.strokes['s$k'] = Stroke('s$k', 'pen', '#22211e', 2.6, [100, y, .5, 200, y + 10, .5]);
    }
    nb.touch();
    await s.saveNotebook(d);
    final idx = await s.indexFile.exists() ? await s.loadIndex() : NotesIndex();
    idx.notebooks.add(nb);
    await s.saveIndex(idx);
    return nb;
  }

  Future<Notebook> nbOf(Storage s, String id) async => (await s.loadIndex()).notebooks.firstWhere((n) => n.id == id);

  /// Carga el cuaderno, deja que [f] toque la hoja [k] y guarda como haría el editor (sube su `updated`).
  Future<void> change(Storage s, String id, int k, void Function(SheetMeta m) f) async {
    final idx = await s.loadIndex();
    final nb = idx.notebooks.firstWhere((n) => n.id == id);
    final d = await s.loadNotebook(nb);
    final m = d.sheets[k];
    f(m);
    final now = DateTime.now().millisecondsSinceEpoch;
    m.updated = now > m.updated ? now : m.updated + 1;
    nb.touch();
    await s.saveNotebook(d);
    await s.saveIndex(idx);
  }

  Heading head(String id, String title, int k, {int level = 1}) => Heading(id, level: level, title: title, y: 100, ids: ['s$k']);

  void expectSame(Heading? got, Heading want) {
    expect(got, isNotNull);
    expect(got!.id, want.id);
    expect(got.level, want.level);
    expect(got.title, want.title);
    expect(got.y, want.y);
    expect(got.ids, want.ids);
    expect(got.hidden, want.hidden);
  }

  Heading? find(Notebook nb, int k, String id) => nb.sheets[k].heads.where((h) => h.id == id).firstOrNull;

  String line(OutlineEntry e) => '${e.number}|${e.title}|${e.sheetId}|${e.level}|${e.y}';

  test('un título creado en A llega idéntico a B, y el índice da la misma entrada', () async {
    final a = await device(), b = await device(), r = FakeRemoteStore();
    final nb = await create(a, 'Física');
    final h = head('h1', 'Cinemática', 0);
    await change(a, nb.id, 0, (m) => m.heads.add(h));
    await sync(a, r);
    await sync(b, r);

    final nbA = await nbOf(a, nb.id), nbB = await nbOf(b, nb.id);
    expectSame(find(nbB, 0, 'h1'), h);
    final oa = buildOutline(nbA), ob = buildOutline(nbB);
    expect(ob, hasLength(1));
    expect(ob.single.number, '1');
    expect(ob.single.title, 'Cinemática');
    expect(ob.single.sheetId, nbB.sheets[0].id);
    expect(ob.single.sheet, 0);
    expect(ob.single.headingId, 'h1');
    expect([for (final e in ob) line(e)], [for (final e in oa) line(e)]);
  });

  test('B renombra el título y lo pasa a nivel 2: A lo ve cambiado', () async {
    final a = await device(), b = await device(), r = FakeRemoteStore();
    final nb = await create(a, 'Física');
    await change(a, nb.id, 0, (m) {
      m.heads.add(head('h0', 'Capítulo', 0));
      m.heads.add(head('h1', 'Cinemática', 0)..y = 200);
    });
    await sync(a, r);
    await sync(b, r);

    await change(b, nb.id, 0, (m) {
      m.heads.firstWhere((x) => x.id == 'h1')
        ..title = 'Cinemática 1D'
        ..level = 2;
    });
    await sync(b, r);
    await sync(a, r);

    final nbA = await nbOf(a, nb.id);
    final h = find(nbA, 0, 'h1')!;
    expect(h.title, 'Cinemática 1D');
    expect(h.level, 2);
    expect(find(nbA, 0, 'h0')!.title, 'Capítulo');
    expect([for (final e in buildOutline(nbA)) '${e.number} ${e.title}'], ['1 Capítulo', '1.1 Cinemática 1D']);
  });

  test('A quita el título: tras sincronizar, B ya no lo tiene', () async {
    final a = await device(), b = await device(), r = FakeRemoteStore();
    final nb = await create(a, 'Física');
    await change(a, nb.id, 0, (m) => m.heads.add(head('h1', 'Cinemática', 0)));
    await sync(a, r);
    await sync(b, r);
    expect(find(await nbOf(b, nb.id), 0, 'h1'), isNotNull);

    await change(a, nb.id, 0, (m) => m.heads.removeWhere((h) => h.id == 'h1'));
    await sync(a, r);
    await sync(b, r);
    await sync(a, r);

    for (final s in [a, b]) {
      final n = await nbOf(s, nb.id);
      expect(n.sheets[0].heads, isEmpty);
      expect(buildOutline(n), isEmpty);
    }
  });

  test('títulos nuevos en hojas distintas sin sincronizar entre medio: quedan los dos', () async {
    final a = await device(), b = await device(), r = FakeRemoteStore();
    final nb = await create(a, 'Física');
    await sync(a, r);
    await sync(b, r);

    await change(a, nb.id, 0, (m) => m.heads.add(head('hA', 'Del A', 0)));
    await change(b, nb.id, 1, (m) => m.heads.add(head('hB', 'Del B', 1)));
    await sync(a, r);
    await sync(b, r);
    await sync(a, r);

    for (final s in [a, b]) {
      final n = await nbOf(s, nb.id);
      expectSame(find(n, 0, 'hA'), head('hA', 'Del A', 0));
      expectSame(find(n, 1, 'hB'), head('hB', 'Del B', 1));
      expect([for (final e in buildOutline(n)) '${e.number} ${e.title}'], ['1 Del A', '2 Del B']);
    }
  });

  test('un título hidden viaja como hidden y no sale en el índice del otro lado', () async {
    final a = await device(), b = await device(), r = FakeRemoteStore();
    final nb = await create(a, 'Física');
    await change(a, nb.id, 0, (m) {
      m.heads.add(head('h1', 'Oculto', 0)..hidden = true);
      m.heads.add(head('h2', 'Visible', 0)..y = 300);
    });
    await sync(a, r);
    await sync(b, r);

    final nbB = await nbOf(b, nb.id);
    expect(find(nbB, 0, 'h1')!.hidden, isTrue);
    expect(find(nbB, 0, 'h2')!.hidden, isFalse);
    expect([for (final e in buildOutline(nbB)) e.title], ['Visible']);
  });

  group('mergeNotebookJson', () {
    Map sheet(String id, int updated, List<Map> heads) => {
          'id': id,
          'bg': 'lined',
          'paper': '#fffefb',
          'spacing': 8.0,
          'rev': 1,
          'updated': updated,
          if (heads.isNotEmpty) 'heads': heads,
        };
    Map hd(String id, String t, int l, List<String> ids, {double y = 10}) => {'id': id, 'l': l, 't': t, 'y': y, 'ids': ids};
    String nbJson(List<Map> sheets) => jsonEncode({'sheets': sheets});
    List<Map> headsOf(String merged, String sheetId) {
      final s = ((jsonDecode(merged) as Map)['sheets'] as List).cast<Map>().firstWhere((e) => e['id'] == sheetId);
      return [for (final h in (s['heads'] as List? ?? const [])) h as Map];
    }

    final base = nbJson([
      sheet('a', 100, [hd('h1', 'Base', 1, ['x'])])
    ]);

    test('la hoja con updated mayor se queda entera, con todos sus títulos', () {
      final local = nbJson([
        sheet('a', 200, [hd('h1', 'Local', 1, ['x']), hd('h2', 'Extra', 2, ['y'], y: 50)])
      ]);
      final remote = nbJson([
        sheet('a', 300, [hd('h1', 'Remoto', 3, ['z'], y: 7)])
      ]);
      expect(headsOf(mergeNotebookJson(base, local, remote), 'a'), [hd('h1', 'Remoto', 3, ['z'], y: 7)]);
      expect(headsOf(mergeNotebookJson(base, remote, local), 'a'), [hd('h1', 'Remoto', 3, ['z'], y: 7)]);
    });

    test('con updated mayor en el local, gana el local entero', () {
      final local = nbJson([
        sheet('a', 400, [hd('h1', 'Local', 2, ['x']), hd('h2', 'Extra', 1, ['y'], y: 50)])
      ]);
      final remote = nbJson([
        sheet('a', 300, [hd('h1', 'Remoto', 3, ['z'])])
      ]);
      expect(headsOf(mergeNotebookJson(base, local, remote), 'a'), [hd('h1', 'Local', 2, ['x']), hd('h2', 'Extra', 1, ['y'], y: 50)]);
    });

    test('si solo cambió un lado, se toma ese lado aunque tenga menos updated', () {
      final remote = nbJson([
        sheet('a', 50, [hd('h1', 'Remoto', 2, ['x'])])
      ]);
      expect(headsOf(mergeNotebookJson(base, base, remote), 'a'), [hd('h1', 'Remoto', 2, ['x'])]);
    });
  });
}
