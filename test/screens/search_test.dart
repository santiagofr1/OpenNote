import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/screens/notebook/search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  NotebookDoc doc() {
    final nb = Notebook.create('Física');
    nb.sheets.add(nb.newSheet());
    nb.sheets[0].title = 'Electricidad';
    nb.sheets[1].title = 'Ohm y circuitos';
    return NotebookDoc(nb)
      ..texts['t1'] = TextBlock('t1', 0, 44, 800, 'La Ley de Ohm dice\nV = I·R')
      ..items['i1'] = Item('i1', 'sticky', 0, 300, 10, 10, text: 'repasar ohm')
      ..items['i2'] = Item('i2', 'image', 0, 400, 10, 10)
      ..texts['t2'] = TextBlock('t2', 0, kSheetStep + 44, 800, 'más OHM acá');
  }

  test('busca en textos, notas y títulos, sin importar mayúsculas, en orden de hoja', () {
    final hits = searchNotebook(doc(), '  OHM ');
    expect(hits.map((h) => h.id), ['t1', 'i1', null, 't2'], reason: 'hoja 1: texto, nota; hoja 2: título primero (arriba), texto');
    expect(hits.map((h) => h.sheet), [0, 0, 1, 1]);
    expect(hits[2].snippet, 'Título: Ohm y circuitos');
    expect(hits.first.snippet, 'La Ley de Ohm dice V = I·R', reason: 'en una línea');
  });

  test('el título de una hoja se encuentra aunque no tenga nada escrito', () {
    final hits = searchNotebook(doc(), 'electri');
    expect(hits.single.sheet, 0);
    expect(hits.single.id, isNull);
  });

  test('búsqueda vacía: nada', () {
    expect(searchNotebook(doc(), '   '), isEmpty);
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
