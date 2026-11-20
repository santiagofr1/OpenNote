import 'dart:convert';
import 'dart:io';

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

  test('primera vez: crea un cuaderno de ejemplo con una página', () async {
    final idx = await store.loadIndex();
    expect(idx.notebooks.single.name, 'Mi cuaderno');
    expect(idx.last, idx.notebooks.single.pages.single.id);
    expect(await File('${root.path}/index.json').exists(), isTrue);
    expect((await store.loadIndex()).notebooks.single.id, idx.notebooks.single.id, reason: 'la segunda vez lo lee');
  });

  test('página: guardar sube rev y updated; leer devuelve lo mismo', () async {
    final p = PageData('p1')..texts['t'] = TextBlock('t', 1, 2, 3, 'x');
    await store.savePage(p);
    expect(p.rev, 1);
    expect(p.updated, greaterThan(0));
    final back = await store.loadPage('p1');
    expect(back.texts['t']!.text, 'x');
    expect(back.rev, 1);
    expect(await File('${root.path}/pages/p1.json.tmp').exists(), isFalse, reason: 'el temporal se renombra');
  });

  test('página que no existe o está rota: vacía con ese id', () async {
    expect((await store.loadPage('nada')).isEmpty, isTrue);
    await File('${root.path}/pages/rota.json').writeAsString('{no es json');
    expect((await store.loadPage('rota')).id, 'rota');
  });

  test('lee páginas viejas (layout 1) y las migra', () async {
    await File('${root.path}/pages/v1.json').writeAsString(jsonEncode({
      'id': 'v1',
      'h': 2828,
      'texts': {
        't': {'id': 't', 'x': 90, 'y': 1458, 'w': 800, 'text': 'hoja 2'}
      },
    }));
    final p = await store.loadPage('v1');
    expect(p.texts['t']!.y, 1458 + kGap);
    expect(p.h, heightFor(2));
  });

  test('prefs', () async {
    expect(await store.loadPrefs(), isNull);
    await store.savePrefs((ToolState()..dock = 'right').toJson());
    expect((ToolState()..load(await store.loadPrefs())).dock, 'right');
  });

  test('deleteNotebook borra sus páginas y lo saca del índice', () async {
    final idx = await store.loadIndex();
    final nb = idx.notebooks.single;
    final pageFile = File('${root.path}/pages/${nb.pages.single.id}.json');
    expect(await pageFile.exists(), isTrue);
    await store.deleteNotebook(idx, nb);
    expect(await pageFile.exists(), isFalse);
    expect((await store.loadIndex()).notebooks, isEmpty);
  });

  test('medios: se copian a media/ con nombre nuevo', () async {
    final name = await store.addMedia([1, 2, 3], 'png');
    expect(name, endsWith('.png'));
    expect(await store.media(name).readAsBytes(), [1, 2, 3]);
  });
}
