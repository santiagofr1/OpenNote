import 'dart:convert';

import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// JSON del índice, de las carpetas y de las secciones con números escritos como decimales ("1700000000000.0"): es el
/// mismo número, y otros programas (JavaScript, Python, un cliente de la nube) lo escriben así. Hoy varios campos se
/// leen con `as int`, que tira con un double: `NotesIndex.fromJson` descarta EN SILENCIO ese cuaderno o carpeta (y el
/// próximo guardado del índice lo borra de la biblioteca, aunque sus hojas sigan en disco), y `loadSheetsJson` tira.
void main() {
  const t = 1700000000000.0; // el mismo instante que 1700000000000

  Map cuaderno({Object? updated = 1700000000000, Object? last = 0, Object? favorite = false}) =>
      {'id': 'n1', 'name': 'Física', 'updated': updated, 'last': last, 'favorite': favorite, 'bg': 'lined', 'paper': '#fffefb'};

  group('NotesIndex.fromJson', () {
    test('control: con enteros el cuaderno y la carpeta se leen', () {
      final idx = NotesIndex.fromJson({
        'notebooks': [cuaderno()],
        'folders': [
          {'id': 'f1', 'name': 'Uni', 'updated': 5}
        ]
      });
      expect(idx.notebooks.length, 1);
      expect(idx.folders.length, 1);
    });

    for (final (campo, valor) in [('updated', t), ('last', 3.0)]) {
      test('BUG sospechado: cuaderno con "$campo": $valor (decimal entero) no se descarta', () {
        final j = jsonDecode(jsonEncode({
          'notebooks': [cuaderno(updated: campo == 'updated' ? valor : 1, last: campo == 'last' ? valor : 0)]
        })) as Map;
        final idx = NotesIndex.fromJson(j);
        expect(idx.notebooks.map((n) => n.id), ['n1'], reason: 'el cuaderno desapareció de la biblioteca');
      });
    }

    test('BUG sospechado: carpeta con "updated" decimal entero no se descarta', () {
      final j = jsonDecode(jsonEncode({
        'folders': [
          {'id': 'f1', 'name': 'Uni', 'updated': t}
        ]
      })) as Map;
      expect(NotesIndex.fromJson(j).folders.map((f) => f.id), ['f1']);
    });

    test('un cuaderno roto no se lleva a los demás', () {
      final idx = NotesIndex.fromJson({
        'notebooks': [cuaderno(), 7, null, 'x', {'id': 'n2'}, {'id': 'n3', 'name': 'ok', 'updated': 1}]
      });
      expect(idx.notebooks.map((n) => n.id), containsAll(['n1', 'n3']));
    });
  });

  group('secciones y hojas', () {
    test('BUG sospechado: una sección con "updated" / "last" decimales enteros no hace tirar a loadSheetsJson', () {
      final nb = Notebook('n1', 'x');
      final j = jsonDecode(jsonEncode({
        'sections': [
          {'id': 'a', 'name': 'A', 'updated': t, 'last': 2.0}
        ],
        'sheets': [
          {'id': 'h1', 'section': 'a'}
        ],
      })) as Map;
      expect(() => nb.loadSheetsJson(j), returnsNormally);
      expect(nb.totalSheets, 1);
    });

    test('hojas con rev / updated decimales y títulos con ids que no son texto no tiran', () {
      final m = SheetMeta.fromJson({'id': 'h', 'rev': 3.0, 'updated': t, 'spacing': 8, 'heads': <Object>[]});
      expect(m.rev, 3);
      expect(m.updated, t.toInt());
    });

    test('BUG sospechado: un título del índice con un id de elemento que no es texto no tira ni se lleva la hoja', () {
      expect(() => SheetMeta.fromJson({
            'id': 'h',
            'heads': [
              {'id': 'x', 'ids': [1, 2]}
            ]
          }), returnsNormally);
    });
  });
}
