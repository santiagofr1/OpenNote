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
      final s = randomStroke(r, 'ini$i', yBase: r.nextInt(3) * kSheetStep + 50, n: 3 + r.nextInt(10), span: 500, jumps: false);
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
  EditAction? _randomAction(NotebookDoc d, Random r, int op) {
    final y = r.nextDouble() * (d.sheetCount * kSheetStep - 300);
    switch (op) {
      case 0 || 1: // trazo nuevo
        final s = randomStroke(r, nid('s'), yBase: y, n: 2 + r.nextInt(40), span: 400, jumps: false);
        s.z = d.nextZ();
        d.strokes[s.id] = s;
        return EditAction(d, added: [s]);
      case 2: // goma
        if (d.strokes.isEmpty) return null;
        final s = d.strokes.remove(d.strokes.keys.elementAt(r.nextInt(d.strokes.length)))!;
        return EditAction(d, removed: [s]);
      case 3: // mover un trazo (a veces a otra hoja)
        if (d.strokes.isEmpty) return null;
        final s = d.strokes.values.elementAt(r.nextInt(d.strokes.length));
        final dy = (r.nextInt(2) == 0 ? r.nextInt(200) - 100 : (r.nextInt(5) - 2) * kSheetStep).toDouble();
        final m = s.moved(Offset((r.nextInt(100) - 50).toDouble(), dy));
        if (m.bounds.top < 0 || m.bounds.bottom > d.h - 10) return null;
        d.strokes[s.id] = m;
        return EditAction(d, removed: [s], added: [m]);
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
        return EditAction(d, added: copies);
      case 5: // texto nuevo
        final t = TextBlock(nid('t'), 90, d.snapTextY(y), 800, 'texto ${r.nextInt(99)}')..z = d.nextZ();
        d.texts[t.id] = t;
        return EditAction(d, textBefore: absent([t.id]), textAfter: {t.id: t.copy()});
      case 6: // editar un texto en el lugar
        if (d.texts.isEmpty) return null;
        final t = d.texts.values.elementAt(r.nextInt(d.texts.length));
        final before = t.copy();
        d.markDirtyElement(t);
        t.text = 'editado ${r.nextInt(999)}';
        if (r.nextInt(3) == 0 && t.y + kSheetStep < d.h - 100) t.y += kSheetStep; // a la hoja de abajo
        d.markDirtyElement(t);
        return EditAction(d, textBefore: {t.id: before}, textAfter: {t.id: t.copy()});
      case 7: // borrar un texto
        if (d.texts.isEmpty) return null;
        final t = d.texts.remove(d.texts.keys.elementAt(r.nextInt(d.texts.length)))!;
        return EditAction(d, textBefore: {t.id: t.copy()}, textAfter: absent([t.id]));
      case 8: // nota nueva / borrar nota
        if (d.items.isNotEmpty && r.nextBool()) {
          final i = d.items.remove(d.items.keys.elementAt(r.nextInt(d.items.length)))!;
          return EditAction(d, itemBefore: {i.id: i.copy()}, itemAfter: absent([i.id]));
        }
        final i = Item(nid('i'), 'sticky', 50, y, 200, 100, text: 'n')..z = d.nextZ();
        d.items[i.id] = i;
        return EditAction(d, itemBefore: absent([i.id]), itemAfter: {i.id: i.copy()});
      case 9: // reordenar lo "seleccionado"
        final all = d.drawOrder();
        if (all.length < 2) return null;
        final sel = {for (final e in all) if (r.nextInt(4) == 0) e.id};
        final ch = d.reorder(sel, ZMove.values[r.nextInt(4)], rectOf);
        return ch == null ? null : EditAction(d, zBefore: ch.before, zAfter: ch.after);
      case 10: // hoja nueva al final
        d.addSheet();
        return EditAction(d, sheetOps: [SheetPresenceOp.added(d, d.sheets.last)]);
      case 11: // duplicar una hoja
        final m = d.duplicateSheet(r.nextInt(d.sheetCount));
        return EditAction(d, sheetOps: [SheetPresenceOp.added(d, m)]);
      case 12: // borrar una hoja
        final op = SheetPresenceOp.delete(d, r.nextInt(d.sheetCount));
        return op == null ? null : EditAction(d, sheetOps: [op]);
      default: // mover una hoja
        final op = SheetMoveOp.run(d, r.nextInt(d.sheetCount), r.nextInt(d.sheetCount));
        return op == null ? null : EditAction(d, sheetOps: [op]);
    }
  }

  final opNames = <EditAction, String>{};
  EditAction? randomAction(NotebookDoc d, Random r, {bool hojas = true}) {
    final op = r.nextInt(hojas ? 14 : 10);
    final a = _randomAction(d, r, op);
    if (a != null) opNames[a] = 'op$op';
    return a;
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
    for (final hojas in [false, true]) {
      for (final seed in kSeeds) {
        final conHojas = hojas ? 'con' : 'sin';
        test('semilla $seed, $conHojas operaciones de hojas: 150 acciones, deshacer paso a paso es exacto', () {
          final r = Random(seed);
          final d = initial(r);
          final h = History();
          final snaps = [snapshotDoc(d)];
          for (var i = 0; i < 150; i++) {
            final a = randomAction(d, r, hojas: hojas);
            if (a == null) continue;
            h.push(a);
            snaps.add(snapshotDoc(d));
            sane(d, 'semilla $seed acción $i');
          }
          expect(snaps.length, greaterThan(100), reason: 'la secuencia no puede quedar vacía por rechazos');
          for (var i = snaps.length - 1; i > 0; i--) {
            final a = h.undo()!;
            a.apply(d, undo: true, putText: (id, t) => putText(d, id, t));
            expect(snapshotDoc(d), snaps[i - 1], reason: 'semilla $seed: deshacer #$i (${opNames[a]}) no deja el estado anterior');
          }
          expect(h.canUndo, isFalse);
        });

        test('semilla $seed, $conHojas operaciones de hojas: deshacer todo y rehacer todo, paso a paso', () {
          final r = Random(seed);
          final d = initial(r);
          final h = History();
          final snaps = [snapshotDoc(d)];
          for (var i = 0; i < 150; i++) {
            final a = randomAction(d, r, hojas: hojas);
            if (a == null) continue;
            h.push(a);
            snaps.add(snapshotDoc(d));
          }
          while (h.canUndo) {
            h.undo()!.apply(d, undo: true, putText: (id, t) => putText(d, id, t));
          }
          expect(snapshotDoc(d), snaps.first);
          for (var i = 1; i < snaps.length; i++) {
            final a = h.redo()!;
            a.apply(d, undo: false, putText: (id, t) => putText(d, id, t));
            expect(snapshotDoc(d), snaps[i], reason: 'semilla $seed: rehacer #$i (${opNames[a]}) no deja el estado siguiente');
          }
          expect(h.canRedo, isFalse);
        });
      }
    }
  });

  group('caminata al azar: deshacer, rehacer y acciones nuevas mezcladas', () {
    for (final hojas in [false, true]) {
      for (final seed in kSeeds) {
        test('semilla $seed, ${hojas ? 'con' : 'sin'} operaciones de hojas: el documento siempre es la foto de donde está parado', () {
          final r = Random(seed * 101);
          final d = initial(r);
          final h = History();
          final snaps = [snapshotDoc(d)];
          var pos = 0;
          for (var step = 0; step < 300; step++) {
            final dice = r.nextInt(10);
            String what;
            if (dice < 5) {
              final a = randomAction(d, r, hojas: hojas);
              if (a == null) continue;
              h.push(a); // borra el rehacer
              snaps
                ..removeRange(pos + 1, snaps.length)
                ..add(snapshotDoc(d));
              pos++;
              what = 'acción ${opNames[a]}';
            } else if (dice < 8) {
              final a = h.undo();
              if (a == null) continue;
              a.apply(d, undo: true, putText: (id, t) => putText(d, id, t));
              pos--;
              what = 'deshacer ${opNames[a]}';
            } else {
              final a = h.redo();
              if (a == null) continue;
              a.apply(d, undo: false, putText: (id, t) => putText(d, id, t));
              pos++;
              what = 'rehacer ${opNames[a]}';
            }
            expect(snapshotDoc(d), snaps[pos], reason: 'semilla $seed paso $step ($what) pos $pos');
            sane(d, 'semilla $seed paso $step');
          }
        });
      }
    }

    // Con carga perezosa: entre paso y paso se sueltan las hojas que el historial no fija (como el editor), a veces se poda
    // el historial por el fondo, y deshacer / rehacer cargan solo lo que la acción pide. La foto se toma con todo cargado
    // y SIN z absolutos: al cargar una hoja sus z se renumeran arriba de todo (solo importa el orden dentro de cada hoja).
    for (final seed in kSeeds) {
      test('semilla $seed, con hojas y con carga / descarga / poda del historial: siempre la foto de donde está parado', () {
        final r = Random(seed * 7919);
        final d = initial(r);
        final disco = _Disco()..guardar(d);
        final h = History();
        final snaps = [snapshotDocLoose(d)];
        var first = 0; // índice en snaps de lo más viejo a lo que se puede volver
        for (var step = 0; step < 400; step++) {
          final dice = r.nextInt(14);
          String what;
          final undoBefore = h.undoCount;
          if (dice < 5) {
            disco.cargarTodo(d); // las acciones nuevas se hacen sobre hojas cargadas
            final a = randomAction(d, r);
            if (a == null) continue;
            h.push(a);
            snaps
              ..removeRange(first + undoBefore + 1, snaps.length)
              ..add(snapshotDocLoose(d));
            first += undoBefore + 1 - h.undoCount; // History.limit puede soltar la más vieja
            what = 'acción ${opNames[a]}';
          } else if (dice < 8 || dice < 10 && !h.canRedo) {
            final a = h.peek(undo: true);
            if (a == null) continue;
            final need = a.sheetIds(d);
            expect(need.every(d.isLoaded), isTrue, reason: 'semilla $seed paso $step: el historial fija las hojas que necesita');
            disco.cargar(d, need);
            h.undo();
            a.apply(d, undo: true, putText: (id, t) => putText(d, id, t));
            what = 'deshacer ${opNames[a]}';
          } else if (dice < 10) {
            final a = h.peek(undo: false);
            if (a == null) continue;
            final need = a.sheetIds(d);
            expect(need.every(d.isLoaded), isTrue, reason: 'semilla $seed paso $step: el historial fija las hojas que necesita');
            disco.cargar(d, need);
            h.redo();
            a.apply(d, undo: false, putText: (id, t) => putText(d, id, t));
            what = 'rehacer ${opNames[a]}';
          } else if (dice < 12) {
            disco.descargar(d, h.sheetIds(d), r);
            what = 'descargar';
          } else {
            // poda: nada es "visible" salvo una hoja al azar
            final visible = {d.sheets[r.nextInt(d.sheetCount)].id};
            h.trim(d, far: {for (final m in d.sheets) m.id}, exempt: const {}, visible: visible, maxFar: 1 + r.nextInt(5));
            first += undoBefore - h.undoCount; // lo que se descartó por el fondo
            what = 'podar';
          }
          // lo que se puede rehacer queda entero o vacío: la lista de fotos acompaña
          final last = first + h.undoCount + h.redoCount + 1;
          if (snaps.length > last) snaps.removeRange(last, snaps.length);
          expect(disco.foto(d), snaps[first + h.undoCount], reason: 'semilla $seed paso $step ($what) deshacer ${h.undoCount} rehacer ${h.redoCount}');
          sane(d, 'semilla $seed paso $step');
        }
      });
    }

    test('más de ${History.limit} acciones: se olvida lo más viejo y lo que queda es exacto', () {
      final r = Random(99);
      final d = initial(r);
      final h = History();
      final snaps = [snapshotDoc(d)];
      while (snaps.length < History.limit + 80) {
        final a = randomAction(d, r);
        if (a == null) continue;
        h.push(a);
        snaps.add(snapshotDoc(d));
      }
      var n = 0;
      while (h.canUndo) {
        h.undo()!.apply(d, undo: true, putText: (id, t) => putText(d, id, t));
        n++;
      }
      expect(n, History.limit);
      expect(snapshotDoc(d), snaps[snaps.length - 1 - History.limit]);
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

/// "Disco" de los tests con carga perezosa: lo último guardado de cada hoja (coordenadas locales), como lo dejaría la
/// `Storage`. Una hoja sin entrada está vacía.
class _Disco {
  final _hojas = <String, SheetContent>{};

  SheetContent leer(String id) => _hojas[id]?.copy() ?? SheetContent();

  /// Guarda lo sucio (solo hojas cargadas) y deja el documento limpio.
  void guardar(NotebookDoc d) {
    final t = d.takeDirty();
    final ids = t.all ? d.loadedSheets : t.ids.where(d.isLoaded).toSet();
    _hojas.addAll(d.splitSheets(ids.toSet()));
  }

  /// Carga las hojas [ids] que existan y no estén cargadas.
  void cargar(NotebookDoc d, Iterable<String> ids) {
    for (final id in ids.toList()) {
      if (d.indexOfSheet(id) >= 0 && !d.isLoaded(id)) d.attachSheet(id, leer(id));
    }
  }

  void cargarTodo(NotebookDoc d) => cargar(d, [for (final m in d.sheets) m.id]);

  /// Suelta algunas hojas cargadas que no están en [fijas] (guarda antes, como la `Storage`).
  void descargar(NotebookDoc d, Set<String> fijas, Random r) {
    guardar(d);
    for (final id in d.loadedSheets) {
      if (!fijas.contains(id) && r.nextBool()) d.detachSheet(id);
    }
  }

  /// Foto del documento COMPLETO (sin z absolutos): carga lo que falta un momento y lo vuelve a soltar.
  String foto(NotebookDoc d) {
    final temp = [for (final m in d.sheets) if (!d.isLoaded(m.id)) m.id];
    cargar(d, temp);
    final s = snapshotDocLoose(d);
    guardar(d);
    for (final id in temp) {
      d.detachSheet(id);
    }
    return s;
  }
}
