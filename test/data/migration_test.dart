import 'dart:convert';
import 'dart:io';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// Trazo en el JSON viejo: [[x, y, presión], ...]
Map<String, dynamic> oldStroke(String id, List<List<num>> pts, {String k = 'pen', double? o}) =>
    {'id': id, 'k': k, 'c': '#22211e', 'w': 2.6, 'o': ?o, 'pts': pts};

void main() {
  late Directory root;
  late Storage store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('apuntes_migracion');
    Directory('${root.path}/pages').createSync(recursive: true);
    Directory('${root.path}/media').createSync(recursive: true);
  });
  tearDown(() => root.delete(recursive: true));

  void writeJson(String rel, Object o) => File('${root.path}/$rel').writeAsStringSync(jsonEncode(o));

  /// Dos cuadernos:
  ///  - "Física": p1 (2 hojas, "Primera página", grid/crema), p2 (1 hoja, título "Circuitos", marcada),
  ///    p3 (3 hojas, "Página 3"); abierto en p2.
  ///  - "Química": q1 (1 hoja, título propio) con ids de trazos repetidos respecto de q2 (página duplicada).
  void writeOldFixture() {
    writeJson('pages/p1.json', {
      'id': 'p1', 'rev': 4, 'h': heightFor(2), 'bg': 'grid', 'paper': '#fbf3e0', 'updated': 5, 'layout': 2,
      'strokes': {
        's1': oldStroke('s1', [[10, 100, .5], [20, 110, .6]]),
        's2': oldStroke('s2', [[30, kSheetStep + 200, .5], [40, kSheetStep + 210, .5]], k: 'hl', o: .5),
      },
      'texts': {
        't1': {'id': 't1', 'x': 90, 'y': 44, 'w': 800, 'text': 'hoja 1 de p1'},
        't2': {'id': 't2', 'x': 90, 'y': kSheetStep + 84, 'w': 800, 'text': 'hoja 2 de p1'},
      },
      'items': {
        'i1': {'id': 'i1', 'type': 'image', 'x': 0, 'y': kSheetStep + 300, 'w': 200, 'h': 100, 'file': 'foto.png'},
      },
    });
    writeJson('pages/p2.json', {
      'id': 'p2', 'h': kSheetH, 'bg': 'dots', 'paper': '#ffffff', 'layout': 2,
      'strokes': {'s3': oldStroke('s3', [[5, 5, .5]])},
      'texts': {'t3': {'id': 't3', 'x': 90, 'y': 44, 'w': 800, 'text': 'p2'}},
      'items': {'i2': {'id': 'i2', 'type': 'sticky', 'x': 100, 'y': 200, 'w': 300, 'h': 200, 'text': 'nota', 'color': '#fde68a'}},
    });
    writeJson('pages/p3.json', {
      'id': 'p3', 'h': heightFor(3), 'layout': 2,
      'strokes': {'s4': oldStroke('s4', [[1, 2 * kSheetStep + 50, .5], [2, 2 * kSheetStep + 60, .5]])},
      'texts': {'t4': {'id': 't4', 'x': 90, 'y': 2 * kSheetStep + 44, 'w': 800, 'text': 'hoja 3 de p3'}},
    });
    // páginas duplicadas: comparten ids de trazo
    writeJson('pages/q1.json', {
      'id': 'q1', 'layout': 2, 'strokes': {'dup': oldStroke('dup', [[1, 1, .5]])},
    });
    writeJson('pages/q2.json', {
      'id': 'q2', 'layout': 2, 'strokes': {'dup': oldStroke('dup', [[7, 7, .5]])},
      'texts': {'tq': {'id': 'tq', 'x': 0, 'y': 44, 'w': 800, 'text': 'q2'}},
    });
    writeJson('index.json', {
      'rev': 9,
      'last': 'p2',
      'notebooks': [
        {
          'id': 'nF', 'name': 'Física', 'updated': 111, 'last': 'p2', 'favorite': true, 'pin': hashPin('1234'),
          'pages': [
            {'id': 'p1', 'title': 'Primera página'},
            {'id': 'p2', 'title': 'Circuitos', 'bookmark': true},
            {'id': 'p3', 'title': 'Página 3'},
          ],
        },
        {
          'id': 'nQ', 'name': 'Química', 'updated': 222, 'last': 'q1',
          'pages': [
            {'id': 'q1', 'title': 'Enlaces'},
            {'id': 'q2', 'title': '03/11'},
            {'id': 'q-falta', 'title': 'Archivo perdido'},
          ],
        },
      ],
    });
  }

  Future<Storage> open() async {
    store = Storage(root: root);
    await store.init();
    return store;
  }

  test('convierte el formato viejo: hojas seguidas, posiciones y elementos intactos', () async {
    writeOldFixture();
    await open();
    final idx = await store.loadIndex();

    expect(idx.notebooks.map((n) => n.name), ['Física', 'Química']);
    final nF = idx.notebooks[0];
    expect([nF.id, nF.updated, nF.favorite, nF.pin], ['nF', 111, true, hashPin('1234')]);
    expect(idx.last, 'nF', reason: 'sin equivalencia de página: el primero');
    expect([nF.bg, nF.paper], ['grid', '#fbf3e0'], reason: 'el estilo de la primera página queda como el del cuaderno');
    expect(nF.sheets.length, 2 + 1 + 3);
    expect(nF.last, 2, reason: 'abierto en p2, que empieza en la hoja 3 (índice 2)');

    // hojas: estilo por hoja, títulos y marcadores
    expect(nF.sheets.map((s) => s.bg), ['grid', 'grid', 'dots', 'lined', 'lined', 'lined']);
    expect(nF.sheets.map((s) => s.paper), ['#fbf3e0', '#fbf3e0', '#ffffff', '#fffefb', '#fffefb', '#fffefb']);
    expect(nF.sheets.map((s) => s.title), ['', '', 'Circuitos', '', '', ''], reason: '"Primera página" y "Página 3" son por defecto');
    expect(nF.sheets.map((s) => s.bookmark), [false, false, true, false, false, false]);

    final d = await store.loadNotebook(nF);
    expect(d.sheetCount, 6);
    expect(d.strokes.length, 4);
    expect(d.texts.length, 4);
    expect(d.items.length, 2);
    // posiciones: p1 en las hojas 0-1, p2 en la 2, p3 en las 3-5
    expect(d.strokes['s1']!.pts[1], closeTo(100, .05));
    expect(d.strokes['s2']!.pts[1], closeTo(kSheetStep + 200, .05));
    expect(d.strokes['s2']!.k, 'hl');
    expect(d.strokes['s2']!.o, .5);
    expect(d.strokes['s3']!.pts[1], closeTo(2 * kSheetStep + 5, .05));
    expect(d.strokes['s4']!.pts[1], closeTo((3 + 2) * kSheetStep + 50, .05));
    expect(d.texts['t2']!.y, kSheetStep + 84);
    expect(d.texts['t3']!.y, 2 * kSheetStep + 44);
    expect(d.texts['t4']!.y, 5 * kSheetStep + 44);
    expect(d.items['i1']!.file, 'foto.png');
    expect(d.items['i1']!.y, kSheetStep + 300);
    expect(d.items['i2']!.y, 2 * kSheetStep + 200);
    expect(d.items['i2']!.text, 'nota');
    expect(d.splitBySheet().map((c) => c.strokes.length + c.texts.length + c.items.length), [2, 3, 3, 0, 0, 2]);

    // segundo cuaderno: ids repetidos entre páginas no se pisan; página que falta = hoja vacía
    final nQ = idx.notebooks[1];
    expect(nQ.sheets.length, 3);
    expect(nQ.sheets.map((s) => s.title), ['Enlaces', '', 'Archivo perdido']);
    final q = await store.loadNotebook(nQ);
    expect(q.strokes.length, 2, reason: 'los dos trazos con id "dup" siguen siendo dos');
    expect(q.strokes.values.map((s) => s.pts[0]).toSet(), {1.0, 7.0});
    expect(q.texts['tq']!.y, kSheetStep + 44);
  });

  test('deja el formato nuevo escrito y las páginas viejas en un backup', () async {
    writeOldFixture();
    await open();
    await store.loadIndex();
    final j = jsonDecode(File('${root.path}/index.json').readAsStringSync()) as Map;
    expect(j['format'], 3);
    expect((j['notebooks'] as List).length, 2);
    expect(Directory('${root.path}/pages').existsSync(), isFalse, reason: 'pages/ se movió');
    final backup = Directory('${root.path}/legacy_pages_backup').listSync().map((e) => e.uri.pathSegments.last).toSet();
    expect(backup, {'p1.json', 'p2.json', 'p3.json', 'q1.json', 'q2.json'}, reason: 'no se borró nada');
    for (final n in ['nF', 'nQ']) {
      expect(File('${root.path}/notebooks/$n/notebook.json').existsSync(), isTrue);
    }
  });

  test('idempotente: la segunda vez lee el formato nuevo sin volver a convertir', () async {
    writeOldFixture();
    await open();
    final first = await store.loadIndex();
    final ids = first.notebooks[0].sheets.map((s) => s.id).toList();
    final store2 = Storage(root: root);
    await store2.init();
    final second = await store2.loadIndex();
    expect(second.notebooks[0].sheets.map((s) => s.id), ids);
    expect((await store2.loadNotebook(second.notebooks[0])).strokes.length, 4);
  });

  test('interrumpida a medio camino (índice todavía viejo): se rehace desde cero', () async {
    writeOldFixture();
    await open();
    // restos de un intento cortado: carpeta de un cuaderno con basura y una hoja suelta
    final junk = File('${root.path}/notebooks/nF/sheets/basura.sheet')..createSync(recursive: true);
    junk.writeAsBytesSync([1, 2, 3]);
    File('${root.path}/notebooks/nF/notebook.json').writeAsStringSync('{roto');
    File('${root.path}/notebooks/nF/sheets/otra.sheet.tmp').writeAsStringSync('x');
    final idx = await store.loadIndex();
    expect(junk.existsSync(), isFalse, reason: 'lo que quedó de antes se pisó');
    final d = await store.loadNotebook(idx.notebooks[0]);
    expect(d.sheetCount, 6);
    expect(d.strokes.length, 4);
    expect(Directory('${root.path}/notebooks/nF/sheets').listSync().length, 6, reason: 'una por hoja, sin sobrantes');
  });

  test('interrumpida justo antes de mover pages/: el índice ya es nuevo y se termina de archivar', () async {
    writeOldFixture();
    await open();
    await store.loadIndex();
    // simula el corte: el índice nuevo está, pero pages/ quedó con archivos
    Directory('${root.path}/legacy_pages_backup').deleteSync(recursive: true);
    Directory('${root.path}/pages').createSync();
    writeJson('pages/p1.json', {'id': 'p1'});
    final store2 = Storage(root: root);
    await store2.init();
    final idx = await store2.loadIndex();
    expect(idx.notebooks.length, 2);
    expect(Directory('${root.path}/pages').existsSync(), isFalse);
    expect(File('${root.path}/legacy_pages_backup/p1.json').existsSync(), isTrue);
  });

  test('cuaderno sin páginas: una hoja vacía', () async {
    writeJson('index.json', {
      'notebooks': [
        {'id': 'n', 'name': 'Vacío', 'pages': []}
      ]
    });
    await open();
    final idx = await store.loadIndex();
    expect(idx.notebooks.single.sheets.length, 1);
  });

  test('páginas del formato más viejo (hojas pegadas, layout 1): se corre el espacio entre hojas', () async {
    writeJson('pages/v1.json', {
      'id': 'v1', 'h': 2 * kSheetH,
      'texts': {'t': {'id': 't', 'x': 90, 'y': kSheetH + 44, 'w': 800, 'text': 'hoja 2'}},
    });
    writeJson('index.json', {
      'notebooks': [
        {'id': 'n', 'name': 'Viejo', 'pages': [{'id': 'v1', 'title': 'Viejo'}]}
      ]
    });
    await open();
    final idx = await store.loadIndex();
    final d = await store.loadNotebook(idx.notebooks.single);
    expect(d.sheetCount, 2);
    expect(d.texts['t']!.y, kSheetStep + 44);
    expect(d.sheets[0].title, 'Viejo');
  });
}
