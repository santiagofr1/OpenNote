import 'dart:convert';
import 'dart:math';

import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stress.dart';

/// Secciones del cuaderno (agregar, renombrar, mover, quitar, pasar de una a otra): operaciones al azar contra un modelo
/// simple (lista ordenada de (sección, [ids de hoja])). Invariantes después de CADA paso:
///  - no se pierde ni se inventa ninguna hoja (salvo las de una sección quitada);
///  - `sheets` tiene solo las de la sección activa, y siempre alguna;
///  - el orden de `allSheets` es el de las secciones, y dentro de cada una el orden de antes;
///  - `sheetsJson` -> `loadSheetsJson` da el mismo cuaderno (lo que se guarda = lo que se ve).
void main() {
  /// Modelo: id de sección -> ids de hoja en orden.
  Map<String, List<String>> modelo(Notebook nb) => {for (final s in nb.sections) s.id: [for (final m in nb.sheetsOf(s.id)) m.id]};

  List<String> ordenSecciones(Notebook nb) => [for (final s in nb.sections) s.id];

  void chequear(Notebook nb, Map<String, List<String>> esperado, List<String> orden, String donde) {
    expect(ordenSecciones(nb), orden, reason: '$donde: orden de secciones');
    expect(modelo(nb), esperado, reason: '$donde: hojas por sección');
    expect(nb.sections, isNotEmpty, reason: donde);
    expect(nb.sheets, isNotEmpty, reason: '$donde: la sección activa nunca queda sin hojas');
    expect([for (final m in nb.sheets) m.id], esperado[nb.active], reason: '$donde: sheets es la tira de la sección activa');
    expect(nb.totalSheets, esperado.values.fold<int>(0, (n, l) => n + l.length), reason: '$donde: total');
    final todas = nb.allSheets.map((m) => m.id).toList();
    expect(todas.toSet().length, todas.length, reason: '$donde: ids de hoja repetidos');
    expect(todas, [for (final id in orden) ...esperado[id]!], reason: '$donde: allSheets agrupa por sección en orden');
    // lo que se guarda vuelve igual
    final j = jsonDecode(jsonEncode(nb.sheetsJson())) as Map;
    final copia = Notebook(nb.id, nb.name)..last = nb.last;
    copia.loadSheetsJson(j);
    expect(ordenSecciones(copia), orden, reason: '$donde: json orden');
    expect(modelo(copia), esperado, reason: '$donde: json hojas');
    expect(copia.active, nb.active, reason: '$donde: json activa');
  }

  for (final seed in kSeeds) {
    test('200 acciones de secciones al azar (semilla $seed): nada se pierde y el JSON coincide', () {
      final r = Random(seed);
      final nb = Notebook.create('Mate');
      for (var i = 0; i < r.nextInt(4); i++) {
        nb.sheets.add(nb.newSheet());
      }
      // lo que dice el cuaderno al empezar: una sola sección con sus hojas
      final esperado = modelo(nb);
      var orden = ordenSecciones(nb);
      chequear(nb, esperado, orden, 'inicio');

      for (var paso = 0; paso < 200; paso++) {
        final donde = 'semilla $seed paso $paso';
        switch (r.nextInt(7)) {
          case 0: // agregar sección
            final s = nb.addSection('Sec ${r.nextInt(99)}');
            orden = [...orden, s.id];
            esperado[s.id] = [nb.otherSheets.last.id];
          case 1: // pasar a otra sección
            final id = nb.sections[r.nextInt(nb.sections.length)].id;
            nb.activate(id);
            expect(nb.active, id, reason: donde);
          case 2: // agregar una hoja a la activa (como hace el documento)
            final m = nb.newSheet();
            nb.sheets.add(m);
            esperado[nb.active]!.add(m.id);
          case 3: // mover sección
            final id = nb.sections[r.nextInt(nb.sections.length)].id;
            final delta = r.nextBool() ? -1 : 1;
            final i = orden.indexOf(id), j = i + delta;
            final ok = nb.moveSection(id, delta);
            expect(ok, j >= 0 && j < orden.length, reason: '$donde: moveSection devuelve si se pudo');
            if (ok) orden.insert(j, orden.removeAt(i));
          case 4: // quitar sección
            final id = nb.sections[r.nextInt(nb.sections.length)].id;
            final puede = nb.sections.length >= 2 && id != nb.active;
            final gone = nb.removeSection(id);
            expect(gone != null, puede, reason: '$donde: quitar la activa o la última no se puede');
            if (gone != null) {
              expect(gone.map((m) => m.id).toList(), esperado[id], reason: '$donde: devuelve las hojas quitadas (para borrarles el archivo)');
              orden.remove(id);
              esperado.remove(id);
            }
          case 5: // renombrar (con nombres feos)
            final id = nb.sections[r.nextInt(nb.sections.length)].id;
            final nombre = kNombresRaros[r.nextInt(kNombresRaros.length)];
            nb.renameSection(id, nombre);
            expect(nb.sectionById(id)!.name, nombre);
          default: // "última hoja vista" fuera de rango, como la deja una app vieja
            nb.last = r.nextInt(50) - 5;
        }
        chequear(nb, esperado, orden, donde);
      }
    });
  }

  test('renombrar, mover o quitar una sección que no existe no hace nada ni tira', () {
    final nb = Notebook.create('x');
    nb.addSection('b');
    final antes = jsonEncode(nb.sheetsJson());
    nb.renameSection('nada', 'zzz');
    expect(nb.moveSection('nada', 1), isFalse);
    expect(nb.removeSection('nada'), isNull);
    nb.activate('nada');
    expect(jsonEncode(nb.sheetsJson()), antes);
  });

  test('un notebook.json con hojas de una sección que no existe: van a la primera, no se pierden', () {
    final nb = Notebook(newIdFijo, 'x');
    nb.loadSheetsJson({
      'sections': [
        {'id': 'a', 'name': 'A'},
        {'id': 'b', 'name': 'B'}
      ],
      'active': 'b',
      'sheets': [
        {'id': 'h1', 'section': 'a'},
        {'id': 'h2', 'section': 'fantasma'},
        {'id': 'h3', 'section': 'b'},
        {'id': 'h4'},
      ],
    });
    expect(nb.totalSheets, 4);
    expect(nb.sheetsOf('a').map((m) => m.id), ['h1', 'h2', 'h4']);
    expect(nb.sheetsOf('b').map((m) => m.id), ['h3']);
    expect(nb.active, 'b');
  });

  test('un notebook.json con secciones de id repetido o vacío no duplica hojas ni deja el cuaderno sin secciones', () {
    final nb = Notebook(newIdFijo, 'x');
    nb.loadSheetsJson({
      'sections': [
        {'id': '', 'name': 'sin id'},
        {'id': 'a', 'name': 'A'},
        {'id': 'a', 'name': 'otra A'},
        7,
        null,
      ],
      'sheets': [
        {'id': 'h1', 'section': 'a'},
        {'id': 'h2', 'section': ''},
      ],
    });
    expect(nb.sections.map((s) => s.id), ['a']);
    expect(nb.totalSheets, 2);
    expect(nb.sheets, isNotEmpty);
  });

  test('un nombre de sección vacío en el archivo se lee como "Sección" (no deja una sección sin nombre que no se pueda tocar)', () {
    expect(Section.fromJson({'id': 'a', 'name': ''}).name, isNotEmpty);
    expect(Section.fromJson({'id': 'a'}).name, isNotEmpty);
  });
}

const newIdFijo = 'n-fijo';
