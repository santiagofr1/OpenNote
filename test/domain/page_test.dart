import 'dart:convert';

import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ida y vuelta por texto JSON, como en disco.
Map<String, dynamic> roundTrip(Map<String, dynamic> j) => jsonDecode(jsonEncode(j)) as Map<String, dynamic>;

void main() {
  group('hojas', () {
    test('sheetCount y heightFor son inversas', () {
      for (var n = 1; n <= 6; n++) {
        expect(sheetCount(heightFor(n)), n);
      }
      expect(heightFor(1), kSheetH);
      expect(heightFor(2), 2 * kSheetH + kGap);
      expect(sheetCount(0), 1, reason: 'siempre hay al menos una hoja');
    });

    test('sheetRects: una por hoja, separadas por kSheetStep', () {
      final r = sheetRects(heightFor(3));
      expect(r.length, 3);
      expect(r[1].top, kSheetStep);
      expect(r[2].bottom, heightFor(3));
    });

    test('snapTextY cae sobre el renglón (+4)', () {
      expect(snapTextY(4), 4);
      expect(snapTextY(60), 44);
      expect(snapTextY(66), 84);
    });

    test('addSheets y lastSheetEmpty', () {
      final p = PageData('p')..addSheets(1);
      expect(sheetCount(p.h), 2);
      expect(p.lastSheetEmpty, isTrue);
      p.texts['t'] = TextBlock('t', 90, kSheetStep + 44, 800, 'hola');
      expect(p.lastSheetEmpty, isFalse);
      p.addSheets(-1);
      expect(sheetCount(p.h), 1);
    });
  });

  group('JSON de página', () {
    PageData sample() {
      final p = PageData('p1', rev: 3, h: heightFor(2), bg: 'grid', paper: '#fbf3e0', updated: 123);
      p.strokes['s1'] = Stroke('s1', 'pen', '#22211e', 2.6, [10.04, 20.06, .333, 30, 40, 1], .5);
      p.strokes['s2'] = Stroke('s2', 'hl', '#f7d22c', 22, [1, 2, .5]);
      p.texts['t1'] = TextBlock('t1', 90, 44, 800, 'Hola');
      p.items['i1'] = Item('i1', 'sticky', 100, 200, 320, 240, text: 'nota', color: '#fde68a');
      p.items['i2'] = Item('i2', 'audio', 0, 300, 360, 64, file: 'm1.m4a', dur: 4200);
      p.items['i3'] = Item('i3', 'image', 0, 500, 560, 420, file: 'm2.png');
      return p;
    }

    test('ida y vuelta conserva todo (redondeado como en disco)', () {
      final p = PageData.fromJson(roundTrip(sample().toJson()));
      expect(p.id, 'p1');
      expect(p.rev, 3);
      expect(p.h, heightFor(2));
      expect(p.bg, 'grid');
      expect(p.paper, '#fbf3e0');
      expect(p.updated, 123);
      expect(p.strokes.keys, ['s1', 's2'], reason: 'el orden importa: es el orden de dibujo');
      expect(p.strokes['s1']!.pts, [10.0, 20.1, .33, 30, 40, 1]);
      expect(p.strokes['s1']!.o, .5);
      expect(p.strokes['s2']!.o, 1);
      expect(p.texts['t1']!.text, 'Hola');
      expect(p.items['i1']!.text, 'nota');
      expect(p.items['i2']!.dur, 4200);
      expect(p.items['i3']!.file, 'm2.png');
    });

    test('formato exacto de las claves (compatibilidad con la versión web)', () {
      final j = roundTrip(sample().toJson());
      expect(j.keys, ['id', 'rev', 'h', 'bg', 'paper', 'updated', 'items', 'layout', 'strokes', 'texts']);
      expect(j['layout'], 2);
      expect(j['strokes']['s2'], {'id': 's2', 'k': 'hl', 'c': '#f7d22c', 'w': 22.0, 'pts': [[1.0, 2.0, .5]]},
          reason: 'sin "o" cuando la opacidad es 1');
      expect(j['strokes']['s1']['o'], .5);
      expect(j['items']['i1'], {'id': 'i1', 'type': 'sticky', 'x': 100.0, 'y': 200.0, 'w': 320.0, 'h': 240.0, 'text': 'nota', 'color': '#fde68a'});
      expect(j['items']['i2'], {'id': 'i2', 'type': 'audio', 'x': 0.0, 'y': 300.0, 'w': 360.0, 'h': 64.0, 'file': 'm1.m4a', 'dur': 4200});
      expect(j['texts']['t1'], {'id': 't1', 'x': 90.0, 'y': 44.0, 'w': 800.0, 'text': 'Hola'});
    });

    test('valores que faltan: los de siempre', () {
      final p = PageData.fromJson({
        'id': 'x',
        'layout': 2,
        'strokes': {
          's': {'id': 's', 'pts': [[1, 2], [3, 4, .8]]}
        },
        'texts': {
          't': {'id': 't'}
        },
        'items': {
          'i': {'id': 'i', 'type': 'image'}
        },
      });
      expect(p.h, kSheetH);
      expect(p.bg, 'lined');
      expect(p.paper, '#fffefb');
      final s = p.strokes['s']!;
      expect([s.k, s.c, s.w, s.o], ['pen', '#22211e', 2, 1]);
      expect(s.pts, [1, 2, .5, 3, 4, .8], reason: 'sin presión = .5');
      expect(p.texts['t']!.w, 800);
      expect(p.items['i']!.w, 200);
    });

    test('migración layout 1 → 2: corre todo por el espacio entre hojas', () {
      final old = {
        'id': 'v1',
        'h': 2 * kSheetH, // dos hojas pegadas
        'strokes': {
          'a': {'id': 'a', 'pts': [[10, 100, .5], [20, kSheetH + 100, .5]]}
        },
        'texts': {
          't': {'id': 't', 'x': 90, 'y': kSheetH + 44, 'w': 800, 'text': 'hoja 2'}
        },
        'items': {
          'i': {'id': 'i', 'type': 'sticky', 'x': 0, 'y': 50, 'w': 100, 'h': 100}
        },
      };
      final p = PageData.fromJson(old);
      expect(p.h, heightFor(2));
      expect(p.strokes['a']!.pts, [10, 100, .5, 20, kSheetStep + 100, .5]);
      expect(p.strokes['a']!.bounds.bottom, greaterThan(kSheetStep + 100), reason: 'los bounds se recalculan');
      expect(p.texts['t']!.y, kSheetStep + 44);
      expect(p.items['i']!.y, 50, reason: 'lo de la primera hoja no se mueve');
      // ya migrada: guardada y releída no se vuelve a correr
      final again = PageData.fromJson(roundTrip(p.toJson()));
      expect(again.texts['t']!.y, kSheetStep + 44);
      expect(again.h, heightFor(2));
    });

    test('duplicate: id nuevo, mismo contenido', () {
      final p = sample();
      final d = p.duplicate();
      expect(d.id, isNot(p.id));
      expect(d.strokes.keys, p.strokes.keys);
      expect(d.texts['t1']!.text, 'Hola');
      d.texts['t1']!.text = 'otro';
      expect(p.texts['t1']!.text, 'Hola', reason: 'no comparten objetos');
    });
  });

  group('índice', () {
    test('ida y vuelta de cuadernos y páginas', () {
      final idx = NotesIndex(rev: 4, last: 'p2', notebooks: [
        Notebook('n1', 'Física', [PageRef('p1', 'a'), PageRef('p2', 'b', bookmark: true)],
            updated: 99, last: 'p2', favorite: true, pin: hashPin('1234')),
        Notebook('n2', 'Química', []),
      ]);
      final j = roundTrip(idx.toJson());
      final back = NotesIndex.fromJson(j);
      expect(back.rev, 4);
      expect(back.last, 'p2');
      final nb = back.notebooks.first;
      expect([nb.id, nb.name, nb.updated, nb.last, nb.favorite, nb.pin], ['n1', 'Física', 99, 'p2', true, hashPin('1234')]);
      expect(nb.pages.map((p) => p.bookmark), [false, true]);
      expect(j['notebooks'][1], {'id': 'n2', 'name': 'Química', 'updated': 0, 'last': null, 'pages': []},
          reason: 'favorite y pin solo si están');
      expect(j['notebooks'][0]['pages'][0], {'id': 'p1', 'title': 'a'});
    });

    test('hashPin es estable y depende del PIN', () {
      expect(hashPin('1234'), hashPin('1234'));
      expect(hashPin('1234'), isNot(hashPin('4321')));
      expect(hashPin('1234').length, 64);
    });
  });
}
