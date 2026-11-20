import 'dart:convert';

import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prefs: ida y vuelta', () {
    final a = ToolState()
      ..tool = Tool.hl
      ..eraserSize = 2
      ..dock = 'left'
      ..zoom = 1.5
      ..zoomLocked = true;
    a.pen.tip = 'calli';
    a.hl.width = 30;
    a.pickColor('#5bc8ff');
    final b = ToolState()..load(jsonDecode(jsonEncode(a.toJson())) as Map);
    expect(b.tool, Tool.hl);
    expect(b.pen.tip, 'calli');
    expect(b.hl.width, 30);
    expect(b.hl.color, '#5bc8ff');
    expect(b.hlRecent.first, '#5bc8ff');
    expect([b.eraserSize, b.dock, b.zoom, b.zoomLocked], [2, 'left', 1.5, true]);
  });

  test('prefs viejas o raras: valores por defecto y límites', () {
    final t = ToolState()..load({'tool': 'laser', 'dock': 'bottom', 'zoom': 9, 'eraserSize': 7, 'pen': {'width': 3}});
    expect(t.tool, Tool.pen);
    expect(t.dock, 'top');
    expect(t.zoom, 4);
    expect(t.eraserSize, 2);
    expect(t.pen.width, 3);
    expect(t.pen.color, '#22211e', reason: 'lo que falta queda como estaba');
    ToolState().load(null); // sin prefs.json
  });

  test('pickColor: el elegido va primero, sin repetir, hasta 7', () {
    final t = ToolState();
    for (final c in ['#000001', '#000002', '#000003', '#1d4ed8']) {
      t.pickColor(c);
    }
    expect(t.penRecent.first, '#1d4ed8');
    expect(t.penRecent.where((c) => c == '#1d4ed8').length, 1);
    expect(t.penRecent.length, 7);
    expect(t.pen.color, '#1d4ed8');
  });

  test('current y eraserRadius según la herramienta', () {
    final t = ToolState();
    expect(t.current, same(t.pen));
    t.tool = Tool.hl;
    expect(t.current, same(t.hl));
    expect(t.drawing, isTrue);
    t.tool = Tool.select;
    expect(t.drawing, isFalse);
    expect(t.eraserRadius, eraserSizes[1]);
  });

  test('el portapapeles no se guarda en prefs', () {
    final t = ToolState();
    t.clipboard.texts = [TextBlock('t', 0, 0, 100, 'x')];
    expect(t.clipboard.isEmpty, isFalse);
    expect(t.toJson().keys, isNot(contains('clipboard')));
  });
}
