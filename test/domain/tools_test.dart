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

  test('prefs: figuras inteligentes, ida y vuelta y por defecto prendidas', () {
    expect(ToolState().shapeSnap, isTrue);
    final a = ToolState()..shapeSnap = false;
    final b = ToolState()..load(jsonDecode(jsonEncode(a.toJson())) as Map);
    expect(b.shapeSnap, isFalse);
    expect((ToolState()..load({'tool': 'pen'})).shapeSnap, isTrue, reason: 'sin la clave queda prendido');
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

  test('favoritos: pickColor no los reordena, setFavorite cambia solo un lugar y cada herramienta tiene los suyos', () {
    final t = ToolState();
    final antes = List<String>.from(t.favorites);
    t.pickColor(antes[2]);
    expect(t.favorites, antes);
    t.setFavorite(2, '#123456');
    expect(t.favorites, [antes[0], antes[1], '#123456', antes[3]]);
    t.setFavorite(4, '#000000');
    t.setFavorite(-1, '#000000');
    expect(t.favorites.length, 4);
    expect(t.penFav[2], '#123456');
    t.tool = Tool.hl;
    expect(t.favorites, same(t.hlFav));
    expect(t.hlFav[2], isNot('#123456'));
    t.tool = Tool.paint;
    expect(t.favorites, same(t.paintFav));
  });

  test('favoritos: ida y vuelta; si están mal en las prefs quedan los de siempre', () {
    final a = ToolState()
      ..setFavorite(1, '#abcdef')
      ..tool = Tool.paint
      ..setFavorite(3, '#fedcba');
    final b = ToolState()..load(jsonDecode(jsonEncode(a.toJson())) as Map);
    expect(b.penFav, a.penFav);
    expect(b.paintFav, a.paintFav);
    expect(b.hlFav, a.hlFav);
    final d = ToolState();
    final c = ToolState()..load({'penFav': ['#111111', '#222222', '#333333'], 'hlFav': ['#111111', 'rojo', '#333333', '#444444']});
    expect(c.penFav, d.penFav);
    expect(c.hlFav, d.hlFav);
    expect(c.paintFav, d.paintFav);
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

  group('pickColor + saveFavorite: toque justo antes del mantener apretado', () {
    var now = DateTime(2026, 1, 1);
    setUp(() {
      now = DateTime(2026, 1, 1);
      ToolState.clock = () => now;
    });
    tearDown(() => ToolState.clock = DateTime.now);

    test('el mismo favorito tocado hace menos de 2 s: se deshace el toque y se guarda el color anterior', () {
      final t = ToolState();
      t.pen.color = '#7b3a43';
      final fav = t.penFav[0];
      t.pickColor(fav);
      now = now.add(const Duration(seconds: 2));
      expect(t.saveFavorite(0), isTrue);
      expect(t.pen.color, '#7b3a43');
      expect(t.penFav[0], '#7b3a43');
      expect(t.penRecent.first, '#7b3a43');
      expect(t.saveFavorite(0), isFalse, reason: 'el registro se limpió');
    });

    test('pasados 2 s no deshace nada', () {
      final t = ToolState();
      t.pen.color = '#7b3a43';
      final fav = t.penFav[0];
      t.pickColor(fav);
      now = now.add(const Duration(seconds: 2, milliseconds: 1));
      expect(t.saveFavorite(0), isFalse);
      expect(t.pen.color, fav);
      expect(t.penFav[0], fav);
    });

    test('otra herramienta no deshace nada', () {
      final t = ToolState();
      t.pen.color = '#7b3a43';
      t.pickColor(t.penFav[0]);
      t.tool = Tool.hl;
      t.hl.color = t.hlFav[0];
      expect(t.saveFavorite(0), isFalse);
      expect(t.pen.color, t.penFav[0]);
    });

    test('un favorito distinto del tocado guarda normal y no deshace', () {
      final t = ToolState();
      t.pen.color = '#7b3a43';
      t.pickColor(t.penFav[0]);
      expect(t.saveFavorite(1), isTrue);
      expect(t.penFav[1], t.penFav[0]);
      expect(t.pen.color, t.penFav[0]);
    });

    test('elegir el color que ya estaba no pisa el registro', () {
      final t = ToolState();
      t.pen.color = '#7b3a43';
      t.pickColor(t.penFav[0]);
      t.pickColor(t.penFav[0]);
      expect(t.saveFavorite(0), isTrue);
      expect(t.pen.color, '#7b3a43');
    });
  });
}
