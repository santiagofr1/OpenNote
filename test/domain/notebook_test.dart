import 'dart:convert';

import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ida y vuelta por texto JSON, como en disco.
Map<String, dynamic> roundTrip(Map<String, dynamic> j) => jsonDecode(jsonEncode(j)) as Map<String, dynamic>;

void main() {
  group('medidas de las hojas', () {
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

    test('snapTextY cae sobre el renglón (+10 % del renglón)', () {
      // rayado de 8 mm: renglón de 38,1 unidades y texto 3,8 por debajo
      final line = mmToUnits(8), inset = line * .1;
      expect(snapTextY(0, 'lined', 8), closeTo(inset, 1e-9));
      expect(snapTextY(line + inset + 5, 'lined', 8), closeTo(line + inset, 1e-9));
      expect(snapTextY(line * 1.6, 'lined', 8), closeTo(2 * line + inset, 1e-9));
      expect(snapTextY(line * 1.6, 'lined', 8, floor: true), closeTo(line + inset, 1e-9));
    });
  });

  group('elementos', () {
    test('texto e item: ida y vuelta y claves', () {
      final t = TextBlock.fromJson(roundTrip(TextBlock('t1', 90, 44, 800, 'Hola').toJson()));
      expect([t.id, t.x, t.y, t.w, t.text], ['t1', 90, 44, 800, 'Hola']);
      final i = Item('i2', 'audio', 0, 300, 360, 64, file: 'm1.m4a', dur: 4200);
      expect(roundTrip(i.toJson()), {'id': 'i2', 'type': 'audio', 'x': 0.0, 'y': 300.0, 'w': 360.0, 'h': 64.0, 'file': 'm1.m4a', 'dur': 4200});
      final st = Item('i1', 'sticky', 100, 200, 320, 240, text: 'nota', color: '#fde68a');
      expect(Item.fromJson(roundTrip(st.toJson())).text, 'nota');
    });

    test('valores que faltan: los de siempre', () {
      expect(TextBlock.fromJson({'id': 't'}).w, 800);
      expect(Item.fromJson({'id': 'i', 'type': 'image'}).w, 200);
    });
  });

  group('hojas y cuadernos', () {
    test('SheetMeta: título y marcador solo si están', () {
      final m = SheetMeta('h1', bg: 'grid', paper: '#fbf3e0', rev: 3, updated: 9);
      expect(roundTrip(m.toJson()), {'id': 'h1', 'bg': 'grid', 'paper': '#fbf3e0', 'spacing': 5.0, 'rev': 3, 'updated': 9});
      final back = SheetMeta.fromJson(roundTrip((m..title = 'Ohm'..bookmark = true).toJson()));
      expect([back.title, back.bookmark, back.bg, back.rev], ['Ohm', true, 'grid', 3]);
    });

    test('Notebook.create: una hoja con el estilo del cuaderno', () {
      final nb = Notebook.create('Física');
      expect(nb.sheets.length, 1);
      nb..bg = 'dots'..paper = '#ffffff';
      final s = nb.newSheet();
      expect([s.bg, s.paper, s.title, s.bookmark], ['dots', '#ffffff', '', false]);
    });

    test('índice: ida y vuelta (las hojas van aparte, en notebook.json)', () {
      final idx = NotesIndex(rev: 4, last: 'n1', notebooks: [
        Notebook('n1', 'Física',
            sheets: [SheetMeta('h1')], bg: 'grid', paper: '#fbf3e0', updated: 99, last: 3, favorite: true, pin: hashPin('1234')),
        Notebook('n2', 'Química'),
      ]);
      final j = roundTrip(idx.toJson());
      expect(j['format'], 3);
      final back = NotesIndex.fromJson(j);
      expect([back.rev, back.last], [4, 'n1']);
      final nb = back.notebooks.first;
      expect([nb.id, nb.name, nb.updated, nb.last, nb.favorite, nb.pin, nb.bg, nb.paper],
          ['n1', 'Física', 99, 3, true, hashPin('1234'), 'grid', '#fbf3e0']);
      expect(nb.sheets, isEmpty, reason: 'las hojas no van en el índice');
      expect(j['notebooks'][1], {'id': 'n2', 'name': 'Química', 'updated': 0, 'bg': 'lined', 'paper': '#fffefb', 'spacing': 8.0, 'last': 0},
          reason: 'favorite y pin solo si están');
    });

    test('hashPin es estable y depende del PIN', () {
      expect(hashPin('1234'), hashPin('1234'));
      expect(hashPin('1234'), isNot(hashPin('4321')));
      expect(hashPin('1234').length, 64);
    });
  });
}
