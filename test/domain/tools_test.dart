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
    a.setColor('#5bc8ff');
    final b = ToolState()..load(jsonDecode(jsonEncode(a.toJson())) as Map);
    expect(b.tool, Tool.hl);
    expect(b.pen.tip, 'calli');
    expect(b.hl.width, 30);
    expect(b.hl.color, '#5bc8ff');
    expect(b.hlFav[0], '#5bc8ff', reason: 'el favorito elegido sigue al color');
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

  test('fresco: el favorito elegido de cada herramienta es el 0 (su color por defecto)', () {
    final t = ToolState();
    expect([t.penFavSel, t.hlFavSel, t.paintFavSel], [0, 0, 0]);
    expect(t.pen.color, t.penFav[0]);
    expect(t.hl.color, t.hlFav[0]);
    expect(t.paint.color, t.paintFav[0]);
  });

  test('useFavorite elige el lugar y pone su color; fuera de rango no hace nada', () {
    final t = ToolState();
    t.useFavorite(2);
    expect(t.favSel, 2);
    expect(t.pen.color, t.penFav[2]);
    t.useFavorite(9);
    t.useFavorite(-1);
    expect(t.favSel, 2);
  });

  test('setColor edita el favorito elegido; sin elegido no toca los favoritos', () {
    final t = ToolState();
    final antes = List<String>.from(t.penFav);
    t.useFavorite(1);
    t.setColor('#7b3a43');
    expect(t.pen.color, '#7b3a43');
    expect(t.penFav, [antes[0], '#7b3a43', antes[2], antes[3]]);
    t.favSel = -1;
    t.setColor('#123456');
    expect(t.pen.color, '#123456');
    expect(t.penFav, [antes[0], '#7b3a43', antes[2], antes[3]]);
  });

  test('addFavorite suma el color actual, lo elige y llega hasta kFavMax', () {
    final t = ToolState();
    t.favSel = -1;
    t.setColor('#abcdef');
    expect(t.addFavorite(), isTrue);
    expect(t.penFav.length, 5);
    expect(t.penFav.last, '#abcdef');
    expect(t.favSel, 4);
    while (t.penFav.length < ToolState.kFavMax) {
      expect(t.addFavorite(), isTrue);
    }
    expect(t.penFav.length, 8);
    expect(t.addFavorite(), isFalse);
    expect(t.penFav.length, 8);
  });

  test('removeFavorite: ajusta el elegido y siempre queda uno', () {
    final t = ToolState();
    t.useFavorite(2);
    expect(t.removeFavorite(0), isTrue);
    expect(t.penFav.length, 3);
    expect(t.favSel, 1, reason: 'el elegido corre un lugar');
    expect(t.removeFavorite(2), isTrue);
    expect(t.favSel, 1, reason: 'borrar uno posterior no lo mueve');
    expect(t.removeFavorite(1), isTrue);
    expect(t.favSel, -1, reason: 'borraron el elegido');
    expect(t.penFav.length, 1);
    expect(t.removeFavorite(0), isFalse);
    expect(t.removeFavorite(5), isFalse);
    expect(t.penFav.length, 1);
  });

  test('favoritos: cada herramienta tiene los suyos y su propio elegido', () {
    final t = ToolState();
    t.useFavorite(2);
    t.tool = Tool.hl;
    expect(t.favorites, same(t.hlFav));
    expect(t.favSel, 0);
    t.useFavorite(3);
    t.setColor('#111111');
    expect(t.hlFav[3], '#111111');
    expect(t.penFav[3], isNot('#111111'));
    t.tool = Tool.paint;
    expect(t.favorites, same(t.paintFav));
    expect(t.favSel, 0);
    t.tool = Tool.pen;
    expect(t.favSel, 2);
    t.tool = Tool.shape;
    expect(t.favorites, same(t.penFav));
    expect(t.current, same(t.pen));
  });

  test('favoritos: ida y vuelta con largo variable y elegido', () {
    final a = ToolState()
      ..useFavorite(1)
      ..setColor('#abcdef')
      ..addFavorite()
      ..tool = Tool.paint
      ..removeFavorite(3);
    final b = ToolState()..load(jsonDecode(jsonEncode(a.toJson())) as Map);
    expect(b.penFav, a.penFav);
    expect(b.penFav.length, 5);
    expect(b.paintFav.length, 3);
    expect(b.hlFav, a.hlFav);
    expect([b.penFavSel, b.hlFavSel, b.paintFavSel], [a.penFavSel, a.hlFavSel, a.paintFavSel]);
    expect(b.penFavSel, 4);
  });

  test('favoritos: claves viejas de recientes se ignoran; favSel inválido cae al índice del color', () {
    final t = ToolState()
      ..load({
        'penRecent': ['#111111'],
        'penFav': ['#111111', '#22211e', '#333333'],
        'pen': {'color': '#22211e'},
        'penFavSel': 7,
        'hlFavSel': 'x',
        'paintFavSel': -3,
      });
    expect(t.penFavSel, 1);
    expect(t.hlFavSel, 0);
    expect(t.paintFavSel, 0);
    expect(t.toJson().keys, isNot(contains('penRecent')));
    final u = ToolState()..load({'penFav': ['#111111', '#222222'], 'pen': {'color': '#999999'}});
    expect(u.penFavSel, -1);
  });

  test('favoritos: si están mal en las prefs quedan los de siempre', () {
    final d = ToolState();
    final c = ToolState()
      ..load({
        'penFav': [],
        'hlFav': ['#111111', 'rojo', '#333333', '#444444'],
        'paintFav': List.generate(9, (i) => '#00000$i'),
      });
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
}
