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
    expect(paintShapes.length, paintShapeIds.length - 1); // 'none' ya no se ofrece (trazos viejos: formas apagadas)
    expect(isPaint('paint-none'), isTrue);
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
    int count(double g) => buildStrokeMesh(wave('paint-stars', pp: PaintParams(glitter: g, shapes: false)))!.vertexCount;
    expect(count(0), lessThan(count(.5)));
    expect(count(.5), lessThan(count(1)));
  });

  test('cantidad y tamaño de las formas cambian la malla; el color propio llega a los vértices', () {
    int count(PaintParams pp) => buildStrokeMesh(wave('paint-stars', pp: pp))!.vertexCount;
    expect(count(const PaintParams(density: .1)), lessThan(count(const PaintParams(density: .9))));
    final none = buildStrokeMesh(wave('paint-stars', pp: const PaintParams(glitter: 0, shapes: false)))!.vertexCount;
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
      expect(j['pp'], {'g': .3, 'sd': .7, 'ss': .2, 'sc': 'light'}); // los valores por defecto nuevos no se guardan
      expect(Stroke.fromJson(j).pp, pp);
      const nuevo = PaintParams(style: 'marker', bg: false, shapes: false);
      final jn = jsonDecode(jsonEncode(Stroke('a', 'paint-moons', '#e3cfa0', 40, [1, 2, .5], .6, nuevo).toJson())) as Map;
      expect((jn['pp'] as Map)['st'], 'marker');
      expect((jn['pp'] as Map)['bg'], false);
      expect((jn['pp'] as Map)['sh'], false);
      expect(Stroke.fromJson(jn).pp, nuevo);
      expect(PaintParams.fromJson({'st': 'raro'}).style, 'brush');
      expect(Stroke('b', 'pen', '#000000', 2, [1, 2, .5]).toJson().containsKey('pp'), isFalse);
      expect(Stroke.fromJson({'id': 'x', 'pts': []}).pp, isNull);
    });

    test('claves faltantes: valores por defecto', () {
      final q = PaintParams.fromJson({'g': .9});
      expect((q.glitter, q.density, q.size, q.shapeColor, q.style, q.bg, q.shapes), (.9, .5, .5, null, 'brush', true, true));
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
    // la vieja opción "Ninguna" pasa a formas apagadas
    final ninguna = ToolState()..load({'paint': {'tip': 'paint-none'}});
    expect((ninguna.paint.tip, ninguna.paintParams.shapes), ('paint-stars', false));
    final nuevos = ToolState()..paintParams = const PaintParams(style: 'hl', bg: false);
    expect((ToolState()..load(jsonDecode(jsonEncode(nuevos.toJson())) as Map)).paintParams, const PaintParams(style: 'hl', bg: false));
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

  group('tipos de trazo, fondo y formas apagables', () {
    Set<int> rgbs(StrokeMesh m) => {for (final p in m.parts) ...p.colors!.map((c) => c & 0xFFFFFF)};
    List<int> alphas(StrokeMesh m) => [for (final p in m.parts) ...p.colors!.map((c) => c >>> 24)];

    test('los tres tipos arman mallas válidas y distintas', () {
      final meshes = {
        for (final st in paintStyleIds) st: buildStrokeMesh(wave('paint-stars', pp: PaintParams(style: st, glitter: 0, shapes: false)))!
      };
      for (final m in meshes.values) {
        for (final p in m.parts) {
          checkValid(p);
        }
      }
      expect(meshes['brush']!.vertexCount, isNot(meshes['hl']!.vertexCount));
      // resaltador: un solo color y alfa parejo; fibra: más opaca que el resaltador
      expect(alphas(meshes['hl']!).toSet().length, 1);
      expect(alphas(meshes['marker']!).toSet().length, 1);
      expect(alphas(meshes['marker']!).first, greaterThan(alphas(meshes['hl']!).first));
      expect(alphas(meshes['brush']!).toSet().length, greaterThan(3));
    });

    test('fondo apagado: solo quedan formas y brillo; con todo apagado se dibuja el fondo igual', () {
      for (final st in paintStyleIds) {
        final full = buildStrokeMesh(wave('paint-stars', pp: PaintParams(style: st)))!.vertexCount;
        final sin = buildStrokeMesh(wave('paint-stars', pp: PaintParams(style: st, bg: false)))!.vertexCount;
        expect(sin, lessThan(full), reason: st);
        expect(sin, greaterThan(0));
      }
      final solo = buildStrokeMesh(wave('paint-stars', pp: const PaintParams(bg: false, glitter: 0, shapeColor: '#d4a937')))!;
      expect(rgbs(solo), {0xd4a937}); // ni una cerda: todo es de las formas
      final nada = buildStrokeMesh(wave('paint-stars', pp: const PaintParams(bg: false, glitter: 0, shapes: false)))!;
      expect(nada.vertexCount, greaterThan(0));
    });

    test('formas apagadas (y el viejo paint-none) no dejan formas', () {
      const off = PaintParams(glitter: 0, shapes: false);
      final a = buildStrokeMesh(wave('paint-stars', pp: off))!.vertexCount;
      final b = buildStrokeMesh(wave('paint-none', pp: const PaintParams(glitter: 0)))!.vertexCount;
      expect(a, b);
      expect(buildStrokeMesh(wave('paint-stars', pp: const PaintParams(glitter: 0)))!.vertexCount, greaterThan(a));
    });

    test('fibra y resaltador: sin cerdas desflecadas, bandas dentro de bounds', () {
      for (final st in ['hl', 'marker']) {
        final s = wave('paint-hearts', pp: PaintParams(style: st));
        final r = s.bounds.inflate(.01);
        for (final part in buildStrokeMesh(s)!.parts) {
          for (var i = 0; i < part.pos.length; i += 2) {
            expect(r.contains(Offset(part.pos[i], part.pos[i + 1])), isTrue, reason: st);
          }
        }
      }
    });
  });

  group('dibujo en vivo y curvas', () {
    // S larga a lo largo de x: los N primeros puntos de la misma curva
    List<double> sCurve(int n) => [
          for (var i = 0; i < n; i++) ...[100 + i * 5.0, 300 + 60 * sin(i * 5.0 / 80), .5]
        ];

    test('al seguir dibujando, brillo y formas de la primera mitad del arco no se mueven', () {
      for (final st in paintStyleIds) {
        for (final n in [100, 400]) {
          // (400 puntos: cruza el corte entre partes de 250)
          final pp = PaintParams(style: st, bg: false, glitter: .7, density: .6);
          List<Offset> firstHalf(int pts) {
            final m = buildStrokeMesh(Stroke('t', 'paint-stars', '#f4a7c3', 34, sCurve(pts), .85, pp))!;
            final xHalf = 100 + 5.0 * n / 2;
            return [
              for (final p in m.parts)
                for (var i = 0; i < p.pos.length; i += 2)
                  if (p.pos[i] < xHalf) Offset(p.pos[i].toDouble(), p.pos[i + 1].toDouble())
            ]..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
          }

          final a = firstHalf(n), b = firstHalf(n + 10);
          expect(a.length, greaterThan(50));
          expect(b.length, a.length, reason: '$st n=$n');
          for (var i = 0; i < a.length; i++) {
            expect((a[i] - b[i]).distance, lessThan(1e-6), reason: '$st n=$n vértice $i');
          }
        }
      }
    });

    /// Cantidad de triángulos de cerda "dados vuelta" (área con signo opuesta a la de todos los de las tiras).
    int plegados(List<double> pts, double w) {
      final s = Stroke('t', 'paint-stars', '#f4a7c3', w, pts, .85, const PaintParams(glitter: 0, shapes: false));
      var neg = 0;
      for (final part in buildStrokeMesh(s)!.parts) {
        for (var i = 0; i < part.idx.length; i += 3) {
          final a = part.idx[i] * 2, b = part.idx[i + 1] * 2, c = part.idx[i + 2] * 2;
          final ar = ((part.pos[b] - part.pos[a]) * (part.pos[c + 1] - part.pos[a + 1]) -
                  (part.pos[b + 1] - part.pos[a + 1]) * (part.pos[c] - part.pos[a])) /
              2;
          if (ar < -1) neg++; // (un pliegue de verdad es de varias unidades de área; el miter de una esquina, no)
        }
      }
      return neg;
    }

    List<double> arcPts(double cx, double cy, double r, double a0, double a1) {
      final n = (((a1 - a0).abs() * r) / 4).ceil();
      return [
        for (var i = 0; i <= n; i++) ...[cx + r * cos(a0 + (a1 - a0) * i / n), cy + r * sin(a0 + (a1 - a0) * i / n), .5]
      ];
    }

    test('S cerrada, espiral y zigzag a 90°: la franja no se pliega', () {
      for (final w in [16.0, 34.0, 70.0]) {
        final r = .6 * w;
        final s = [...arcPts(200, 300, r, pi, 0), ...arcPts(200 + 2 * r, 300, r, pi, 2 * pi).skip(3)];
        expect(plegados(s, w), 0, reason: 'S w=$w');
        final sp = <double>[];
        for (var i = 0; i < 400; i++) {
          final t = i / 400 * 5 * pi, rr = 100 - 55 * i / 400;
          sp.addAll([300 + rr * cos(t), 300 + rr * sin(t), .5]);
        }
        expect(plegados(sp, w), 0, reason: 'espiral w=$w');
        final zz = <double>[];
        var x = 100.0, y = 300.0;
        for (var seg = 0; seg < 6; seg++) {
          for (var i = 0; i < 24; i++) {
            zz.addAll([x, y, .5]);
            x += 5 * .7071;
            y += (seg.isEven ? 1 : -1) * 5 * .7071;
          }
        }
        expect(plegados(zz, w), 0, reason: 'zigzag w=$w');
      }
    });

    test('las uniones entre partes en una curva no dejan huecos: cada parte arranca donde terminó la anterior', () {
      final pts = <double>[];
      for (var i = 0; i < 700; i++) {
        pts.addAll([300 + 120 * cos(i * .03), 300 + 120 * sin(i * .03), .5]);
      }
      final s = Stroke('t', 'paint-stars', '#f4a7c3', 34, pts, .85, const PaintParams(style: 'hl', glitter: 0, shapes: false));
      final m = buildStrokeMesh(s)!;
      expect(m.parts.length, 3);
      // el borde exterior de la banda (vértices pares) del último vértice de una parte = el primero de la siguiente
      for (var k = 0; k + 1 < m.parts.length; k++) {
        final p = m.parts[k], q = m.parts[k + 1];
        final e = p.pos.length - 4; // último par (izq, der)
        for (var j = 0; j < 4; j++) {
          expect((p.pos[e + j] - q.pos[j]).abs(), lessThan(.02), reason: 'unión $k coord $j');
        }
      }
    });
  });
}
