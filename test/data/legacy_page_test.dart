import 'dart:convert';

import 'package:apuntes/data/legacy_page.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> roundTrip(Map<String, dynamic> j) => jsonDecode(jsonEncode(j)) as Map<String, dynamic>;

void main() {
  test('valores que faltan: los de siempre', () {
    final p = LegacyPage.fromJson({
      'id': 'x',
      'layout': 2,
      'strokes': {
        's': {'id': 's', 'pts': [[1, 2], [3, 4, .8]]}
      },
      'texts': {
        't': {'id': 't'}
      },
      'items': {
        'i': {'id': 'i', 'type': 'image'}
      },
    });
    expect(p.h, kSheetH);
    expect(p.bg, 'lined');
    expect(p.paper, '#fffefb');
    final s = p.strokes['s']!;
    expect([s.k, s.c, s.w, s.o], ['pen', '#22211e', 2, 1]);
    expect(s.pts, [1, 2, .5, 3, 4, .8], reason: 'sin presión = .5');
    expect(p.texts['t']!.w, 800);
    expect(p.items['i']!.w, 200);
  });

  test('layout 1 → 2: corre todo por el espacio entre hojas', () {
    final old = {
      'id': 'v1',
      'h': 2 * kSheetH, // dos hojas pegadas
      'strokes': {
        'a': {'id': 'a', 'pts': [[10, 100, .5], [20, kSheetH + 100, .5]]}
      },
      'texts': {
        't': {'id': 't', 'x': 90, 'y': kSheetH + 44, 'w': 800, 'text': 'hoja 2'}
      },
      'items': {
        'i': {'id': 'i', 'type': 'sticky', 'x': 0, 'y': 50, 'w': 100, 'h': 100}
      },
    };
    final p = LegacyPage.fromJson(old);
    expect(p.h, heightFor(2));
    expect(p.strokes['a']!.pts, [10, 100, .5, 20, kSheetStep + 100, .5]);
    expect(p.strokes['a']!.bounds.bottom, greaterThan(kSheetStep + 100), reason: 'los bounds se recalculan');
    expect(p.texts['t']!.y, kSheetStep + 44);
    expect(p.items['i']!.y, 50, reason: 'lo de la primera hoja no se mueve');
  });

  test('layout 2: no se vuelve a correr', () {
    final p = LegacyPage.fromJson(roundTrip({
      'id': 'v2',
      'layout': 2,
      'h': heightFor(2),
      'texts': {
        't': {'id': 't', 'x': 90, 'y': kSheetStep + 44, 'w': 800, 'text': 'hoja 2'}
      },
    }));
    expect(p.texts['t']!.y, kSheetStep + 44);
    expect(p.h, heightFor(2));
  });
}
