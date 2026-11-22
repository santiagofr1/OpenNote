import 'dart:convert';
import 'dart:math';

import 'package:apuntes/data/sheet_codec.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

Stroke wave(String k, {double w = 34, int n = 60, PaintParams? pp}) {
  final pts = <double>[];
  for (var i = 0; i < n; i++) {
    final t = i / (n - 1);
    pts.addAll([100 + t * 330, 300 + sin(t * pi * 3) * 60, .6]);
  }
  return Stroke('t', k, '#f4a7c3', w, pts, .85, pp ?? const PaintParams());
}

void checkValid(MeshPart p) {
  expect(p.idx, isNotEmpty);
  expect(p.idx.length % 3, 0);
  expect(p.idx.reduce(max), lessThan(p.vertexCount));
  expect(p.colors, isNotNull);
  expect(p.colors!.length, p.vertexCount);
  expect(p.pos.every((v) => v.isFinite), isTrue);
}

void main() {
  test('isPaint / isUnderInk', () {
    expect(paintShapes.map((e) => e.$1).every(isPaint), isTrue);
    expect(paintShapes.length, paintShapeIds.length);
    expect(isPaint('pen'), isFalse);
    expect(isPaint('paint-desconocida'), isFalse);
    expect(isUnderInk('hl'), isTrue);
    expect(isUnderInk('paint-stars'), isTrue);
    expect(isUnderInk('pen'), isFalse);
    expect(isUnderInk('pencil'), isFalse);
  });

  for (final (k, _) in paintShapes) {
    group(k, () {
      test('malla no vacía, índices válidos y colores por vértice', () {
        final m = buildStrokeMesh(wave(k))!;
        expect(m.colored, isTrue);
        for (final p in m.parts) {
          checkValid(p);
        }
      });

      test('es determinística', () {
        final a = buildStrokeMesh(wave(k))!, b = buildStrokeMesh(wave(k))!;
        expect(a.parts.length, b.parts.length);
        for (var i = 0; i < a.parts.length; i++) {
          expect(a.parts[i].pos, b.parts[i].pos);
          expect(a.parts[i].idx, b.parts[i].idx);
          expect(a.parts[i].colors, b.parts[i].colors);
        }
      });

      test('bounds contiene todos los vértices (anchos 16, 34 y 70)', () {
        for (final w in [16.0, 34.0, 70.0]) {
          final s = wave(k, w: w);
          final r = s.bounds.inflate(.01);
          for (final part in buildStrokeMesh(s)!.parts) {
            for (var i = 0; i < part.pos.length; i += 2) {
              expect(r.contains(Offset(part.pos[i], part.pos[i + 1])), isTrue, reason: '$k w=$w vértice $i');
            }
          }
        }
      });

      test('un punto deja una mancha con malla válida dentro de bounds', () {
        final s = Stroke('p', k, '#8fd8e0', 34, [100, 100, .5], 1, const PaintParams());
        final m = buildStrokeMesh(s)!;
        expect(m.vertexCount, greaterThan(8));
        final r = s.bounds.inflate(.01);
        for (final p in m.parts) {
          checkValid(p);
          for (var i = 0; i < p.pos.length; i += 2) {
            expect(r.contains(Offset(p.pos[i], p.pos[i + 1])), isTrue);
          }
        }
      });

      test('un trazo larguísimo no pasa el tope de vértices', () {
        final pts = <double>[];
        for (var i = 0; i < 20000; i++) {
          pts.addAll([i * 1.5, 100 + (i.isEven ? 0 : 6), .5]);
        }
        final m = buildStrokeMesh(Stroke('l', k, '#000000', 70, pts, 1, const PaintParams()))!;
        expect(m.parts.length, greaterThan(1));
        for (final p in m.parts) {
          expect(p.vertexCount, lessThan(StrokeMesh.maxVertices));
          expect(p.idx.reduce(max), lessThan(p.vertexCount));
        }
      });
    });
  }

  test('dos puntos muy lejanos (un tramo larguísimo) tampoco pasan el tope', () {
    final m = buildStrokeMesh(Stroke('l', 'paint-stars', '#000000', 70, [0, 0, .5, 500000, 0, .5], 1, const PaintParams(glitter: 1, density: 1)))!;
    for (final p in m.parts) {
      expect(p.vertexCount, lessThan(StrokeMesh.maxVertices));
      expect(p.idx.reduce(max), lessThan(p.vertexCount));
    }
  });

  test('brillo 0 no deja puntitos; más brillo, más vértices', () {
    int count(double g) => buildStrokeMesh(wave('paint-none', pp: PaintParams(glitter: g)))!.vertexCount;
    expect(count(0), lessThan(count(.5)));
    expect(count(.5), lessThan(count(1)));
  });

  test('cantidad y tamaño de las formas cambian la malla; el color propio llega a los vértices', () {
    int count(PaintParams pp) => buildStrokeMesh(wave('paint-stars', pp: pp))!.vertexCount;
    expect(count(const PaintParams(density: .1)), lessThan(count(const PaintParams(density: .9))));
    final none = buildStrokeMesh(wave('paint-none', pp: const PaintParams(glitter: 0)))!.vertexCount;
    expect(count(const PaintParams(glitter: 0, density: 0)), greaterThan(none));
    final gold = buildStrokeMesh(wave('paint-stars', pp: const PaintParams(glitter: 0, shapeColor: '#d4a937')))!;
    final rgbs = {for (final p in gold.parts) ...p.colors!.map((c) => c & 0xFFFFFF)};
    expect(rgbs, contains(0xd4a937));
  });

  test('la pintura se arma igual sin ajustes guardados (pp null)', () {
    final s = Stroke('t', 'paint-hearts', '#f4a7c3', 34, wave('paint-hearts').pts, .85);
    expect(buildStrokeMesh(s)!.vertexCount, buildStrokeMesh(wave('paint-hearts'))!.vertexCount);
  });

  test('la goma toca la franja aunque no esté sobre la línea central', () {
    final s = Stroke('g', 'paint-stars', '#000000', 34, [100, 100, .5, 300, 100, .5]);
    expect(s.hitBy(const Offset(200, 100 + 17), 1), isTrue);
    expect(s.hitBy(const Offset(200, 100 + 60), 1), isFalse);
  });

  group('PaintParams en el trazo (pp)', () {
    const pp = PaintParams(glitter: .3, density: .7, size: .2, shapeColor: 'light');

    test('ida y vuelta JSON; sin pp no agrega ni una clave', () {
      final s = Stroke('a', 'paint-moons', '#e3cfa0', 40, [1, 2, .5], .6, pp);
      final j = jsonDecode(jsonEncode(s.toJson())) as Map;
      expect(j['pp'], {'g': .3, 'sd': .7, 'ss': .2, 'sc': 'light'});
      expect(Stroke.fromJson(j).pp, pp);
      expect(Stroke('b', 'pen', '#000000', 2, [1, 2, .5]).toJson().containsKey('pp'), isFalse);
      expect(Stroke.fromJson({'id': 'x', 'pts': []}).pp, isNull);
    });

    test('claves faltantes: valores por defecto', () {
      final q = PaintParams.fromJson({'g': .9});
      expect((q.glitter, q.density, q.size, q.shapeColor), (.9, .5, .5, null));
    });

    test('moved y transformed conservan pp', () {
      final s = Stroke('a', 'paint-stars', '#f4a7c3', 34, [10, 10, .5, 50, 10, .5], .8, pp);
      expect(s.moved(const Offset(5, 5)).pp, pp);
      expect(s.moved(const Offset(5, 5), id: 'z').pp, pp);
      expect(s.transformed(const Xform(pivot: Offset(0, 0), scale: 2)).pp, pp);
    });

    test('la hoja guarda y lee pp (y la huella lo ve)', () {
      final c = SheetContent(strokes: [
        Stroke('a', 'paint-hearts', '#8fd8e0', 34, [10, 20, .5, 30, 40, .5], .85, pp),
        Stroke('b', 'pen', '#000000', 2, [1, 2, .5]),
      ]);
      final back = decodeSheet(encodeSheet(c));
      expect(back.strokes[0].pp, pp);
      expect(back.strokes[1].pp, isNull);
      expect(sheetDigest(back), sheetDigest(c));
      final other = SheetContent(strokes: [
        Stroke('a', 'paint-hearts', '#8fd8e0', 34, [10, 20, .5, 30, 40, .5], .85, const PaintParams(glitter: 1)),
        Stroke('b', 'pen', '#000000', 2, [1, 2, .5]),
      ]);
      expect(sheetDigest(other), isNot(sheetDigest(c)));
    });
  });

  test('las preferencias guardan y recuperan la pintura (con defaults si faltan)', () {
    final ts = ToolState()
      ..paint.tip = 'paint-clouds'
      ..paint.width = 50
      ..paintParams = const PaintParams(glitter: .3, density: .7, size: .2, shapeColor: 'light');
    final back = ToolState()..load(jsonDecode(jsonEncode(ts.toJson())) as Map);
    expect((back.paint.tip, back.paint.width, back.paintParams), ('paint-clouds', 50, const PaintParams(glitter: .3, density: .7, size: .2, shapeColor: 'light')));
    final old = ToolState()..load({'tool': 'pen'});
    expect((old.paint.tip, old.paintParams), ('paint-stars', const PaintParams()));
    expect((ToolState()..load({'paint': {'tip': 'paint-glitter'}})).paint.tip, 'paint-stars');
  });

  test('con la herramienta de pintura: current, recent y drawing', () {
    final ts = ToolState()..tool = Tool.paint;
    expect(ts.drawing, isTrue);
    expect(ts.current, same(ts.paint));
    expect(ts.recent, same(ts.paintRecent));
    ts.pickColor('#c9b3ec');
    expect(ts.paintRecent.first, '#c9b3ec');
    expect(ts.paint.color, '#c9b3ec');
  });
}
