import 'dart:convert';

import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String snapshot(NotebookDoc p) => jsonEncode({
        'strokes': [for (final s in p.strokes.values) s.toJson()],
        'texts': [for (final t in p.texts.values) t.toJson()],
        'items': [for (final i in p.items.values) i.toJson()],
      });
  void put(NotebookDoc p, String id, TextBlock? t) => t == null ? p.texts.remove(id) : p.texts[id] = t;

  group('History', () {
    test('deshacer y rehacer van y vuelven entre las pilas', () {
      final h = History();
      expect(h.undo(), isNull);
      const a = EditAction(), b = EditAction();
      h.push(a);
      h.push(b);
      expect(h.undo(), same(b));
      expect(h.canRedo, isTrue);
      expect(h.redo(), same(b));
      expect(h.canRedo, isFalse);
      expect(h.undo(), same(b));
      h.push(const EditAction());
      expect(h.canRedo, isFalse, reason: 'una acción nueva borra lo que se podía rehacer');
    });

    test('guarda hasta ${History.limit} acciones', () {
      final h = History();
      final first = EditAction(added: [Stroke('s0', 'pen', '#000000', 1, [])]);
      h.push(first);
      for (var i = 0; i < History.limit; i++) {
        h.push(const EditAction());
      }
      var n = 0;
      EditAction? last;
      while (h.canUndo) {
        last = h.undo();
        n++;
      }
      expect(n, History.limit);
      expect(last, isNot(same(first)), reason: 'la más vieja se descartó');
    });
  });

  group('EditAction.apply', () {
    test('mover trazo, texto y elemento: deshacer y rehacer son simétricos', () {
      final page = NotebookDoc(Notebook.create('t'));
      final s = Stroke('s', 'pen', '#000000', 2, [0, 0, .5, 10, 10, .5]);
      page.strokes['s'] = s;
      page.texts['t'] = TextBlock('t', 90, 44, 800, 'hola');
      page.items['i'] = Item('i', 'sticky', 0, 0, 100, 100);
      final before = snapshot(page);

      // la acción como la arma el editor al soltar un arrastre
      const d = Offset(30, 40);
      final m = s.moved(d);
      page.strokes['s'] = m;
      final tBefore = page.texts['t']!.copy();
      page.texts['t']!.y += 40;
      final iBefore = page.items['i']!.copy();
      page.items['i']!.x += 30;
      final a = EditAction(
        removed: [s],
        added: [m],
        textBefore: {'t': tBefore},
        textAfter: {'t': page.texts['t']!.copy()},
        itemBefore: {'i': iBefore},
        itemAfter: {'i': page.items['i']!.copy()},
      );
      final after = snapshot(page);

      a.apply(page, undo: true, putText: (id, t) => put(page, id, t));
      expect(snapshot(page), before);
      a.apply(page, undo: false, putText: (id, t) => put(page, id, t));
      expect(snapshot(page), after);
      a.apply(page, undo: true, putText: (id, t) => put(page, id, t));
      expect(snapshot(page), before);
    });

    test('borrar y pegar: null = no existe', () {
      final page = NotebookDoc(Notebook.create('t'));
      final t = TextBlock('t', 1, 2, 3, 'x');
      final it = Item('i', 'image', 0, 0, 10, 10, file: 'a.png');
      final a = EditAction(textBefore: absent(['t']), textAfter: {'t': t}, itemBefore: absent(['i']), itemAfter: {'i': it});
      a.apply(page, undo: false, putText: (id, t) => put(page, id, t));
      expect(page.texts.keys, ['t']);
      expect(page.items.keys, ['i']);
      expect(page.texts['t'], isNot(same(t)), reason: 'se pone una copia: la acción no se modifica al seguir editando');
      a.apply(page, undo: true, putText: (id, t) => put(page, id, t));
      expect(page.texts, isEmpty);
      expect(page.items, isEmpty);
    });
  });
}
