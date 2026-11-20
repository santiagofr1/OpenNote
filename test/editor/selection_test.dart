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
