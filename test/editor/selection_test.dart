import 'dart:ui';

import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  NotebookDoc page() {
    final p = NotebookDoc(Notebook.create('t'));
    // horizontal de 0 a 100 en y = 50, puntos cada 10
    p.strokes['a'] = Stroke('a', 'pen', '#000000', 2, [for (var x = 0; x <= 100; x += 10) ...[x.toDouble(), 50, .5]]);
    p.strokes['b'] = Stroke('b', 'pen', '#000000', 2, [500, 500, .5, 510, 510, .5]);
    p.texts['t'] = TextBlock('t', 90, 204, 300, 'hola');
    p.items['i'] = Item('i', 'sticky', 600, 0, 100, 100);
    return p;
  }

  group('selectAll', () {
    NotebookDoc three() {
      final nb = Notebook.create('t');
      while (nb.sheets.length < 3) {
        nb.sheets.add(nb.newSheet());
      }
      final d = NotebookDoc(nb);
      for (var k = 0; k < 3; k++) {
        final y = k * kSheetStep + 100;
        d.strokes['s$k'] = Stroke('s$k', 'pen', '#000000', 2, [50, y, .5, 90, y, .5]);
        d.texts['t$k'] = TextBlock('t$k', 90, y + 50, 300, 'hoja $k');
        d.items['i$k'] = Item('i$k', 'sticky', 100, y + 200, 100, 100);
      }
      return d;
    }

    test('con hoja: solo lo de esa hoja (trazos, textos y elementos)', () {
      final d = three(), sel = Selection();
      sel.selectAll(d, sheet: 1);
      expect(sel.strokes, {'s1'});
      expect(sel.texts, {'t1'});
      expect(sel.items, {'i1'});
      sel.selectAll(d, sheet: 2);
      expect(sel.allIds, {'s2', 't2', 'i2'}, reason: 'reemplaza la selección anterior');
    });

    test('sin hoja: todo lo cargado; una hoja sin cargar no aporta nada', () {
      final full = three(), sel = Selection();
      sel.selectAll(full);
      expect(sel.allIds.length, 9);
      final d = NotebookDoc.lazy(full.nb); // solo se cargan las hojas 0 y 1
      for (var k = 0; k < 2; k++) {
        final id = full.sheets[k].id;
        expect(d.attachSheet(id, full.splitSheets({id})[id]!), isTrue);
      }
      sel.selectAll(d);
      expect(sel.allIds.length, 6);
      sel.selectAll(d, sheet: 2);
      expect(sel.isEmpty, isTrue);
    });
  });

  group('selectIn', () {
    test('trazos con la mitad o más de los puntos adentro', () {
      final p = page(), sel = Selection();
      sel.selectIn(p, const Rect.fromLTRB(-5, 0, 45, 100)); // 5 de 11 puntos
      expect(sel.strokes, isEmpty);
      sel.selectIn(p, const Rect.fromLTRB(-5, 0, 55, 100)); // 6 de 11
      expect(sel.strokes, {'a'});
    });

    test('textos y elementos por su centro', () {
      final p = page(), sel = Selection();
      sel.selectIn(p, const Rect.fromLTRB(80, 190, 600, 215));
      expect(sel.texts, isEmpty, reason: 'toca el texto pero no su centro (un renglón: 204..244)');
      sel.selectIn(p, const Rect.fromLTRB(80, 190, 600, 260));
      expect(sel.texts, {'t'});
      sel.selectIn(p, const Rect.fromLTRB(0, 0, 1000, 1000));
      expect(sel.strokes, {'a', 'b'});
      expect(sel.texts, {'t'});
      expect(sel.items, {'i'});
    });

    test('un toque (rectángulo mínimo) no selecciona nada', () {
      final p = page(), sel = Selection()..selectAll(p);
      sel.selectIn(p, const Rect.fromLTRB(50, 50, 52, 52));
      expect(sel.isEmpty, isTrue);
    });
  });

  group('captura (derecha a izquierda)', () {
    test('un trazo que cruza el rectángulo sin puntos adentro se toma en captura y no en ventana', () {
      final p = NotebookDoc(Notebook.create('t'));
      p.strokes['x'] = Stroke('x', 'pen', '#000000', 2, [0, 50, .5, 300, 50, .5]);
      final sel = Selection();
      const r = Rect.fromLTRB(100, 20, 200, 80);
      sel.selectIn(p, r, capture: true);
      expect(sel.strokes, {'x'});
      sel.selectIn(p, r);
      expect(sel.strokes, isEmpty);
    });

    test('parcialmente adentro: ventana no, captura sí', () {
      final p = page(), sel = Selection();
      const r = Rect.fromLTRB(-5, 0, 25, 100); // 3 de 11 puntos de "a"
      sel.selectIn(p, r);
      expect(sel.strokes, isEmpty);
      sel.selectIn(p, r, capture: true);
      expect(sel.strokes, {'a'});
    });

    test('textos y elementos por superposición', () {
      final p = page(), sel = Selection();
      const r = Rect.fromLTRB(80, 190, 650, 215); // toca el texto y la nota, sin sus centros
      sel.selectIn(p, r);
      expect(sel.texts, isEmpty);
      sel.selectIn(p, const Rect.fromLTRB(650, 20, 900, 40), capture: true);
      expect(sel.items, {'i'});
      sel.selectIn(p, r, capture: true);
      expect(sel.texts, {'t'});
      expect(sel.strokes, isEmpty);
    });

    test('la dirección del arrastre define el modo', () {
      final sel = Selection()..bandA = const Offset(100, 10);
      sel.bandB = const Offset(200, 50);
      expect(sel.capture, isFalse);
      sel.bandB = const Offset(20, 50);
      expect(sel.capture, isTrue);
      sel.clear();
      expect(sel.capture, isFalse);
    });
  });

  test('bounds: envuelve lo seleccionado con margen y, al arrastrar, queda en la posición original', () {
    final p = page(), sel = Selection();
    sel.replace(strokes: ['b'], items: ['i']);
    final r = sel.bounds(p)!;
    final b = p.strokes['b']!.bounds.expandToInclude(p.items['i']!.rect).inflate(6);
    expect(r, b);
    sel.startDrag(p, const Offset(600, 50));
    p.items['i']!.x += 200; // el editor mueve los elementos en vivo
    expect(sel.bounds(p), b);
    sel.clear();
    expect(sel.moving, isFalse);
    expect(sel.bounds(p), isNull);
  });

  test('ids que ya no existen se ignoran', () {
    final p = page(), sel = Selection()..replace(strokes: ['a', 'zz'], texts: ['nada']);
    expect(sel.strokesOf(p).map((s) => s.id), ['a']);
    expect(sel.textsOf(p), isEmpty);
  });

  test('clipboardBounds: une trazos, textos y elementos copiados', () {
    final p = page();
    final c = SelectionClipboard()
      ..strokes = [p.strokes['a']!]
      ..items = [p.items['i']!];
    final r = clipboardBounds(c)!;
    expect(r.left, p.strokes['a']!.bounds.left);
    expect(r.right, 700);
    expect(r.top, 0);
    expect(clipboardBounds(SelectionClipboard()), isNull);
    c.texts = [p.texts['t']!];
    expect(clipboardBounds(c)!.bottom, greaterThanOrEqualTo(204 + kLine), reason: 'un texto ocupa al menos un renglón');
  });
}
