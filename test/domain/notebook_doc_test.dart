import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cuaderno de [n] hojas con un texto en cada una (y = 44 de su hoja) llamado t0, t1...
NotebookDoc docWith(int n) {
  final nb = Notebook.create('t');
  while (nb.sheets.length < n) {
    nb.sheets.add(nb.newSheet());
  }
  final d = NotebookDoc(nb);
  for (var k = 0; k < n; k++) {
    d.texts['t$k'] = TextBlock('t$k', 90, k * kSheetStep + 44, 800, 'hoja $k');
  }
  return d;
}

/// Orden de los textos por hoja: ['hoja 1', 'hoja 0', ...] según dónde cae cada uno.
List<String> byPosition(NotebookDoc d) {
  final l = d.texts.values.toList()..sort((a, b) => a.y.compareTo(b.y));
  return [for (final t in l) t.text];
}

void main() {
  group('hojas al final', () {
    test('addSheet usa el estilo del cuaderno; growFor agrega hasta tener una de sobra', () {
      final d = NotebookDoc(Notebook.create('t')..bg = 'grid');
      d.addSheet();
      expect(d.sheetCount, 2);
      expect(d.sheets.last.bg, 'grid');
      expect(d.h, heightFor(2));
      d.growFor(10); // lejos del final de... la 2ª hoja termina en h; 10 está arriba: nada
      expect(d.sheetCount, 2);
      d.growFor(d.h - 100);
      expect(d.sheetCount, 3);
    });

    test('lastSheetEmpty y removeLastSheetIfEmpty', () {
      final d = NotebookDoc(Notebook.create('t'))..addSheet();
      expect(d.lastSheetEmpty, isTrue);
      d.texts['t'] = TextBlock('t', 90, kSheetStep + 44, 800, 'hola');
      expect(d.lastSheetEmpty, isFalse);
      expect(d.removeLastSheetIfEmpty(), isFalse);
      d.texts.clear();
      expect(d.removeLastSheetIfEmpty(), isTrue);
      expect(d.sheetCount, 1);
      expect(d.removeLastSheetIfEmpty(), isFalse, reason: 'nunca queda sin hojas');
    });

    test('el cuaderno siempre tiene al menos una hoja', () {
      expect(NotebookDoc(Notebook('n', 'x')).sheetCount, 1);
    });
  });

  group('sheetOfY', () {
    test('el espacio entre hojas cuenta para la de arriba; los extremos se ajustan', () {
      final d = docWith(3);
      expect(d.sheetOfY(0), 0);
      expect(d.sheetOfY(kSheetH + 10), 0, reason: 'en el hueco');
      expect(d.sheetOfY(kSheetStep), 1);
      expect(d.sheetOfY(-50), 0);
      expect(d.sheetOfY(1e6), 2);
    });
  });

  group('operaciones', () {
    test('insertSheet: lo de abajo baja una hoja', () {
      final d = docWith(3);
      final stroke = Stroke('s', 'pen', '#000000', 2, [10, kSheetStep + 100, .5, 20, kSheetStep + 120, .5]);
      d.strokes['s'] = stroke;
      d.items['i'] = Item('i', 'sticky', 0, 2 * kSheetStep + 5, 100, 100);
      final m = d.insertSheet(1);
      expect(d.sheetCount, 4);
      expect(d.sheets[1], same(m));
      expect(byPosition(d), ['hoja 0', 'hoja 1', 'hoja 2'].map((e) => e).toList());
      expect(d.texts['t0']!.y, 44);
      expect(d.texts['t1']!.y, 2 * kSheetStep + 44);
      expect(d.texts['t2']!.y, 3 * kSheetStep + 44);
      expect(stroke.pts[1], 2 * kSheetStep + 100);
      expect(stroke.bounds.top, greaterThan(2 * kSheetStep), reason: 'los bounds se recalculan');
      expect(d.items['i']!.y, 3 * kSheetStep + 5);
    });

    test('insertSheet con contenido (importar un PDF): va en coordenadas locales', () {
      final d = docWith(2);
      d.insertSheet(1,
          meta: SheetMeta('x', title: 'pdf · 1', bg: 'blank'),
          content: SheetContent(items: [Item('im', 'image', 10, 20, 100, 100, file: 'a.png')]));
      expect(d.items['im']!.y, kSheetStep + 20);
      expect(d.sheets[1].title, 'pdf · 1');
      expect(d.texts['t1']!.y, 2 * kSheetStep + 44);
    });

    test('duplicateSheet: copia con ids nuevos justo después, sin tocar lo de arriba', () {
      final d = docWith(3);
      d.strokes['s'] = Stroke('s', 'pen', '#000000', 2, [10, kSheetStep + 100, .5]);
      d.sheets[1].title = 'Ohm';
      d.sheets[1].bookmark = true;
      final m = d.duplicateSheet(1);
      expect(d.sheetCount, 4);
      expect(d.sheets[2], same(m));
      expect([m.title, m.bookmark], ['Ohm (copia)', false]);
      expect(m.id, isNot(d.sheets[1].id));
      expect(d.texts.length, 4);
      final copy = d.texts.values.where((t) => t.text == 'hoja 1' && t.id != 't1').single;
      expect(copy.y, 2 * kSheetStep + 44);
      expect(d.texts['t1']!.y, kSheetStep + 44, reason: 'el original no se movió');
      expect(d.texts['t2']!.y, 3 * kSheetStep + 44, reason: 'lo de abajo bajó');
      expect(d.strokes.length, 2);
      expect(d.strokes.values.map((s) => s.pts[1]), [kSheetStep + 100, 2 * kSheetStep + 100]);
      expect(d.strokes.keys.toSet().length, 2);
    });

    test('deleteSheet: se va lo de esa hoja y lo de abajo sube', () {
      final d = docWith(3);
      d.strokes['s'] = Stroke('s', 'pen', '#000000', 2, [10, kSheetStep + 100, .5]);
      d.strokes['u'] = Stroke('u', 'pen', '#000000', 2, [10, 2 * kSheetStep + 100, .5]);
      expect(d.deleteSheet(1), isTrue);
      expect(d.sheetCount, 2);
      expect(d.texts.keys, ['t0', 't2']);
      expect(d.texts['t2']!.y, kSheetStep + 44);
      expect(d.strokes.keys, ['u']);
      expect(d.strokes['u']!.pts[1], kSheetStep + 100);
    });

    test('deleteSheet: la única hoja no se borra; índices fuera de rango tampoco', () {
      final d = docWith(1);
      expect(d.deleteSheet(0), isFalse);
      expect(d.texts, isNotEmpty);
      final e = docWith(2);
      expect(e.deleteSheet(5), isFalse);
      expect(e.deleteSheet(-1), isFalse);
    });

    test('moveSheet: lleva la hoja con todo lo suyo; las del medio se corren', () {
      final d = docWith(4);
      final ids = d.sheets.map((s) => s.id).toList();
      d.strokes['s'] = Stroke('s', 'pen', '#000000', 2, [10, 100, .5]); // en la hoja 0
      d.moveSheet(0, 2);
      expect(d.sheets.map((s) => s.id), [ids[1], ids[2], ids[0], ids[3]]);
      expect(byPosition(d), ['hoja 1', 'hoja 2', 'hoja 0', 'hoja 3']);
      expect(d.strokes['s']!.pts[1], 2 * kSheetStep + 100);
      d.moveSheet(2, 0);
      expect(byPosition(d), ['hoja 0', 'hoja 1', 'hoja 2', 'hoja 3']);
      expect(d.strokes['s']!.pts[1], 100);
      // hacia atrás y casos sin efecto
      d.moveSheet(3, 1);
      expect(byPosition(d), ['hoja 0', 'hoja 3', 'hoja 1', 'hoja 2']);
      d.moveSheet(1, 1);
      d.moveSheet(9, 0);
      expect(d.sheetCount, 4);
    });
  });

  group('splitBySheet / fromSheets', () {
    test('cada elemento va a la hoja de su borde de arriba, en coordenadas locales', () {
      final d = docWith(3);
      // trazo que empieza en la hoja 1 pero se pasa de largo hacia la 2: va con la 1
      d.strokes['a'] = Stroke('a', 'pen', '#000000', 2, [10, kSheetStep + 1000, .5, 10, 2 * kSheetStep + 50, .5]);
      d.items['i'] = Item('i', 'sticky', 5, 2 * kSheetStep + 7, 100, 100);
      final parts = d.splitBySheet();
      expect(parts.length, 3);
      expect(parts[0].texts.single.y, 44);
      expect(parts[1].texts.single.y, 44);
      expect(parts[1].strokes.single.id, 'a');
      expect(parts[1].strokes.single.pts[1], 1000);
      expect(parts[1].strokes.single.pts[4], kSheetStep + 50);
      expect(parts[2].items.single.y, 7);
      expect(parts[0].strokes, isEmpty);
    });

    test('un elemento por encima o por debajo de todo se ajusta a la primera o la última hoja', () {
      final d = docWith(2);
      d.items['arriba'] = Item('arriba', 'sticky', 0, -30, 10, 10);
      d.items['abajo'] = Item('abajo', 'sticky', 0, 99999, 10, 10);
      final parts = d.splitBySheet();
      expect(parts[0].items.single.id, 'arriba');
      expect(parts[1].items.single.id, 'abajo');
    });

    test('ida y vuelta: split + fromSheets reconstruye el mismo documento', () {
      final d = docWith(3);
      d.strokes['a'] = Stroke('a', 'hl', '#f7d22c', 22, [1, 2, .5, 3, kSheetStep + 4, .7], .5);
      d.strokes['b'] = Stroke('b', 'pen', '#000000', 2, [1, 2 * kSheetStep + 9, .5]);
      d.items['i'] = Item('i', 'image', 0, kSheetStep + 300, 200, 100, file: 'x.png');
      final back = NotebookDoc.fromSheets(d.nb, d.splitBySheet());
      expect(back.strokes.keys.toSet(), d.strokes.keys.toSet());
      for (final id in d.strokes.keys) {
        expect(back.strokes[id]!.pts, d.strokes[id]!.pts);
        expect(back.strokes[id]!.o, d.strokes[id]!.o);
      }
      for (final id in d.texts.keys) {
        expect(back.texts[id]!.y, d.texts[id]!.y);
      }
      expect(back.items['i']!.y, kSheetStep + 300);
    });

    test('mantiene el orden de inserción dentro de cada hoja', () {
      final d = docWith(1);
      for (final id in ['z', 'a', 'm']) {
        d.strokes[id] = Stroke(id, 'pen', '#000000', 2, [1, 1, .5]);
      }
      expect(d.splitBySheet().single.strokes.map((s) => s.id), ['z', 'a', 'm']);
    });

    test('split devuelve copias: tocarlas no cambia el documento', () {
      final d = docWith(2);
      d.splitBySheet()[1].texts.single.y = 0;
      expect(d.texts['t1']!.y, kSheetStep + 44);
    });

    test('NotebookDoc.single: una hoja suelta para miniaturas', () {
      final d = NotebookDoc.single(SheetMeta('h'), SheetContent(texts: [TextBlock('t', 1, 2, 3, 'x')]));
      expect(d.sheetCount, 1);
      expect(d.texts['t']!.y, 2);
    });
  });

  test('Stroke.translateY corre solo la y y recalcula los bounds', () {
    final s = Stroke('s', 'pen', '#000000', 2, [10, 100, .5]);
    final before = s.bounds;
    s.translateY(50);
    expect(s.pts, [10, 150, .5]);
    expect(s.bounds, before.shift(const Offset(0, 50)));
  });
}
