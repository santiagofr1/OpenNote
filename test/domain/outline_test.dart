import 'dart:ui';

import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

Heading head(String id, int level, double y, {String? title, List<String> ids = const [], bool hidden = false}) =>
    Heading(id, level: level, title: title ?? id, y: y, ids: List.of(ids), hidden: hidden);

/// Cuaderno de [n] hojas (todas cargadas).
NotebookDoc docOf(int n) {
  final nb = Notebook.create('t');
  while (nb.sheets.length < n) {
    nb.sheets.add(nb.newSheet());
  }
  return NotebookDoc(nb);
}

Stroke stroke(String id, double x, double y) => Stroke(id, 'pen', '#000000', 2, [x, y, .5, x + 50, y + 10, .5]);

void main() {
  group('Heading y SheetMeta (json)', () {
    test('ida y vuelta', () {
      final h = head('h1', 2, 123.46, title: 'Intro', ids: ['a', 'b'], hidden: true);
      final r = Heading.fromJson(h.toJson());
      expect(r.id, 'h1');
      expect(r.level, 2);
      expect(r.title, 'Intro');
      expect(r.y, 123.5);
      expect(r.ids, ['a', 'b']);
      expect(r.hidden, isTrue);
      expect(head('h2', 1, 0).toJson().containsKey('x'), isFalse);
    });

    test('fromJson tolera faltantes', () {
      final h = Heading.fromJson({'id': 'z'});
      expect(h.level, 1);
      expect(h.title, '');
      expect(h.y, 0);
      expect(h.ids, isEmpty);
      expect(h.hidden, isFalse);
    });

    test('SheetMeta con títulos: ida y vuelta; sin títulos no escribe la clave', () {
      final m = SheetMeta('s1')..heads.add(head('h1', 1, 10, ids: ['a']));
      final r = SheetMeta.fromJson(m.toJson());
      expect(r.heads.single.id, 'h1');
      expect(r.heads.single.ids, ['a']);
      expect(SheetMeta('s2').toJson().containsKey('heads'), isFalse);
      expect(SheetMeta.fromJson(SheetMeta('s2').toJson()).heads, isEmpty);
    });

    test('copy con id nuevo no copia los títulos; sin id los copia en profundidad', () {
      final m = SheetMeta('s1')..heads.add(head('h1', 1, 10, ids: ['a']));
      expect(m.copy(id: 'otra').heads, isEmpty);
      final c = m.copy();
      expect(c.heads.single.id, 'h1');
      c.heads.single.title = 'cambiado';
      c.heads.single.ids.add('b');
      expect(m.heads.single.title, 'h1');
      expect(m.heads.single.ids, ['a']);
    });
  });

  group('buildOutline', () {
    test('ordena por hoja y altura y numera por niveles libres', () {
      final nb = Notebook.create('t');
      nb.sheets.add(nb.newSheet());
      nb.sheets[0].heads.addAll([head('b', 2, 200), head('a', 1, 50), head('c', 2, 300)]);
      nb.sheets[1].heads.addAll([head('e', 3, 400), head('d', 1, 20)]);
      final o = buildOutline(nb);
      expect([for (final e in o) e.headingId], ['a', 'b', 'c', 'd', 'e']);
      expect([for (final e in o) e.number], ['1', '1.1', '1.2', '2', '2.1']);
      expect([for (final e in o) e.sheet], [0, 0, 0, 1, 1]);
      expect(o.first.sheetId, nb.sheets[0].id);
    });

    test('1 / 1.1 / 1.2 / 2 / 2.1.1 con niveles libres', () {
      final nb = Notebook.create('t');
      nb.sheets[0].heads.addAll([head('a', 1, 10), head('b', 2, 20), head('c', 2, 30), head('d', 1, 40), head('e', 2, 50), head('f', 3, 60)]);
      expect([for (final e in buildOutline(nb)) e.number], ['1', '1.1', '1.2', '2', '2.1', '2.1.1']);
    });

    test('un salto de nivel se normaliza: nivel 3 después de 1 es 1.1; el primero es como mucho 1', () {
      final nb = Notebook.create('t');
      nb.sheets[0].heads.addAll([head('a', 4, 10), head('b', 3, 20), head('c', 1, 30), head('d', 5, 40)]);
      final o = buildOutline(nb);
      expect([for (final e in o) e.number], ['1', '1.1', '2', '2.1']);
      expect([for (final e in o) e.level], [1, 2, 1, 2]);
    });

    test('la numeración reinicia en cada sección y las ocultas no aparecen', () {
      final nb = Notebook.create('t');
      nb.sheets[0].heads.addAll([head('a', 1, 10), head('x', 1, 20, hidden: true), head('b', 1, 30)]);
      final s2 = nb.addSection('Otra');
      final other = nb.otherSheets.firstWhere((m) => m.section == s2.id);
      other.heads.addAll([head('c', 1, 10), head('d', 2, 20)]);
      final o = buildOutline(nb);
      expect([for (final e in o) e.headingId], ['a', 'b', 'c', 'd']);
      expect([for (final e in o) e.number], ['1', '2', '1', '1.1']);
      expect(o[2].sectionId, s2.id);
      expect(o[0].sectionId, nb.sections.first.id);
    });
  });

  group('syncHeadings', () {
    test('actualiza la y local cuando se mueve el trazo', () {
      final d = docOf(1);
      d.strokes['s'] = stroke('s', 100, 200);
      d.sheets[0].heads.add(head('h', 1, 0, ids: ['s']));
      expect(syncHeadings(d), isTrue);
      final y0 = d.sheets[0].heads.single.y;
      expect(y0, closeTo(200, 5)); // el borde del trazo incluye el grosor
      expect(syncHeadings(d), isFalse); // ya está al día
      d.strokes['s']!.translateY(100);
      expect(syncHeadings(d), isTrue);
      expect(d.sheets[0].heads.single.y, closeTo(y0 + 100, .5));
    });

    test('pasa a otra hoja cargada y sube updated', () {
      final d = docOf(2);
      d.strokes['s'] = stroke('s', 100, 200);
      d.sheets[0].heads.add(head('h', 1, 200, ids: ['s']));
      d.sheets[0].updated = 0;
      d.strokes['s']!.translateY(kSheetStep);
      expect(syncHeadings(d), isTrue);
      expect(d.sheets[0].heads, isEmpty);
      expect(d.sheets[1].heads.single.id, 'h');
      expect(d.sheets[1].heads.single.y, closeTo(200, 5));
      expect(d.sheets[0].updated, greaterThan(0));
      expect(d.sheets[1].updated, greaterThan(0));
    });

    test('usa el texto o el elemento más alto de lo marcado', () {
      final d = docOf(1);
      d.texts['t'] = TextBlock('t', 90, 150, 600, 'hola');
      d.items['i'] = Item('i', 'sticky', 10, 400, 100, 100);
      d.sheets[0].heads.add(head('h', 1, 0, ids: ['i', 't']));
      syncHeadings(d);
      expect(d.sheets[0].heads.single.y, 150);
    });

    test('se oculta si se borra lo marcado y vuelve si reaparece', () {
      final d = docOf(1);
      final s = stroke('s', 100, 200);
      d.strokes['s'] = s;
      d.sheets[0].heads.add(head('h', 1, 200, ids: ['s']));
      d.strokes.remove('s');
      expect(syncHeadings(d), isTrue);
      expect(d.sheets[0].heads.single.hidden, isTrue);
      expect(buildOutline(d.nb), isEmpty);
      expect(syncHeadings(d), isFalse);
      d.strokes['s'] = s; // deshacer
      expect(syncHeadings(d), isTrue);
      expect(d.sheets[0].heads.single.hidden, isFalse);
      expect(buildOutline(d.nb), hasLength(1));
    });

    test('una hoja sin cargar no se toca', () {
      final nb = Notebook.create('t');
      nb.sheets[0].heads.add(head('h', 1, 50, ids: ['s']));
      final d = NotebookDoc.lazy(nb);
      expect(syncHeadings(d), isFalse);
      expect(nb.sheets[0].heads.single.hidden, isFalse);
    });
  });

  group('título con zona (box) sobre un PDF', () {
    Item pdf(double y) => Item('p', 'pdf', 100, y, 300, 400, file: 'a.pdf');

    test('json ida y vuelta, y sin box no hay clave', () {
      final h = head('h', 1, 10, ids: ['p'])..box = const Rect.fromLTWH(10.04, 20.26, 100, 15);
      final j = h.toJson();
      expect(j['b'], [10, 20.3, 100, 15]);
      final r = Heading.fromJson(j);
      expect(r.box, const Rect.fromLTWH(10, 20.3, 100, 15));
      expect(r.copy().box, r.box);
      expect(head('h2', 1, 0).toJson().containsKey('b'), isFalse);
      expect(Heading.fromJson({'id': 'z', 'b': 'basura'}).box, isNull);
      expect(Heading.fromJson({'id': 'z', 'b': [1, 2]}).box, isNull);
    });

    test('syncHeadings usa la altura de la zona y se oculta si se borra el elemento', () {
      final d = docOf(1);
      d.items['p'] = pdf(50);
      d.sheets[0].heads.add(head('h', 1, 0, ids: ['p'])..box = const Rect.fromLTWH(10, 120, 100, 15));
      expect(syncHeadings(d), isTrue);
      expect(d.sheets[0].heads.single.y, 170);
      d.items.remove('p');
      syncHeadings(d);
      expect(d.sheets[0].heads.single.hidden, isTrue);
    });

    test('headingBounds devuelve la zona, no el elemento entero', () {
      final d = docOf(1);
      d.items['p'] = pdf(50);
      final h = head('h', 1, 0, ids: ['p'])..box = const Rect.fromLTWH(10, 120, 100, 15);
      expect(headingBounds(d, h, (_) => Rect.zero), const Rect.fromLTWH(110, 170, 100, 15));
      expect(headingBounds(d, head('g', 1, 0, ids: ['p']), (_) => Rect.zero), d.items['p']!.rect);
    });
  });
}
