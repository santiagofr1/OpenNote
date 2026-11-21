import 'dart:convert';
import 'dart:math';
import 'dart:ui';

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

    test('cambio de orden: deshacer y rehacer devuelven los z', () {
      final page = NotebookDoc(Notebook.create('t'));
      page.items['a'] = Item('a', 'image', 0, 0, 100, 100)..z = 0;
      page.items['b'] = Item('b', 'image', 0, 0, 100, 100)..z = 1;
      final ch = page.reorder({'a'}, ZMove.front, (e) => e is Item ? e.rect : Rect.zero)!;
      final a = EditAction(zBefore: ch.before, zAfter: ch.after);
      expect(page.drawOrder().map((e) => e.id), ['b', 'a']);
      a.apply(page, undo: true, putText: (id, t) => put(page, id, t));
      expect(page.drawOrder().map((e) => e.id), ['a', 'b']);
      a.apply(page, undo: false, putText: (id, t) => put(page, id, t));
      expect(page.drawOrder().map((e) => e.id), ['b', 'a']);
    });
  });

  group('History.trim (poda por el fondo)', () {
    NotebookDoc doc(int n) {
      final nb = Notebook.create('t');
      while (nb.sheets.length < n) {
        nb.sheets.add(nb.newSheet());
      }
      return NotebookDoc(nb);
    }

    Stroke on(int k, String id) => Stroke(id, 'pen', '#000000', 2, [50, k * kSheetStep + 100, .5, 90, k * kSheetStep + 110, .5]);
    EditAction add(NotebookDoc d, int k, String id) {
      final s = on(k, id);
      d.strokes[id] = s;
      return EditAction(added: [s]);
    }

    Set<String> ids(NotebookDoc d, Iterable<int> ks) => {for (final k in ks) d.sheets[k].id};
    List<EditAction> drain(History h) => [for (; h.canUndo;) h.undo()!];

    test('descarta las más viejas hasta quedar bajo el tope, suelta sus hojas y nunca toca la visible', () {
      final d = doc(30), h = History();
      final all = [for (var k = 0; k < 30; k++) add(d, k, 's$k')];
      all.forEach(h.push);
      final cut = h.trim(d, far: ids(d, Iterable.generate(25)), exempt: const {}, visible: ids(d, [29]));
      expect(cut, isTrue);
      final left = drain(h);
      expect(left.reversed.toList(), all.sublist(13), reason: 'quedan las 17 más nuevas: 12 lejanas + 5 cercanas');
      expect(h.sheetIds(d).intersection(ids(d, Iterable.generate(13))), isEmpty, reason: 'esas hojas se sueltan');
    });

    test('exentas (sucias, seleccionadas...) no cuentan; bajo el tope no se toca nada', () {
      final d = doc(30), h = History();
      for (var k = 0; k < 20; k++) {
        h.push(add(d, k, 's$k'));
      }
      expect(h.trim(d, far: ids(d, Iterable.generate(20)), exempt: ids(d, Iterable.generate(8)), visible: ids(d, [29])), isFalse);
      expect(drain(h).length, 20);
    });

    test('una acción que toca la visible frena el recorte: no se descarta ni lo anterior a ella', () {
      final d = doc(30), h = History();
      final all = [for (var k = 0; k < 29; k++) add(d, k, 's$k')];
      all.insert(3, add(d, 29, 'vis')); // la 4ª acción toca la hoja visible
      all.forEach(h.push);
      h.trim(d, far: ids(d, Iterable.generate(29)), exempt: const {}, visible: ids(d, [29]));
      expect(drain(h).reversed.toList(), all.sublist(3), reason: 'solo las 3 de abajo, antes de la que toca la visible');
    });

    test('si no alcanza con el deshacer, se vacía el rehacer', () {
      final d = doc(30), h = History();
      for (var k = 0; k < 20; k++) {
        h.push(add(d, k, 's$k'));
      }
      for (var i = 0; i < 18; i++) {
        h.undo(); // 18 para rehacer, 2 para deshacer (sobre las hojas 0 y 1)
      }
      expect(h.trim(d, far: ids(d, Iterable.generate(20)), exempt: const {}, visible: ids(d, [29]), maxFar: 1), isTrue);
      expect(h.canUndo, isFalse);
      expect(h.canRedo, isFalse);
    });

    test('deshacer después de la poda anda para lo que quedó', () {
      final d = doc(30), h = History();
      for (var k = 0; k < 30; k++) {
        h.push(add(d, k, 's$k'));
      }
      h.trim(d, far: ids(d, Iterable.generate(25)), exempt: const {}, visible: ids(d, [29]));
      for (final a in drain(h)) {
        a.apply(d, undo: true, putText: (_, _) {});
      }
      expect(d.strokes.keys.toSet(), {for (var k = 0; k < 13; k++) 's$k'}, reason: 'lo descartado ya no se deshace; lo demás sí');
    });

    test('propiedades aleatorias: recorte por el fondo, nunca la visible, bajo el tope o sin más que descartar', () {
      final r = Random(7);
      for (var round = 0; round < 300; round++) {
        final n = 6 + r.nextInt(30), d = doc(n), h = History();
        final acts = <EditAction>[];
        for (var i = 0; i < 1 + r.nextInt(60); i++) {
          acts.add(add(d, r.nextInt(n), 'a$i'));
          h.push(acts.last);
        }
        final undone = r.nextInt(acts.length + 1);
        for (var i = 0; i < undone; i++) {
          h.undo();
        }
        final redoBefore = acts.sublist(acts.length - undone);
        Set<String> pick(double p) => {for (var k = 0; k < n; k++) if (r.nextDouble() < p) d.sheets[k].id};
        final far = pick(.7), exempt = pick(.3), visible = {d.sheets[r.nextInt(n)].id}, max = r.nextInt(10);
        h.trim(d, far: far, exempt: exempt, visible: visible, maxFar: max);
        final nRedo = [for (; h.canRedo;) h.redo()!].length; // pasan al deshacer, en orden
        final all = drain(h).reversed.toList();
        final remainingRedo = all.sublist(all.length - nRedo), remainingUndo = all.sublist(0, all.length - nRedo);
        final before = acts.sublist(0, acts.length - undone);
        // lo que queda de deshacer es un sufijo de lo anterior (se cortó por el fondo)
        expect(remainingUndo, before.sublist(before.length - remainingUndo.length), reason: 'ronda $round');
        // nunca se descartó una acción que toque la visible
        for (final a in before.sublist(0, before.length - remainingUndo.length)) {
          expect(a.sheetIds(d).intersection(visible), isEmpty, reason: 'ronda $round');
        }
        // el rehacer queda entero o vacío
        expect(remainingRedo.isEmpty || remainingRedo.length == redoBefore.length, isTrue);
        // bajo el tope, o ya no se podía descartar más
        final left = {for (final a in [...remainingUndo, ...remainingRedo]) ...a.sheetIds(d)}.intersection(far).difference(exempt);
        final blocked = remainingUndo.isNotEmpty && remainingUndo.first.sheetIds(d).intersection(visible).isNotEmpty;
        expect(left.length <= max || blocked || (remainingUndo.isEmpty && remainingRedo.isEmpty), isTrue, reason: 'ronda $round');
      }
    });
  });
}
