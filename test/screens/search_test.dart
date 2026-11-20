import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/screens/notebook/search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final p1 = PageData('p1')
    ..texts['t1'] = TextBlock('t1', 0, 0, 800, 'La Ley de Ohm dice\nV = I·R')
    ..items['i1'] = Item('i1', 'sticky', 0, 0, 10, 10, text: 'repasar ohm')
    ..items['i2'] = Item('i2', 'image', 0, 0, 10, 10);
  final p2 = PageData('p2');
  final nb = Notebook('n', 'Física', [PageRef('p1', 'Electricidad'), PageRef('p2', 'Ohm y circuitos')]);
  Future<PageData> load(String id) async => id == 'p1' ? p1 : p2;

  test('busca en textos, notas y títulos, sin importar mayúsculas', () async {
    final hits = await searchNotebook(nb, load, '  OHM ');
    expect(hits.map((h) => h.id), ['t1', 'i1', null]);
    expect(hits.last.snippet, 'Título: Ohm y circuitos');
    expect(hits.first.snippet, 'La Ley de Ohm dice V = I·R', reason: 'en una línea');
  });

  test('búsqueda vacía: nada', () async {
    expect(await searchNotebook(nb, load, '   '), isEmpty);
  });

  test('snippet recorta alrededor de lo encontrado', () {
    final s = '${'a' * 100}ohm${'b' * 100}';
    final r = snippet(s, 100, 3);
    expect(r, startsWith('…'));
    expect(r, endsWith('…'));
    expect(r, contains('ohm'));
    expect(r.length, 30 + 3 + 50 + 2);
  });
}
