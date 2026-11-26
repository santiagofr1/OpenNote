import 'dart:math';

import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stress.dart';

/// Hojas del cuaderno (agregar, insertar, duplicar, mover, borrar, sacar la última vacía, mover elementos de una hoja a
/// otra): 300 acciones al azar sobre un `NotebookDoc` comparadas con un MODELO independiente: una lista de hojas, cada
/// una con sus elementos en coordenadas LOCALES. Después de cada acción: el documento ve cada elemento en la hoja y a la
/// altura local que dice el modelo, las hojas están en el orden del modelo y partir + rearmar (`splitBySheet` /
/// `fromSheets`, lo que se guarda en disco) da lo mismo.
class _El {
  final String tipo; // s | t | i
  final String id;
  double top; // altura local del borde de arriba
  _El(this.tipo, this.id, this.top);
}

class _Hoja {
  final String id;
  final List<_El> els;
  _Hoja(this.id, this.els);
}

void main() {
  for (final seed in kSeeds) {
    test('300 acciones sobre las hojas (semilla $seed) contra un modelo', () {
      final r = Random(seed);
      final nb = Notebook.create('Hojas');
      final doc = NotebookDoc(nb);
      final modelo = <_Hoja>[_Hoja(nb.sheets[0].id, [])];
      var n = 0;

      double localTop() => 30 + r.nextInt(1200).toDouble();

      /// Agrega al documento un elemento nuevo en la hoja [k] y lo anota en el modelo.
      void agregar(int k, {double? top}) {
        top ??= localTop();
        final y = k * kSheetStep + top;
        final id = '${n++}';
        switch (r.nextInt(3)) {
          case 0:
            doc.strokes['s$id'] = Stroke('s$id', 'pen', '#22211e', 2.0, [50, y + 20, .5, 90, y + 40, .5]);
            // el borde de arriba del trazo es el que dice el trazo (incluye medio grosor)
            modelo[k].els.add(_El('s', 's$id', doc.strokes['s$id']!.bounds.top - k * kSheetStep));
          case 1:
            doc.texts['t$id'] = TextBlock('t$id', 80, y, 800, 'texto $id');
            modelo[k].els.add(_El('t', 't$id', top));
          default:
            doc.items['i$id'] = Item('i$id', 'sticky', 100, y, 120, 80, text: 'nota $id');
            modelo[k].els.add(_El('i', 'i$id', top));
        }
      }

      void verificar(String donde) {
        expect(doc.sheetCount, modelo.length, reason: '$donde: cantidad de hojas');
        expect([for (final m in doc.sheets) m.id], [for (final h in modelo) h.id], reason: '$donde: orden de hojas');
        final vistos = <String>{};
        for (var k = 0; k < modelo.length; k++) {
          for (final e in modelo[k].els) {
            vistos.add(e.id);
            final Layered? obj = switch (e.tipo) { 's' => doc.strokes[e.id], 't' => doc.texts[e.id], _ => doc.items[e.id] };
            expect(obj, isNotNull, reason: '$donde: se perdió ${e.id}');
            expect(doc.sheetOfElement(obj!), k, reason: '$donde: ${e.id} cayó en otra hoja');
            final top = switch (obj) { Stroke s => s.bounds.top, TextBlock t => t.y, Item i => i.y, _ => 0.0 };
            expect(top - k * kSheetStep, closeTo(e.top, 1e-6), reason: '$donde: ${e.id} cambió su altura local');
          }
        }
        final enDoc = {...doc.strokes.keys, ...doc.texts.keys, ...doc.items.keys};
        expect(enDoc, vistos, reason: '$donde: el documento tiene elementos que el modelo no conoce (o al revés)');
        expect(doc.h, closeTo(heightFor(modelo.length), 1e-6));

        // lo que se guarda (hoja por hoja, local) es lo mismo y rearmarlo devuelve el mismo documento
        final partes = doc.splitBySheet();
        expect(partes.length, modelo.length);
        for (var k = 0; k < modelo.length; k++) {
          final ids = {...partes[k].strokes.map((s) => s.id), ...partes[k].texts.map((t) => t.id), ...partes[k].items.map((i) => i.id)};
          expect(ids, {for (final e in modelo[k].els) e.id}, reason: '$donde: splitBySheet hoja $k');
        }
        final copia = Notebook('x', 'x', sheets: [for (final m in doc.sheets) m.copy()]);
        final otro = NotebookDoc.fromSheets(copia, partes);
        expect(snapshotDocLoose(otro), snapshotDocLoose(doc), reason: '$donde: rearmar no da el mismo documento');
        for (var k = 0; k < modelo.length; k++) {
          for (final e in modelo[k].els) {
            final o = otro.strokes[e.id] ?? otro.texts[e.id] ?? otro.items[e.id];
            expect(o, isNotNull, reason: '$donde: rearmar perdió ${e.id}');
            expect(otro.sheetOfElement(o!), k, reason: '$donde: rearmar movió ${e.id}');
          }
        }
        // el orden de dibujo no repite ni pierde a nadie
        final orden = doc.drawOrder().map((e) => e.id).toList();
        expect(orden.toSet().length, orden.length, reason: '$donde: drawOrder repite');
        expect(orden.toSet(), vistos, reason: '$donde: drawOrder');
      }

      for (var i = 0; i < r.nextInt(4); i++) {
        agregar(0);
      }
      verificar('inicio');

      for (var paso = 0; paso < 300; paso++) {
        final donde = 'semilla $seed paso $paso';
        final len = modelo.length;
        switch (r.nextInt(11)) {
          case 0: // agregar hoja al final
            doc.addSheet();
            modelo.add(_Hoja(doc.sheets.last.id, []));
          case 1: // insertar hoja vacía en cualquier lugar (también fuera de rango: se acota)
            final at = r.nextInt(len + 3) - 1;
            final m = doc.insertSheet(at);
            modelo.insert(at.clamp(0, len), _Hoja(m.id, []));
          case 2: // insertar hoja con contenido (importar un PDF)
            final at = r.nextInt(len + 1);
            final top = localTop();
            final c = SheetContent(texts: [TextBlock('t${n++}', 80, top, 800, 'importado')]);
            final m = doc.insertSheet(at, content: c);
            modelo.insert(at, _Hoja(m.id, [_El('t', c.texts.single.id, top)]));
          case 3: // duplicar
            final i = r.nextInt(len);
            final antes = {...doc.strokes.keys, ...doc.texts.keys, ...doc.items.keys};
            final m = doc.duplicateSheet(i);
            final nueva = <_El>[];
            for (final e in modelo[i].els) {
              nueva.add(_El(e.tipo, '?', e.top)); // los ids se estrenan: se buscan abajo
            }
            modelo.insert(i + 1, _Hoja(m.id, nueva));
            final nuevos = [
              for (final s in doc.strokes.values) if (!antes.contains(s.id)) (s.id, 's', s.bounds.top - (i + 1) * kSheetStep),
              for (final t in doc.texts.values) if (!antes.contains(t.id)) (t.id, 't', t.y - (i + 1) * kSheetStep),
              for (final it in doc.items.values) if (!antes.contains(it.id)) (it.id, 'i', it.y - (i + 1) * kSheetStep),
            ];
            expect(nuevos.length, nueva.length, reason: '$donde: la copia tiene la misma cantidad de elementos');
            final esperado = [for (final e in modelo[i].els) '${e.tipo}:${e.top.toStringAsFixed(3)}']..sort();
            final real = [for (final x in nuevos) '${x.$2}:${x.$3.toStringAsFixed(3)}']..sort();
            expect(real, esperado, reason: '$donde: la copia conserva tipos y alturas locales');
            modelo[i + 1].els
              ..clear()
              ..addAll([for (final x in nuevos) _El(x.$2, x.$1, x.$3)]);
          case 4: // borrar
            final i = r.nextInt(len + 2) - 1;
            final ok = doc.deleteSheet(i);
            expect(ok, len >= 2 && i >= 0 && i < len, reason: '$donde: borrar índice $i de $len');
            if (ok) modelo.removeAt(i);
          case 5: // mover
            final from = r.nextInt(len + 2) - 1, to = r.nextInt(len + 2) - 1;
            doc.moveSheet(from, to);
            if (from >= 0 && from < len && to >= 0 && to < len && from != to) modelo.insert(to, modelo.removeAt(from));
          case 6 || 7: // elemento nuevo
            agregar(r.nextInt(len));
          case 8: // sacar un elemento
            final k = r.nextInt(len);
            if (modelo[k].els.isEmpty) break;
            final e = modelo[k].els.removeAt(r.nextInt(modelo[k].els.length));
            if (e.tipo == 's') {
              doc.strokes.remove(e.id);
            } else if (e.tipo == 't') {
              doc.texts.remove(e.id);
            } else {
              doc.items.remove(e.id);
            }
          case 9: // llevar un elemento a otra hoja (como arrastrar la selección)
            final k = r.nextInt(len);
            if (modelo[k].els.isEmpty) break;
            final e = modelo[k].els[r.nextInt(modelo[k].els.length)];
            final k2 = r.nextInt(len);
            final dy = (k2 - k) * kSheetStep;
            switch (e.tipo) {
              case 's':
                final s = doc.strokes[e.id]!;
                doc.markDirtyElement(s);
                s.translateY(dy);
                doc.markDirtyElement(s);
              case 't':
                final t = doc.texts[e.id]!;
                doc.markDirtyElement(t);
                t.y += dy;
                doc.markDirtyElement(t);
              default:
                final it = doc.items[e.id]!;
                doc.markDirtyElement(it);
                it.y += dy;
                doc.markDirtyElement(it);
            }
            modelo[k].els.remove(e);
            modelo[k2].els.add(e);
          default: // sacar la última hoja si está vacía
            final vacia = modelo.last.els.isEmpty;
            final ok = doc.removeLastSheetIfEmpty();
            expect(ok, len >= 2 && vacia, reason: '$donde: removeLastSheetIfEmpty (len $len, vacía $vacia)');
            if (ok) modelo.removeLast();
        }
        verificar(donde);
      }
    });
  }

  test('índices raros: nada tira ni cambia el documento', () {
    final nb = Notebook.create('x');
    final doc = NotebookDoc(nb);
    doc.texts['t'] = TextBlock('t', 10, 10, 800, 'hola');
    for (final i in [-1, 5, 1 << 40, -(1 << 40)]) {
      expect(doc.deleteSheet(i), isFalse);
      doc.moveSheet(i, 0);
      doc.moveSheet(0, i);
    }
    expect(doc.sheetCount, 1);
    expect(doc.texts['t']!.y, 10);
  });
}
