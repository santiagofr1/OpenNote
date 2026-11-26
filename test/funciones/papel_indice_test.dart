import 'dart:convert';
import 'dart:math';

import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/stress.dart';

/// Fondos y tamaños de papel (propiedades de la geometría) e índice del cuaderno (numeración y títulos que siguen a
/// lo que marcan cuando las hojas se mueven o se borran).
void main() {
  const fondos = ['lined', 'grid', 'dots', 'mm', 'axes', 'blank', 'cornell', 'todo', 'image', 'cualquier-cosa'];
  const tamanos = ['a5', 'a4', 'a3'];

  group('papel', () {
    test('validPaperSize: cualquier objeto da uno de los tres tamaños', () {
      for (final v in [null, 3, 'A4', 'a6', '', [], {}, 'a5', 'a3', 'a4', double.nan, true]) {
        expect(tamanos, contains(validPaperSize(v)), reason: '$v');
      }
      expect(validPaperSize('a5'), 'a5');
      expect(validPaperSize('a3'), 'a3');
    });

    test('las tres hojas tienen la misma proporción (la hoja lógica es la misma)', () {
      for (final t in tamanos) {
        expect(paperWidthMm(t) * unitsPerMm(t), closeTo(kW, 1e-9));
        expect(paperHeightMm(t) * unitsPerMm(t) / kSheetH, closeTo(1, 1e-2), reason: t);
      }
    });

    test('rayado: renglones crecientes, parejos y dentro de la hoja, con todos los interlineados y tamaños', () {
      for (final t in tamanos) {
        for (final sp in kLinedSpacings) {
          final ys = ruleYs(sp, size: t);
          expect(ys, isNotEmpty, reason: '$t $sp');
          for (var i = 0; i < ys.length; i++) {
            expect(ys[i], greaterThan(0));
            expect(ys[i], lessThan(paperHeightMm(t) * unitsPerMm(t)), reason: '$t $sp: renglón fuera de la hoja');
            if (i > 0) expect(ys[i] - ys[i - 1], closeTo(sp * unitsPerMm(t), 1e-6));
          }
        }
      }
    });

    test('cuadrícula: simétrica (sobra lo mismo arriba y abajo), dentro de la hoja y pareja', () {
      for (final t in tamanos) {
        for (final sp in kGridSpacings) {
          final ys = gridYs(sp, size: t), xs = gridXs(sp, size: t);
          expect(ys.first + ys.last, closeTo(paperHeightMm(t) * unitsPerMm(t), 1e-6), reason: '$t $sp: no está centrada');
          for (final y in ys) {
            expect(y, inInclusiveRange(0, paperHeightMm(t) * unitsPerMm(t) + 1e-6));
          }
          for (final x in xs) {
            expect(x, inExclusiveRange(0, kW + 1e-6));
          }
          // el origen de los ejes cae sobre la cuadrícula
          final (ox, oy) = axesOrigin(sp, size: t);
          expect(xs.any((x) => (x - ox).abs() < 1e-9), isTrue);
          expect(ys.any((y) => (y - oy).abs() < 1e-9), isTrue);
        }
      }
    });

    test('milimetrado: pesos 2/1/0 cada 10/5/1 mm y todo dentro de la hoja', () {
      for (final t in tamanos) {
        for (final l in [...mmYs(size: t), ...mmXs(size: t)]) {
          expect(l.$1, inInclusiveRange(0, paperHeightMm(t) * unitsPerMm(t) + 0.01));
          expect([0, 1, 2], contains(l.$2));
        }
        expect(mmXs(size: t).where((l) => l.$2 == 2).length, ((paperWidthMm(t) - 0.001) ~/ 10), reason: t);
      }
    });

    test('snapTextY: idempotente, cae a menos de medio renglón y el "de arriba" nunca queda por debajo (todos los fondos)', () {
      final r = Random(3);
      for (final bg in fondos) {
        final sps = spacingsFor(bg).isEmpty ? [8.0] : spacingsFor(bg);
        for (final sp in sps) {
          for (final t in tamanos) {
            final linea = textLine(bg, sp, size: t);
            for (var i = 0; i < 200; i++) {
              final y = r.nextDouble() * kSheetH;
              final s = snapTextY(y, bg, sp, size: t);
              expect(snapTextY(s, bg, sp, size: t), closeTo(s, 1e-6), reason: '$bg $sp $t y=$y: no es idempotente');
              if (y <= linea) continue; // arriba de todo manda el primer renglón (no hay renglones por encima)
              final a = snapTextY(y, bg, sp, floor: true, size: t);
              expect(a, lessThanOrEqualTo(y + 1e-6), reason: '$bg $sp $t: floor pasó de largo y=$y');
              expect(y - a, lessThan(linea + 1e-6), reason: '$bg $sp $t: floor muy lejos');
              expect((s - y).abs(), lessThanOrEqualTo(linea / 2 + 1e-6), reason: '$bg $sp $t y=$y');
            }
          }
        }
      }
    });

    test('snapToGrid: idempotente, dentro de la hoja, y los fondos sin cuadrícula no mueven el punto', () {
      final r = Random(4);
      for (final bg in fondos) {
        final sps = spacingsFor(bg).isEmpty ? [8.0] : spacingsFor(bg);
        for (final sp in sps) {
          for (final t in tamanos) {
            for (var i = 0; i < 100; i++) {
              final p = Offset(r.nextDouble() * kW, r.nextDouble() * kSheetH);
              final s = snapToGrid(p, bg, sp, t);
              final s2 = snapToGrid(s, bg, sp, t);
              expect((s2 - s).distance, lessThan(1e-6), reason: '$bg $sp $t $p: no es idempotente');
              if (!['grid', 'dots', 'axes', 'mm'].contains(bg)) expect(s, p);
              if (['grid', 'dots', 'axes', 'mm'].contains(bg)) {
                expect(s.dx, inInclusiveRange(-1e-6, kW + 1e-6), reason: '$bg $sp $t');
                expect(s.dy, inInclusiveRange(-1e-6, paperHeightMm(t) * unitsPerMm(t) + 1e-6), reason: '$bg $sp $t');
              }
            }
          }
        }
      }
    });

    test('cambiar de fondo muchas veces siempre deja un espaciado válido para ese fondo y no suelta la imagen de otro fondo', () {
      final r = Random(5);
      final m = SheetMeta('h', image: 'foto.png', bg: 'image');
      for (var i = 0; i < 500; i++) {
        final bg = fondos[r.nextInt(fondos.length)];
        m.setBg(bg);
        final ops = spacingsFor(bg);
        expect(ops.isEmpty ? m.spacing == defaultSpacing(bg) : ops.contains(m.spacing), isTrue, reason: '$bg -> ${m.spacing}');
        if (bg != 'image') expect(m.image, isNull, reason: 'un fondo que no es imagen no guarda la imagen');
        if (i % 7 == 0) m.setBg('image');
        if (m.bg == 'image' && m.image == null) m.image = 'foto.png';
      }
    });

    test('SheetMeta JSON: ida y vuelta con valores al azar (también por jsonEncode)', () {
      final r = Random(6);
      for (var i = 0; i < 500; i++) {
        final bg = fondos[r.nextInt(fondos.length)];
        final m = SheetMeta('h$i',
            title: kNombresRaros[r.nextInt(kNombresRaros.length)],
            bookmark: r.nextBool(),
            bg: bg,
            image: r.nextBool() ? 'm$i.png' : null,
            paper: '#${r.nextInt(1 << 24).toRadixString(16).padLeft(6, '0')}',
            spacing: r.nextBool() ? null : (r.nextInt(100) / 4),
            size: tamanos[r.nextInt(3)],
            rev: r.nextInt(1000),
            updated: r.nextInt(1 << 31),
            section: r.nextBool() ? '' : 'sec${r.nextInt(4)}',
            heads: [
              for (var j = 0; j < r.nextInt(4); j++)
                Heading('t$j', level: 1 + r.nextInt(5), title: kNombresRaros[r.nextInt(kNombresRaros.length)], y: tenth(r).abs(), ids: ['a$j'], hidden: r.nextBool())
            ]);
        final j = jsonEncode(m.toJson());
        final m2 = SheetMeta.fromJson(jsonDecode(j) as Map);
        expect(jsonEncode(m2.toJson()), j, reason: 'it $i');
        expect(m2.title, m.title);
        expect(m2.heads.length, m.heads.length);
      }
    });

    test('el lienzo crece en saltos de 500, nunca achica, y crecer dos veces = crecer una', () {
      final r = Random(8);
      for (var i = 0; i < 2000; i++) {
        final w = kCanvasW0 + 500 * r.nextInt(40);
        final right = r.nextDouble() * 30000 - 1000;
        final g = grownCanvasW(w, right);
        expect(g, greaterThanOrEqualTo(w));
        expect(g % 500, 0.0);
        expect(g > w ? g >= right + 800 : right <= w - 400, isTrue, reason: 'w=$w right=$right g=$g');
        expect(grownCanvasW(g, right), g, reason: 'w=$w right=$right: no es estable');
      }
    });
  });

  group('índice', () {
    /// Cuaderno con secciones y títulos al azar. Cada título marca un trazo propio (que no existe: solo importa la numeración).
    Notebook cuaderno(Random r) {
      final nb = Notebook.create('Índice');
      for (var s = 0; s < r.nextInt(3); s++) {
        nb.addSection('S$s');
      }
      for (var k = 0; k < r.nextInt(6); k++) {
        nb.sheets.add(nb.newSheet());
        if (nb.sections.length > 1 && r.nextBool()) nb.otherSheets.add(nb.newSheet(section: nb.sections[1 + r.nextInt(nb.sections.length - 1)].id));
      }
      var n = 0;
      for (final m in nb.allSheets) {
        for (var j = 0; j < r.nextInt(5); j++) {
          m.heads.add(Heading('t${n++}', level: r.nextInt(9) - 1, title: 'T$n', y: r.nextInt(8).toDouble() * 100, hidden: r.nextInt(5) == 0));
        }
      }
      return nb;
    }

    for (final seed in kSeeds) {
      test('buildOutline (semilla $seed): numeración coherente, sin saltos de nivel, sin ocultos', () {
        final r = Random(seed);
        for (var it = 0; it < 200; it++) {
          final nb = cuaderno(r);
          final out = buildOutline(nb);
          final visibles = [for (final m in nb.allSheets) ...m.heads.where((h) => !h.hidden)];
          expect(out.length, visibles.length, reason: 'it $it: cada título visible sale una vez');
          expect(out.map((e) => e.headingId).toSet(), visibles.map((h) => h.id).toSet(), reason: 'it $it');
          OutlineEntry? prev;
          for (final e in out) {
            final partes = e.number.split('.').map(int.parse).toList();
            expect(partes.length, e.level, reason: 'it $it: ${e.number} tiene que tener tantas partes como su nivel');
            expect(partes.every((p) => p >= 1), isTrue, reason: 'it $it: ${e.number}');
            if (prev == null || prev.sectionId != e.sectionId) {
              expect(e.number, '1', reason: 'it $it: el primero de cada sección es 1 (la numeración reinicia)');
              expect(e.level, 1);
            } else {
              final p = prev.number.split('.').map(int.parse).toList();
              expect(e.level, lessThanOrEqualTo(prev.level + 1), reason: 'it $it: salto de nivel ${prev.number} -> ${e.number}');
              if (e.level == prev.level + 1) {
                expect(partes, [...p, 1]);
              } else {
                expect(partes, [...p.sublist(0, e.level - 1), p[e.level - 1] + 1], reason: 'it $it: ${prev.number} -> ${e.number}');
              }
            }
            expect(e.sheet, inInclusiveRange(0, nb.sheetCountOf(e.sectionId) - 1));
            expect(nb.sheetsOf(e.sectionId)[e.sheet].id, e.sheetId);
            prev = e;
          }
          // dentro de una hoja, por altura
          final porHoja = <String, List<double>>{};
          for (final e in out) {
            (porHoja[e.sheetId] ??= []).add(e.y);
          }
          for (final ys in porHoja.values) {
            expect([...ys]..sort(), ys, reason: 'it $it: los títulos de una hoja van por altura');
          }
        }
      });
    }

    test('títulos con el mismo nivel y altura mantienen el orden en que se crearon', () {
      final nb = Notebook.create('x');
      nb.sheets.first.heads.addAll([for (var i = 0; i < 20; i++) Heading('t$i', y: 50, title: 'T$i')]);
      expect(buildOutline(nb).map((e) => e.title), [for (var i = 0; i < 20; i++) 'T$i']);
    });

    Stroke trazo(String id, double y) => Stroke(id, 'pen', '#22211e', 2.0, [50, y, .5, 90, y + 20, .5]);

    for (final seed in kSeeds) {
      test('los títulos siguen a lo que marcan al mover, duplicar, borrar y sacar hojas (semilla $seed)', () {
        final r = Random(seed);
        final nb = Notebook.create('x');
        final doc = NotebookDoc(nb);
        for (var k = 0; k < 4; k++) {
          doc.addSheet();
        }
        // un trazo y un título por hoja
        for (var k = 0; k < doc.sheetCount; k++) {
          final top = 100.0 + r.nextInt(900);
          doc.strokes['s$k'] = trazo('s$k', k * kSheetStep + top);
          doc.sheets[k].heads.add(Heading('h$k', ids: ['s$k'], title: 'Hoja $k', y: doc.strokes['s$k']!.bounds.top - k * kSheetStep));
        }
        for (var paso = 0; paso < 200; paso++) {
          final donde = 'semilla $seed paso $paso';
          final len = doc.sheetCount;
          switch (r.nextInt(6)) {
            case 0:
              doc.moveSheet(r.nextInt(len), r.nextInt(len));
            case 1:
              doc.deleteSheet(r.nextInt(len));
            case 2:
              doc.duplicateSheet(r.nextInt(len));
            case 3:
              doc.insertSheet(r.nextInt(len + 1));
            case 4: // borrar un trazo marcado (y volver a ponerlo a veces)
              final ids = doc.strokes.keys.toList();
              if (ids.isEmpty) break;
              final id = ids[r.nextInt(ids.length)];
              final s = doc.strokes.remove(id)!;
              syncHeadings(doc);
              final h = [for (final m in doc.sheets) ...m.heads].where((h) => h.ids.contains(id));
              for (final x in h) {
                expect(x.hidden, isTrue, reason: '$donde: sin su trazo el título se oculta');
              }
              if (r.nextBool()) {
                doc.strokes[id] = s; // deshacer
                syncHeadings(doc);
                for (final x in [for (final m in doc.sheets) ...m.heads].where((h) => h.ids.contains(id))) {
                  expect(x.hidden, isFalse, reason: '$donde: al volver el trazo reaparece el título');
                }
              }
            default:
              doc.addSheet();
          }
          // mover / borrar / insertar hojas no cambia lo que los títulos marcan: no hay nada que corregir
          final cambio = syncHeadings(doc);
          if (paso % 2 == 0) expect(syncHeadings(doc), isFalse, reason: '$donde: sincronizar dos veces seguidas no cambia nada (cambio la primera: $cambio)');
          // invariante: cada título visible marca algo que está en SU hoja, a la altura que dice
          for (var k = 0; k < doc.sheetCount; k++) {
            for (final h in doc.sheets[k].heads.where((h) => !h.hidden)) {
              final s = doc.strokes[h.ids.first];
              expect(s, isNotNull, reason: '$donde: título visible sin lo marcado');
              expect(doc.sheetOfElement(s!), k, reason: '$donde: el título "${h.title}" quedó en una hoja distinta a la de su trazo');
              expect(h.y, closeTo(s.bounds.top - k * kSheetStep, 0.06), reason: '$donde: altura del título');
            }
          }
        }
      });
    }
  });
}
