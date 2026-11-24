import 'dart:ui';

import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Stroke stroke(String id, double x, double y, {String k = 'pen', int z = 0}) =>
      Stroke(id, k, '#000000', 2, [x, y, .5, x + 50, y, .5])..z = z;
  Item item(String id, double x, double y, {int z = 0}) => Item(id, 'image', x, y, 100, 100)..z = z;
  Rect rectOf(Layered e) => switch (e) {
        Stroke s => s.bounds,
        Item i => i.rect,
        TextBlock t => Rect.fromLTWH(t.x, t.y, t.w, 40),
        _ => Rect.zero,
      };
  List<String> ids(Iterable<Layered> l) => [for (final e in l) e.id];

  group('segmentIntersectsRect', () {
    const r = Rect.fromLTRB(10, 10, 20, 20);
    test('atraviesa sin tener extremos adentro', () {
      expect(segmentIntersectsRect(const Offset(0, 15), const Offset(30, 15), r), isTrue);
      expect(segmentIntersectsRect(const Offset(0, 0), const Offset(30, 30), r), isTrue);
    });
    test('extremo adentro, borde y afuera', () {
      expect(segmentIntersectsRect(const Offset(15, 15), const Offset(50, 50), r), isTrue);
      expect(segmentIntersectsRect(const Offset(0, 10), const Offset(10, 10), r), isTrue);
      expect(segmentIntersectsRect(const Offset(0, 0), const Offset(30, 5), r), isFalse);
      expect(segmentIntersectsRect(const Offset(0, 25), const Offset(9, 5), r), isFalse);
      expect(segmentIntersectsRect(const Offset(5, 5), const Offset(5, 5), r), isFalse);
    });
  });

  group('Stroke.touchesRect', () {
    test('un trazo que cruza el rectángulo sin ningún punto adentro', () {
      final s = Stroke('s', 'pen', '#000000', 2, [0, 50, .5, 200, 50, .5]);
      expect(s.touchesRect(const Rect.fromLTRB(90, 20, 110, 80)), isTrue);
    });
    test('el rectángulo que envuelve se superpone pero el recorrido no pasa cerca', () {
      // "L": el rectángulo cae en la esquina vacía
      final s = Stroke('s', 'pen', '#000000', 2, [0, 0, .5, 0, 100, .5, 100, 100, .5]);
      expect(s.touchesRect(const Rect.fromLTRB(40, 20, 80, 60)), isFalse);
    });
    test('cuenta la mitad del grosor y los trazos de un punto', () {
      final s = Stroke('s', 'pen', '#000000', 10, [0, 50, .5, 100, 50, .5]);
      expect(s.touchesRect(const Rect.fromLTRB(20, 53, 40, 80)), isTrue, reason: '53 - 5 <= 50');
      expect(s.touchesRect(const Rect.fromLTRB(20, 56, 40, 80)), isFalse);
      final dot = Stroke('d', 'pen', '#000000', 4, [10, 10, .5]);
      expect(dot.touchesRect(const Rect.fromLTRB(11, 11, 30, 30)), isTrue);
    });
  });

  group('orden de dibujo', () {
    test('sin z (archivos viejos) queda imágenes, tinta y textos', () {
      final doc = NotebookDoc(Notebook.create('t'));
      doc.texts['t'] = TextBlock('t', 0, 0, 100, 'x');
      doc.strokes['a'] = stroke('a', 0, 0);
      doc.items['i'] = item('i', 0, 0);
      expect(ids(doc.drawOrder()), ['i', 'a', 't']);
    });

    test('nextZ y stackOnTop ponen arriba de todo', () {
      final doc = NotebookDoc(Notebook.create('t'));
      doc.items['i'] = item('i', 0, 0, z: 5);
      expect(doc.nextZ(), 6);
      final a = stroke('a', 0, 0), b = stroke('b', 0, 0, z: 1);
      doc.stackOnTop([a, b]);
      expect([a.z, b.z], [6, 7], reason: 'conservan el orden entre sí');
    });

    test('zRuns: tandas de trazos seguidos', () {
      final order = [stroke('a', 0, 0), stroke('b', 0, 0), item('i', 0, 0), stroke('c', 0, 0)];
      final runs = zRuns(order);
      expect(runs.length, 3);
      expect(runs[0].strokes!.map((s) => s.id), ['a', 'b']);
      expect(runs[1].single, isA<Item>());
      expect(runs[2].strokes!.single.id, 'c');
    });
  });

  group('computeReorder', () {
    // c encima de b encima de a, todos superpuestos; d lejos
    List<Layered> base() => [item('a', 0, 0, z: 0), item('b', 0, 0, z: 1), item('c', 0, 0, z: 2), item('d', 500, 500, z: 3)];

    List<String> apply(List<Layered> o, Set<String> sel, ZMove m) {
      final ch = computeReorder(o, sel, m, rectOf);
      if (ch != null) {
        for (final e in o) {
          final z = ch.after[e.id];
          if (z != null) e.z = z;
        }
      }
      return ids(sortByZ(o));
    }

    test('traer al frente y enviar al fondo', () {
      expect(apply(base(), {'a'}, ZMove.front), ['b', 'c', 'd', 'a']);
      expect(apply(base(), {'c'}, ZMove.back), ['c', 'a', 'b', 'd']);
    });

    test('ya arriba / ya abajo: no cambia nada', () {
      expect(computeReorder(base(), {'d'}, ZMove.front, rectOf), isNull);
      expect(computeReorder(base(), {'a'}, ZMove.back, rectOf), isNull);
      expect(computeReorder(base(), {'zz'}, ZMove.front, rectOf), isNull);
    });

    test('subir uno pasa por encima del próximo que se superpone y salta los que no', () {
      // d (z 3) no se toca con a: subir a deja a por encima de b, no de d
      expect(apply(base(), {'a'}, ZMove.up), ['b', 'a', 'c', 'd']);
      final o = [item('a', 0, 0, z: 0), item('x', 700, 700, z: 1), item('b', 50, 50, z: 2)];
      expect(apply(o, {'a'}, ZMove.up), ['x', 'b', 'a'], reason: 'x no se superpone: se saltea');
    });

    test('bajar uno y los extremos', () {
      expect(apply(base(), {'c'}, ZMove.down), ['a', 'c', 'b', 'd']);
      final o = [item('x', 700, 700, z: 0), item('a', 0, 0, z: 1), item('b', 0, 0, z: 2)];
      expect(apply(o, {'b'}, ZMove.down), ['x', 'b', 'a']);
      expect(computeReorder([item('x', 700, 700, z: 0), item('a', 0, 0, z: 1)], {'a'}, ZMove.down, rectOf), isNull,
          reason: 'lo de abajo no se toca con a: no hay nada que pasar');
      expect(computeReorder(base(), {'c'}, ZMove.up, rectOf), isNull, reason: 'd no se toca con c');
    });

    test('varios seleccionados se mueven juntos', () {
      expect(apply(base(), {'a', 'b'}, ZMove.up), ['c', 'a', 'b', 'd']);
      expect(apply(base(), {'a', 'c'}, ZMove.front), ['b', 'd', 'a', 'c']);
    });

    test('con z repetidos se numera todo y el cambio es deshacible', () {
      final doc = NotebookDoc(Notebook.create('t'));
      doc.items['i'] = item('i', 0, 0);
      doc.strokes['a'] = stroke('a', 0, 0);
      doc.texts['t'] = TextBlock('t', 0, 0, 100, 'x');
      expect(ids(doc.drawOrder()), ['i', 'a', 't']);
      final ch = doc.reorder({'i'}, ZMove.front, rectOf)!;
      expect(ids(doc.drawOrder()), ['a', 't', 'i']);
      ch.before.forEach(doc.setZ);
      expect(ids(doc.drawOrder()), ['i', 'a', 't']);
    });
  });

  group('orden y hojas', () {
    test('sobrevive a splitBySheet / fromSheets, también entre hojas', () {
      final nb = Notebook('n', 'n', sheets: [Notebook.create('x').newSheet(), Notebook.create('x').newSheet()]);
      final doc = NotebookDoc(nb);
      doc.strokes['a'] = stroke('a', 10, 10, z: 3);
      doc.items['i'] = item('i', 10, 10, z: 7);
      doc.texts['t'] = TextBlock('t', 10, 10, 100, 'x')..z = 1;
      doc.strokes['b'] = stroke('b', 10, kSheetStep + 10, z: 2);
      expect(ids(doc.drawOrder()), ['t', 'b', 'a', 'i']);
      final back = NotebookDoc.fromSheets(nb, doc.splitBySheet());
      // por hoja: hoja 0 = t, a, i ; hoja 1 = b
      expect(ids(back.drawOrder()), ['t', 'a', 'i', 'b']);
      expect(back.strokes['b']!.z, greaterThan(back.items['i']!.z));
    });
  });

  group('splitHighlighters', () {
    final paintK = 'paint-${paintShapeIds.first}';
    List<List<String>> idsOf(List<ZRun> l) => [for (final r in l) ids(r.strokes ?? [r.single!])];

    test('[pen, hl, pen]: el resaltador va primero y multiplica; la tinta después', () {
      final run = ZRun.ink([stroke('a', 0, 0), stroke('h', 0, 10, k: 'hl'), stroke('b', 0, 20)]);
      final out = splitHighlighters([run]);
      expect(idsOf(out), [
        ['h'],
        ['a', 'b']
      ]);
      expect([for (final r in out) r.multiply], [true, false]);
    });
    test('[pintura, hl, hl, pen]: la pintura no multiplica, los resaltadores seguidos sí', () {
      final run = ZRun.ink(
          [stroke('p', 0, 0, k: paintK), stroke('h1', 0, 10, k: 'hl'), stroke('h2', 0, 20, k: 'hl'), stroke('a', 0, 30)]);
      final out = splitHighlighters([run]);
      expect(idsOf(out), [
        ['p'],
        ['h1', 'h2'],
        ['a']
      ]);
      expect([for (final r in out) r.multiply], [false, true, false]);
    });
    test('sin resaltador: misma instancia', () {
      final run = ZRun.ink([stroke('a', 0, 0), stroke('b', 0, 10, k: paintK)]);
      final one = ZRun.one(item('i', 0, 0));
      final out = splitHighlighters([run, one]);
      expect(out.length, 2);
      expect(identical(out[0], run), isTrue);
      expect(identical(out[1], one), isTrue);
    });
    test('un elemento suelto entre tandas queda en su lugar', () {
      final one = ZRun.one(item('i', 0, 0));
      final out = splitHighlighters([
        ZRun.ink([stroke('h', 0, 0, k: 'hl')]),
        one,
        ZRun.ink([stroke('a', 0, 0), stroke('g', 0, 5, k: 'hl')])
      ]);
      expect(idsOf(out), [
        ['h'],
        ['i'],
        ['g'],
        ['a']
      ]);
    });
  });
}
