import 'dart:math';
import 'dart:ui';

import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/history.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stress.dart';

/// Deshacer / rehacer en cadena, intercalado con borrar, pegar, mover, editar textos, reordenar y operaciones de hojas
/// (agregar, duplicar, borrar, mover) entre páginas. Modelo de referencia: la foto del documento después de cada acción.
/// Invariantes:
///   * deshacer TODO vuelve EXACTO al estado inicial; rehacer TODO vuelve EXACTO al final;
///   * en una caminata al azar de deshacer / rehacer / acción nueva, el documento siempre es la foto del punto donde está;
///   * con más de `History.limit` acciones se pierde lo más viejo, pero lo que queda sigue siendo exacto.
void main() {
  void putText(NotebookDoc d, String id, TextBlock? t) => t == null ? d.texts.remove(id) : d.texts[id] = t;

  NotebookDoc initial(Random r) {
    final nb = Notebook.create('U');
    while (nb.sheets.length < 3) {
      nb.sheets.add(nb.newSheet());
    }
    final d = NotebookDoc(nb);
    for (var i = 0; i < 6; i++) {
      final s = randomStroke(r, 'i$i', yBase: r.nextInt(3) * kSheetStep + 50, n: 3 + r.nextInt(10), span: 500, jumps: false);
      s.z = d.nextZ();
      d.strokes[s.id] = s;
    }
    d.texts['ti'] = TextBlock('ti', 90, 44, 800, 'inicial')..z = d.nextZ();
    d.items['ii'] = Item('ii', 'sticky', 100, kSheetStep + 100, 200, 100, text: 'nota')..z = d.nextZ();
    return d;
  }

  var ids = 0;
  String nid(String p) => '$p${ids++}';

  Rect rectOf(Layered e) => switch (e) {
        Stroke s => s.bounds,
        TextBlock t => Rect.fromLTWH(t.x, t.y, t.w, 40),
        Item i => i.rect,
        _ => Rect.zero,
      };

  /// Hace UNA operación al azar sobre [d] y devuelve la acción para deshacerla; null (sin tocar nada) si no se pudo.
  EditAction? randomAction(NotebookDoc d, Random r) {
    final y = r.nextDouble() * (d.sheetCount * kSheetStep - 300);
    switch (r.nextInt(14)) {
      case 0 || 1: // trazo nuevo
        final s = randomStroke(r, nid('s'), yBase: y, n: 2 + r.nextInt(40), span: 400, jumps: false);
        s.z = d.nextZ();
        d.strokes[s.id] = s;
        d.growFor(s.bounds.bottom);
        return EditAction(added: [s]);
      case 2: // goma
        if (d.strokes.isEmpty) return null;
        final s = d.strokes.remove(d.strokes.keys.elementAt(r.nextInt(d.strokes.length)))!;
        return EditAction(removed: [s]);
      case 3: // mover un trazo (a veces a otra hoja)
        if (d.strokes.isEmpty) return null;
        final s = d.strokes.values.elementAt(r.nextInt(d.strokes.length));
        final dy = (r.nextInt(2) == 0 ? r.nextInt(200) - 100 : (r.nextInt(5) - 2) * kSheetStep).toDouble();
        final m = s.moved(Offset((r.nextInt(100) - 50).toDouble(), dy));
        if (m.bounds.top < 0 || m.bounds.bottom > d.h - 10) return null;
        d.strokes[s.id] = m;
        return EditAction(removed: [s], added: [m]);
      case 4: // pegar varios trazos copiados de otra hoja (ids nuevos)
        if (d.strokes.length < 2) return null;
        final src = d.strokes.values.take(1 + r.nextInt(3)).toList();
        final dy = (r.nextInt(d.sheetCount)) * kSheetStep;
        var z = d.nextZ();
        final copies = [
          for (final s in src) s.moved(Offset(20, dy - s.bounds.top + 50), id: nid('p'))..z = z++,
        ];
        if (copies.any((c) => c.bounds.bottom > d.h)) return null;
        for (final c in copies) {
          d.strokes[c.id] = c;
        }
        return EditAction(added: copies);
      case 5: // texto nuevo
        final t = TextBlock(nid('t'), 90, d.snapTextY(y), 800, 'texto ${r.nextInt(99)}')..z = d.nextZ();
        d.texts[t.id] = t;
        return EditAction(textBefore: absent([t.id]), textAfter: {t.id: t.copy()});
      case 6: // editar un texto en el lugar
        if (d.texts.isEmpty) return null;
        final t = d.texts.values.elementAt(r.nextInt(d.texts.length));
        final before = t.copy();
        d.markDirtyElement(t);
        t.text = 'editado ${r.nextInt(999)}';
        if (r.nextInt(3) == 0 && t.y + kSheetStep < d.h - 100) t.y += kSheetStep; // a la hoja de abajo
        d.markDirtyElement(t);
        return EditAction(textBefore: {t.id: before}, textAfter: {t.id: t.copy()});
      case 7: // borrar un texto
        if (d.texts.isEmpty) return null;
        final t = d.texts.remove(d.texts.keys.elementAt(r.nextInt(d.texts.length)))!;
        return EditAction(textBefore: {t.id: t.copy()}, textAfter: absent([t.id]));
      case 8: // nota nueva / borrar nota
        if (d.items.isNotEmpty && r.nextBool()) {
          final i = d.items.remove(d.items.keys.elementAt(r.nextInt(d.items.length)))!;
          return EditAction(itemBefore: {i.id: i.copy()}, itemAfter: absent([i.id]));
        }
        final i = Item(nid('i'), 'sticky', 50, y, 200, 100, text: 'n')..z = d.nextZ();
        d.items[i.id] = i;
        return EditAction(itemBefore: absent([i.id]), itemAfter: {i.id: i.copy()});
      case 9: // reordenar lo "seleccionado"
        final all = d.drawOrder();
        if (all.length < 2) return null;
        final sel = {for (final e in all) if (r.nextInt(4) == 0) e.id};
        final ch = d.reorder(sel, ZMove.values[r.nextInt(4)], rectOf);
        return ch == null ? null : EditAction(zBefore: ch.before, zAfter: ch.after);
      case 10: // hoja nueva al final
        d.addSheet();
        return EditAction(sheetOps: [SheetPresenceOp.added(d, d.sheets.last)]);
      case 11: // duplicar una hoja
        final m = d.duplicateSheet(r.nextInt(d.sheetCount));
        return EditAction(sheetOps: [SheetPresenceOp.added(d, m)]);
      case 12: // borrar una hoja
        final op = SheetPresenceOp.delete(d, r.nextInt(d.sheetCount));
        return op == null ? null : EditAction(sheetOps: [op]);
      default: // mover una hoja
        final op = SheetMoveOp.run(d, r.nextInt(d.sheetCount), r.nextInt(d.sheetCount));
        return op == null ? null : EditAction(sheetOps: [op]);
    }
  }

  void sane(NotebookDoc d, String reason) {
    expect(d.sheetCount, greaterThanOrEqualTo(1), reason: reason);
    expect(d.sheets.map((m) => m.id).toSet().length, d.sheetCount, reason: '$reason: ids de hoja repetidos');
    for (final e in d.drawOrder()) {
      expect(() => d.sheetOfElement(e), returnsNormally, reason: reason);
      expect(d.sheetOfElement(e), inInclusiveRange(0, d.sheetCount - 1), reason: reason);
    }
  }

  group('deshacer todo / rehacer todo', () {
    for (final seed in kSeeds) {
      test('semilla $seed: 150 acciones, ida y vuelta exactas', () {
        final r = Random(seed);
        final d = initial(r);
        final h = History();
        final snaps = [snapshotDocLoose(d)];
        for (var i = 0; i < 150; i++) {
          final a = randomAction(d, r);
          if (a == null) continue;
          h.push(a);
          snaps.add(snapshotDocLoose(d));
          sane(d, 'semilla $seed acción $i');
        }
        expect(snaps.length, greaterThan(100), reason: 'la secuencia no puede quedar vacía por rechazos');
        // deshacer de a una: cada paso es EXACTAMENTE la foto anterior
        for (var i = snaps.length - 1; i > 0; i--) {
          final a = h.undo()!;
          a.apply(d, undo: true, putText: (id, t) => putText(d, id, t));
          expect(snapshotDocLoose(d), snaps[i - 1], reason: 'semilla $seed: deshacer #$i no deja el estado anterior');
        }
        expect(h.canUndo, isFalse);
        // rehacer de a una
        for (var i = 1; i < snaps.length; i++) {
          final a = h.redo()!;
          a.apply(d, undo: false, putText: (id, t) => putText(d, id, t));
          expect(snapshotDocLoose(d), snaps[i], reason: 'semilla $seed: rehacer #$i no deja el estado siguiente');
        }
        expect(h.canRedo, isFalse);
      });
    }
  });

  group('caminata al azar: deshacer, rehacer y acciones nuevas mezcladas', () {
    for (final seed in kSeeds) {
      test('semilla $seed: el documento siempre es la foto de donde está parado', () {
        final r = Random(seed * 101);
        final d = initial(r);
        final h = History();
        final snaps = [snapshotDocLoose(d)];
        var pos = 0;
        for (var step = 0; step < 300; step++) {
          final dice = r.nextInt(10);
          String what;
          if (dice < 5) {
            final a = randomAction(d, r);
            if (a == null) continue;
            h.push(a); // borra el rehacer
            snaps
              ..removeRange(pos + 1, snaps.length)
              ..add(snapshotDocLoose(d));
            pos++;
            what = 'acción';
          } else if (dice < 8) {
            final a = h.undo();
            if (a == null) continue;
            a.apply(d, undo: true, putText: (id, t) => putText(d, id, t));
            pos--;
            what = 'deshacer';
          } else {
            final a = h.redo();
            if (a == null) continue;
            a.apply(d, undo: false, putText: (id, t) => putText(d, id, t));
            pos++;
            what = 'rehacer';
          }
          expect(snapshotDocLoose(d), snaps[pos], reason: 'semilla $seed paso $step ($what) pos $pos');
          sane(d, 'semilla $seed paso $step');
        }
      });
    }

    test('más de ${History.limit} acciones: se olvida lo más viejo y lo que queda es exacto', () {
      final r = Random(99);
      final d = initial(r);
      final h = History();
      final snaps = [snapshotDocLoose(d)];
      while (snaps.length < History.limit + 80) {
        final a = randomAction(d, r);
        if (a == null) continue;
        h.push(a);
        snaps.add(snapshotDocLoose(d));
      }
      var n = 0;
      while (h.canUndo) {
        h.undo()!.apply(d, undo: true, putText: (id, t) => putText(d, id, t));
        n++;
      }
      expect(n, History.limit);
      expect(snapshotDocLoose(d), snaps[snaps.length - 1 - History.limit]);
    });
  });

  group('reordenar (z): propiedades', () {
    for (final seed in kSeeds) {
      test('es una permutación de los mismos z, no mueve a los no seleccionados entre sí y se deshace (semilla $seed)', () {
        final r = Random(seed);
        final d = initial(r);
        for (var i = 0; i < 30; i++) {
          d.items['x$i'] = Item('x$i', 'sticky', r.nextInt(500).toDouble(), r.nextInt(900).toDouble(), 150, 150)..z = d.nextZ();
        }
        for (var it = 0; it < 60; it++) {
          final all = d.drawOrder();
          final sel = {for (final e in all) if (r.nextInt(5) == 0) e.id};
          if (sel.isEmpty) continue;
          final move = ZMove.values[r.nextInt(4)];
          final zsBefore = all.map((e) => e.z).toList()..sort();
          final orderBefore = [for (final e in all) e.id];
          final ch = d.reorder(sel, move, rectOf);
          final after = d.drawOrder();
          final orderAfter = [for (final e in after) e.id];
          if (ch == null) {
            expect(orderAfter, orderBefore, reason: 'semilla $seed it $it: null pero cambió el orden');
            continue;
          }
          // mismos valores de z, repartidos distinto (no se agranda ni se pisa)
          expect(after.map((e) => e.z).toList()..sort(), zsBefore, reason: 'semilla $seed it $it $move');
          expect({for (final e in after) e.z}.length, after.length, reason: 'z repetidos tras reordenar');
          // los NO seleccionados conservan su orden relativo; los seleccionados también
          List<String> only(List<String> o, bool s) => [for (final id in o) if (sel.contains(id) == s) id];
          expect(only(orderAfter, false), only(orderBefore, false), reason: 'semilla $seed it $it $move');
          expect(only(orderAfter, true), only(orderBefore, true), reason: 'semilla $seed it $it $move');
          if (move == ZMove.front) expect(orderAfter.sublist(orderAfter.length - sel.length).toSet(), sel);
          if (move == ZMove.back) expect(orderAfter.sublist(0, sel.length).toSet(), sel);
          // deshacer devuelve el orden anterior
          ch.before.forEach(d.setZ);
          expect([for (final e in d.drawOrder()) e.id], orderBefore, reason: 'semilla $seed it $it: deshacer el reorden');
          ch.after.forEach(d.setZ);
        }
      });
    }
  });
}
