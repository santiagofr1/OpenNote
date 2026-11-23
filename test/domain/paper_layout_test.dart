import 'dart:convert';

import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('milímetros de A4', () {
    test('conversión: la hoja mide 210 x 297 mm', () {
      expect(mmToUnits(210), closeTo(kW, 1e-9));
      expect(mmToUnits(297), closeTo(kSheetH, 0.5));
      expect(unitsToMm(mmToUnits(8)), closeTo(8, 1e-9));
      expect(mmToUnits(1), closeTo(1000 / 210, 1e-9));
    });
  });

  group('renglones', () {
    test('rayado: múltiplos del interlineado, el primero cerca de 25 mm', () {
      for (final s in kLinedSpacings) {
        final ys = ruleYs(s);
        expect((unitsToMm(ys.first) - 25).abs(), lessThan(s / 2 + 1e-9), reason: '$s mm');
        for (var i = 0; i < ys.length; i++) {
          expect(unitsToMm(ys[i]) / s, closeTo((unitsToMm(ys.first) / s).round() + i, 1e-9));
        }
        expect(ys.last, lessThan(kSheetH));
        expect(ys.last + mmToUnits(s), greaterThanOrEqualTo(kSheetH - 1), reason: 'llega hasta abajo');
      }
      expect(unitsToMm(ruleYs(7).first), closeTo(28, 1e-9));
      expect(unitsToMm(ruleYs(8).first), closeTo(24, 1e-9));
      expect(unitsToMm(ruleYs(10).first), closeTo(30, 1e-9));
    });

    test('cuadrícula y puntos: simétricas en la hoja', () {
      for (final s in kGridSpacings) {
        final ys = gridYs(s), top = ys.first, bottom = kSheetH - ys.last;
        expect(bottom, closeTo(top, 1.0), reason: 'mismo margen arriba y abajo ($s mm)');
        final xs = gridXs(s);
        expect(xs.first, closeTo(kW - xs.last, 1e-6), reason: 'mismo margen a los lados ($s mm)');
        expect(unitsToMm(xs[1] - xs[0]), closeTo(s, 1e-9));
      }
    });

    test('opciones de espaciado y valores por defecto', () {
      expect(spacingsFor('lined'), [7, 8, 10]);
      expect(spacingsFor('grid'), [5, 7]);
      expect(spacingsFor('dots'), [5, 7]);
      expect(spacingsFor('blank'), isEmpty);
      expect([defaultSpacing('lined'), defaultSpacing('grid'), defaultSpacing('dots')], [8, 5, 5]);
      expect(validSpacing('grid', 8), 5, reason: 'al pasar de rayado a cuadrícula');
      expect(validSpacing('lined', 10), 10);
    });
  });

  group('texto sobre el renglón', () {
    test('snapTextY por espaciado: cae sobre un renglón de la hoja', () {
      for (final s in kLinedSpacings) {
        final line = mmToUnits(s);
        for (final y in [0.0, 30.0, 77.0, 500.0, 1300.0]) {
          final r = snapTextY(y, 'lined', s);
          final rule = r - textInset(line);
          expect(rule / line, closeTo((rule / line).round(), 1e-9), reason: '$s mm, y=$y');
          expect((r - y).abs(), lessThanOrEqualTo(line / 2 + textInset(line) + 1e-9));
        }
      }
    });

    test('en cuadrícula el renglón es un múltiplo del cuadrito y respeta el margen centrado', () {
      for (final s in kGridSpacings) {
        final o = mmToUnits(gridOriginMm('grid', s)), step = mmToUnits(s);
        final line = textLine('grid', s);
        expect((line / step).round() * step, closeTo(line, 1e-9));
        final r = snapTextY(300, 'grid', s), rule = r - textInset(line) - o;
        expect(rule / line, closeTo((rule / line).round(), 1e-9));
        expect(snapTextY(-50, 'grid', s), closeTo(o + textInset(line), 1e-9), reason: 'nunca antes de la primera línea');
      }
    });

    test('en el margen de arriba da un renglón virtual (no la primera línea del fondo) y nunca es negativo', () {
      for (final s in kLinedSpacings) {
        final line = mmToUnits(s), first = ruleYs(s.toDouble()).first;
        final r = snapTextY(first - line * 1.5, 'lined', s, floor: true);
        expect(r, lessThan(first), reason: '$s mm: arriba de la primera línea');
        expect(r, greaterThanOrEqualTo(0));
        expect(snapTextY(-500, 'lined', s), greaterThanOrEqualTo(0));
      }
      for (final s in kGridSpacings) {
        expect(snapTextY(-500, 'grid', s), greaterThanOrEqualTo(0));
      }
    });

    test('la letra escala con el renglón: 8 mm queda casi como antes', () {
      expect(fontForLine(textLine('lined', 8)), closeTo(20, .1));
      expect(fontForLine(textLine('lined', 10)) / fontForLine(textLine('lined', 7)), closeTo(10 / 7, 1e-9));
    });

    test('NotebookDoc.snapTextY usa el espaciado de la hoja donde cae el texto', () {
      final nb = Notebook.create('x');
      nb.sheets[0].spacing = 10;
      nb.sheets.add(SheetMeta('h2', bg: 'lined', spacing: 7));
      final d = NotebookDoc(nb);
      final a = d.snapTextY(100), b = d.snapTextY(kSheetStep + 100) - kSheetStep;
      expect(a, closeTo(snapTextY(100, 'lined', 10), 1e-9));
      expect(b, closeTo(snapTextY(100, 'lined', 7), 1e-9));
      expect(d.lineAt(5), closeTo(mmToUnits(10), 1e-9));
      expect(d.lineAt(kSheetStep + 5), closeTo(mmToUnits(7), 1e-9));
    });
  });

  group('tamaño de hoja', () {
    test('con a4 todo da lo mismo que sin pasar el tamaño', () {
      for (final s in [7.0, 8.0, 10.0]) {
        expect(ruleYs(s, size: 'a4'), ruleYs(s));
      }
      for (final s in [5.0, 7.0]) {
        expect(gridYs(s, size: 'a4'), gridYs(s));
        expect(gridXs(s, size: 'a4'), gridXs(s));
      }
      for (final bg in ['lined', 'grid', 'dots', 'blank']) {
        expect(textLine(bg, 7, size: 'a4'), textLine(bg, 7));
        for (final y in [0.0, 100.0, 777.0]) {
          expect(snapTextY(y, bg, 7, size: 'a4'), snapTextY(y, bg, 7));
        }
      }
      expect(unitsPerMm('a4'), kMm);
    });

    test('A3 tiene más renglones y más juntos; A5 menos y más separados', () {
      final a4 = ruleYs(8), a3 = ruleYs(8, size: 'a3'), a5 = ruleYs(8, size: 'a5');
      expect(a3.length, greaterThan(a4.length));
      expect(a5.length, lessThan(a4.length));
      expect(a3[1] - a3[0], closeTo(8 * kW / 297, 1e-9));
      expect(a5[1] - a5[0], closeTo(8 * kW / 148, 1e-9));
      expect(textLine('lined', 8, size: 'a3'), closeTo(8 * kW / 297, 1e-9));
      expect(marginUnits('a3'), closeTo(25 * kW / 297, 1e-9));
      expect(topMarginUnits('a5'), closeTo(25 * kW / 148, 1e-9));
    });

    test('tamaños válidos', () {
      expect([validPaperSize('a3'), validPaperSize('a5'), validPaperSize('b5'), validPaperSize(null)], ['a3', 'a5', 'a4', 'a4']);
    });
  });

  group('guardado', () {
    test('el espaciado va en el JSON y los archivos viejos cargan con el por defecto', () {
      final m = SheetMeta('h', bg: 'lined', spacing: 10);
      expect(SheetMeta.fromJson(jsonDecode(jsonEncode(m.toJson())) as Map).spacing, 10);
      expect(SheetMeta.fromJson({'id': 'h', 'bg': 'lined'}).spacing, 8);
      expect(SheetMeta.fromJson({'id': 'h', 'bg': 'grid'}).spacing, 5);
      expect(Notebook.fromJson({'id': 'n', 'name': 'x', 'bg': 'dots'}).spacing, 5);
      final nb = Notebook('n', 'x', spacing: 7)..bg = 'lined';
      expect(nb.newSheet().spacing, 7);
      expect(Notebook.fromJson(jsonDecode(jsonEncode(nb.toJson())) as Map).spacing, 7);
    });

    test('el tamaño de la hoja y del cuaderno: A4 no se escribe, A3 ida y vuelta, inválido cae en A4', () {
      expect(SheetMeta('h').toJson().containsKey('size'), isFalse);
      expect(Notebook('n', 'x').toJson().containsKey('size'), isFalse);
      final m = SheetMeta('h', size: 'a3');
      expect(SheetMeta.fromJson(jsonDecode(jsonEncode(m.toJson())) as Map).size, 'a3');
      expect(m.copy().size, 'a3');
      expect(SheetMeta.fromJson({'id': 'h', 'size': 'b5'}).size, 'a4');
      expect(SheetMeta.fromJson({'id': 'h'}).size, 'a4');
      final nb = Notebook('n', 'x', size: 'a5');
      expect(Notebook.fromJson(jsonDecode(jsonEncode(nb.toJson())) as Map).size, 'a5');
      expect(Notebook.fromJson({'id': 'n', 'name': 'x', 'size': 'b5'}).size, 'a4');
      expect(nb.newSheet().size, 'a5');
      final d = NotebookDoc(Notebook('n', 'x', sheets: [SheetMeta('h', size: 'a3')]));
      expect(d.lineAt(5), closeTo(8 * kW / 297, 1e-9));
      expect(d.sizeAt(5), 'a3');
    });

    test('setBg corrige el espaciado que no existe en el fondo nuevo', () {
      final m = SheetMeta('h', spacing: 10)..setBg('grid');
      expect(m.spacing, 5);
      m.setBg('lined');
      expect(m.spacing, 8);
    });
  });
}
