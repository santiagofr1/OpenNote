import 'dart:ui';

import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/live_layer.dart';
import 'package:apuntes/editor/selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pill = Size(24, 17);

  test('pastilla a la izquierda de la barra, centrada con la primera línea', () {
    final p = headingPillRect(const Rect.fromLTWH(200, 100, 300, 20), pill, 1);
    expect(p.right, 200 - 10 - 6);
    expect(p.center.dy, 100 + 10);
  });

  test('con lo marcado muy alto, se centra con los primeros 40 px', () {
    final p = headingPillRect(const Rect.fromLTWH(200, 100, 300, 400), pill, 1);
    expect(p.center.dy, 120);
  });

  test('pegado al borde izquierdo la pastilla va arriba, alineada con la barra', () {
    final p = headingPillRect(const Rect.fromLTWH(20, 100, 300, 20), pill, 1);
    expect(p.left, 10);
    expect(p.bottom, 94);
  });

  test('las medidas escalan con el zoom', () {
    final a = headingPillRect(const Rect.fromLTWH(200, 100, 300, 20), pill, 1);
    final b = headingPillRect(const Rect.fromLTWH(200, 100, 300, 20), pill / 2, 2);
    expect(b.right, closeTo(200 - 8, 1e-9));
    expect(b.width, a.width / 2);
  });

  ({Rect r, Size pill, double sheetTop, double sheetBottom}) item(Rect r, [double top = 0]) => (r: r, pill: pill, sheetTop: top, sheetBottom: top + 1414);

  test('la pastilla de un título que sobresale arriba queda dentro de la hoja', () {
    final p = layoutHeadingPills([item(const Rect.fromLTWH(200, -50, 300, 20))], 1).single;
    expect(p.top, greaterThanOrEqualTo(4));
    expect(p.bottom, lessThanOrEqualTo(1414 - 4));
  });

  test('dos títulos a 5 px: la segunda pastilla va debajo de la primera sin pisarla', () {
    final ps = layoutHeadingPills(
        [item(const Rect.fromLTWH(200, 100, 300, 20)), item(const Rect.fromLTWH(200, 105, 300, 20))], 1);
    expect(ps[1].top, ps[0].bottom + 3);
    expect(ps[1].overlaps(ps[0]), false);
  });

  test('títulos lejanos no se mueven', () {
    final a = const Rect.fromLTWH(200, 100, 300, 20), b = const Rect.fromLTWH(200, 400, 300, 20);
    final ps = layoutHeadingPills([item(b), item(a)], 1);
    expect(ps[0], headingPillRect(b, pill, 1));
    expect(ps[1], headingPillRect(a, pill, 1));
  });

  test('paintLiveLayer con un título del índice no tira excepción', () {
    final doc = NotebookDoc(Notebook.create('T'));
    doc.strokes['s'] = Stroke('s', 'pen', '#000000', 2, [100, 100, .5, 200, 120, .5]);
    final sheet = doc.sheets.first;
    sheet.heads.add(Heading('h', level: 2, title: 'T', ids: ['s']));
    for (final left in [0.0, 100.0]) {
      doc.strokes['s'] = Stroke('s', 'pen', '#000000', 2, [left, 100, .5, left + 100, 120, .5]);
      final c = Canvas(PictureRecorder());
      paintLiveLayer(c,
          doc: doc, scale: 1.5, sel: Selection(), visible: const Rect.fromLTWH(0, 0, 800, 800), outline: buildOutline(doc.nb));
    }
  });
}
