import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/rendering/stroke_painter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Las puntas de efecto (issue #26): punteado, discontinuo, tiza, rotulador biselado, neón y doble línea.
const newTips = ['dotted', 'dashed', 'chalk', 'chisel', 'neon', 'double'];

/// Una ola que avanza en x (con presión variable): [n] puntos separados [step] unidades.
Stroke wave(String k, {int n = 200, double step = 1.6, double w = 6, double o = 1, String color = '#1e63e9'}) {
  final pts = <double>[];
  for (var i = 0; i < n; i++) {
    pts.addAll([30 + i * step, 200 + sin(i * step / 50) * 80, .2 + .7 * sin(i / 40).abs()]);
  }
  return Stroke('t', k, color, w, pts, o);
}

/// Un garabato con curvas cerradas (rulos) y un giro de 180°.
Stroke scribble(String k, {double w = 6}) {
  final pts = <double>[];
  for (var i = 0; i < 300; i++) {
    final t = i / 299;
    pts.addAll([30 + t * 330 + 30 * cos(t * 2 * pi * 5), 200 + 60 * sin(t * 2 * pi * 5), .3 + .6 * (.5 + .5 * sin(t * 9))]);
  }
  pts.addAll([360, 140, .5, 330, 138, .5, 360, 136, .5]);
  return Stroke('s', k, '#1e63e9', w, pts);
}

void checkValid(StrokeMesh m, String why) {
  for (final p in m.parts) {
    expect(p.idx.length % 3, 0, reason: why);
    if (p.idx.isNotEmpty) expect(p.idx.reduce(max), lessThan(p.vertexCount), reason: why);
    expect(p.pos.every((v) => v.isFinite), isTrue, reason: '$why: sin NaN');
    expect(p.vertexCount, lessThanOrEqualTo(StrokeMesh.maxVertices), reason: why);
    if (p.colors != null) expect(p.colors!.length, p.vertexCount, reason: why);
  }
}

Future<ByteData> render(Stroke s) async {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.drawRect(const ui.Rect.fromLTWH(0, 0, 400, 400), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  paintStroke(c, s);
  final img = await rec.endRecording().toImage(400, 400);
  final d = (await img.toByteData())!;
  img.dispose();
  return d;
}

void main() {
  for (final feather in [0.0, 1.0]) {
    group('puntas nuevas (borde $feather)', () {
      for (final k in newTips) {
        test('$k: mallas válidas (un punto, repetidos, dos puntos, giros cerrados, trazo normal)', () {
          final cases = <String, List<double>>{
            'un punto': [50, 60, .5],
            'dos iguales': [50, 60, .5, 50, 60, .5],
            'tres iguales': [50, 60, .5, 50, 60, .5, 50, 60, .5],
            'dos puntos': [10, 10, .5, 80, 40, .5],
            'dos puntos pegados': [10, 10, .5, 10.01, 10, .5],
            'vuelta en U': [0, 0, .5, 40, 0, .5, 0, 1, .5],
            'giros': [0, 0, .5, 0, 0, .5, 10, 0, .5, 0, 1, .5, 0, 1, .5, 20, 5, .9],
          };
          for (final e in cases.entries) {
            for (final w in [.6, 6.0, 40.0]) {
              final m = buildStrokeMesh(Stroke('z', k, '#112233', w, e.value), feather: feather)!;
              expect(m.parts, isNotEmpty, reason: '$k ${e.key}');
              checkValid(m, '$k ${e.key} w=$w');
              expect(m.vertexCount, greaterThan(0), reason: '$k ${e.key}: se ve algo');
            }
          }
          for (final s in [wave(k), scribble(k)]) {
            final m = buildStrokeMesh(s, feather: feather)!;
            checkValid(m, k);
            expect(m.vertexCount, greaterThan(20));
          }
        });

        test('$k: sin NaN con puntos, presión y grosor raros', () {
          final s = Stroke('z', k, '#112233', 3, [1e4, 1e4, 0, 1e4 + .001, 1e4, 1, -5, -5, .5, -5, -5.0001, .5]);
          checkValid(buildStrokeMesh(s, feather: feather)!, k);
        });

        test('$k: un trazo larguísimo se parte en partes sin pasarse del tope de vértices', () {
          final s = wave(k, n: 30000, step: .8, w: 3);
          final m = buildStrokeMesh(s, feather: feather)!;
          expect(m.parts.length, greaterThan(1), reason: k);
          checkValid(m, k);
        });

        test('$k: dos puntos muy lejos (tramo larguísimo) no revienta el tope', () {
          final s = Stroke('z', k, '#112233', 1, [0, 0, .5, 100000, 50, .5]);
          final m = buildStrokeMesh(s, feather: feather)!;
          checkValid(m, k);
          expect(m.vertexCount, lessThanOrEqualTo(estimateMeshVertices(s)), reason: k);
        });

        test('$k: estimateMeshVertices es cota superior de la malla real', () {
          final cases = <Stroke>[
            wave(k, n: 2000),
            wave(k, n: 2000, step: .3), // muy denso
            wave(k, n: 300, step: 6), // tramos largos
            wave(k, n: 300, w: 1),
            wave(k, n: 300, w: 24),
            scribble(k),
            Stroke('a', k, '#000000', 4, [5, 5, .5]),
            Stroke('b', k, '#000000', 4, [5, 5, .5, 5, 5, .5]),
            Stroke('c', k, '#000000', 4, [5, 5, .5, 50, 5, .5]),
          ];
          for (final s in cases) {
            final m = buildStrokeMesh(s, feather: feather)!;
            expect(m.vertexCount, lessThanOrEqualTo(estimateMeshVertices(s)), reason: '$k n=${s.n} w=${s.w}');
          }
        });

        test('$k: lo que se arma entra en el rectángulo del trazo (también con el halo del neón)', () {
          for (final s in [wave(k), scribble(k), scribble(k, w: 20), Stroke('p', k, '#000000', 12, [100, 100, .5])]) {
            final b = s.bounds, m = buildStrokeMesh(s, feather: feather)!;
            for (final p in m.parts) {
              for (var i = 0; i < p.pos.length; i += 2) {
                // lo que se ve (alfa > 0): los vértices del borde del halo valen alfa 0 y también tienen que entrar
                expect(p.pos[i], inInclusiveRange(b.left - .01, b.right + .01), reason: '$k x w=${s.w}');
                expect(p.pos[i + 1], inInclusiveRange(b.top - .01, b.bottom + .01), reason: '$k y w=${s.w}');
              }
            }
          }
        });

        test('$k: la malla es colorida cuando meshIsColored lo dice', () {
          final s = wave(k);
          final m = buildStrokeMesh(s, feather: feather)!;
          expect(m.colored, meshIsColored(s, feather: feather), reason: k);
        });

        test('$k: es determinística (mismo trazo, misma malla)', () {
          final s = scribble(k);
          final a = buildStrokeMesh(s, feather: feather)!.parts.first, b = buildStrokeMesh(s, feather: feather)!.parts.first;
          expect(a.pos, orderedEquals(b.pos));
          expect(a.colors?.toList(), b.colors?.toList());
        });
      }
    });
  }

  test('vértices por punto: ningún trazo de 2000 puntos pasa de ~25 por punto', () {
    for (final k in newTips) {
      for (final feather in [0.0, 1.0]) {
        for (final s in [wave(k, n: 2000), scribble(k)]) {
          final m = buildStrokeMesh(s, feather: feather)!;
          final perPoint = m.vertexCount / s.n;
          // ignore: avoid_print
          print('$k (borde $feather, n=${s.n}): ${perPoint.toStringAsFixed(1)} vértices/punto');
          expect(perPoint, lessThanOrEqualTo(25), reason: k);
        }
      }
    }
  });

  group('estabilidad al crecer (el trazo se re-malla mientras se dibuja)', () {
    for (final k in newTips) {
      testWidgets('$k: lo ya dibujado no se mueve al agregar puntos', (tester) async {
        await tester.runAsync(() async {
          for (final feather in [0.0, 1.0]) {
            final prev = meshFeather;
            meshFeather = feather;
            addTearDown(() => meshFeather = prev);
            for (final w in [3.0, 7.0]) {
              final full = wave(k, n: 240, w: w);
              final head = Stroke('h', k, full.c, w, full.pts.sublist(0, 160 * 3));
              final a = await render(head), b = await render(full);
              // todo lo que está bien a la izquierda de la punta del trazo corto tiene que quedar igual
              final cut = (head.pts[(160 - 14) * 3] - 8).floor();
              var bad = 0, total = 0;
              for (var y = 0; y < 400; y++) {
                for (var x = 0; x < cut; x++) {
                  final i = (y * 400 + x) * 4;
                  var d = 0;
                  for (var c = 0; c < 4; c++) {
                    d = max(d, (a.getUint8(i + c) - b.getUint8(i + c)).abs());
                  }
                  total++;
                  if (d > 2) bad++;
                }
              }
              expect(total, greaterThan(1000));
              expect(bad, 0, reason: '$k w=$w borde $feather: $bad píxeles cambiaron lejos de la punta');
            }
          }
        });
      });
    }
  });

  test('las puntas nuevas están en la lista del panel, con nombre', () {
    final ids = [for (final t in tips) t.$1];
    for (final k in newTips) {
      expect(ids, contains(k));
    }
    expect(ids.toSet().length, ids.length);
    expect(isPenTip('dotted'), isTrue);
    expect(isPenTip('hl'), isFalse);
    expect(isPenTip('nope'), isFalse);
  });

  test('al cargar los ajustes una punta que no existe cae a pen (y las nuevas se conservan)', () {
    final t = ToolState();
    t.load({'pen': {'tip': 'laser', 'color': '#ff0000', 'width': 3, 'opacity': 1}});
    expect(t.pen.tip, 'pen');
    for (final k in newTips) {
      final u = ToolState();
      u.load({'pen': {'tip': k, 'color': '#ff0000', 'width': 3, 'opacity': 1}});
      expect(u.pen.tip, k);
    }
    final h = ToolState();
    h.load({'hl': {'tip': 'hl', 'color': '#f7d22c', 'width': 22, 'opacity': .4}});
    expect(h.hl.tip, 'hl');
  });

  group('forma que se ve', () {
    test('el punteado tiene huecos y el discontinuo guiones (no una línea continua)', () {
      for (final k in ['dotted', 'dashed']) {
        final s = Stroke('l', k, '#000000', 6, [for (var i = 0; i <= 100; i++) ...[20 + i * 3.0, 100, .5]]);
        final m = buildStrokeMesh(s, feather: 0)!;
        // proyecta los vértices sobre x: tiene que haber huecos de al menos medio grosor sin vértices
        final xs = <double>[for (final p in m.parts) for (var i = 0; i < p.pos.length; i += 2) p.pos[i]]..sort();
        var gaps = 0;
        for (var i = 1; i < xs.length; i++) {
          if (xs[i] - xs[i - 1] > 3) gaps++;
        }
        expect(gaps, greaterThan(5), reason: k);
      }
    });

    test('el punteado y el discontinuo siguen el mismo ritmo al crecer (puntos a 2.2 grosores)', () {
      final s = Stroke('l', 'dotted', '#000000', 4, [for (var i = 0; i <= 200; i++) ...[10 + i * 2.0, 50, .5]]);
      final m = buildStrokeMesh(s, feather: 0)!;
      final centers = <double>[];
      final p = m.parts.first;
      for (var v = 0; v + 10 < p.vertexCount; v += 11) {
        centers.add(p.pos[v * 2]); // el primer vértice de cada punto es el centro
      }
      for (var i = 1; i < centers.length; i++) {
        expect(centers[i] - centers[i - 1], closeTo(4 * 2.2, .05));
      }
    });

    test('la doble línea tiene dos líneas separadas por el grosor (sin cruzarse en una recta)', () {
      final s = Stroke('l', 'double', '#000000', 10, [for (var i = 0; i <= 40; i++) ...[10 + i * 5.0, 100, .5]]);
      final m = buildStrokeMesh(s, feather: 0)!;
      final ys = <double>{};
      for (final p in m.parts) {
        for (var i = 1; i < p.pos.length; i += 2) {
          ys.add((p.pos[i] * 10).round() / 10);
        }
      }
      expect(ys.any((y) => (y - 94).abs() < .6), isTrue); // 100 - 0.6*10
      expect(ys.any((y) => (y - 106).abs() < .6), isTrue);
      expect(ys.where((y) => (y - 100).abs() < 1.5), isEmpty, reason: 'entre las dos líneas no hay tinta');
    });

    test('el neón: núcleo casi blanco y el borde del halo transparente', () {
      final s = Stroke('l', 'neon', '#0000ff', 8, [for (var i = 0; i <= 40; i++) ...[10 + i * 5.0, 100, .5]]);
      final p = buildStrokeMesh(s, feather: 0)!.parts.first;
      final cols = p.colors!;
      var maxA = 0, minA = 255, whitish = false;
      for (final c in cols) {
        final a = (c & 0xFFFFFFFF) >>> 24;
        maxA = max(maxA, a);
        minA = min(minA, a);
        if (a == 255 && (c & 0xFF) > 200 && ((c >> 16) & 0xFF) > 200) whitish = true;
      }
      expect(maxA, 255);
      expect(minA, 0);
      expect(whitish, isTrue);
    });

    test('el rotulador biselado no cambia con la presión', () {
      Stroke at(double pr) => Stroke('l', 'chisel', '#000000', 6, [for (var i = 0; i <= 30; i++) ...[10 + i * 5.0, 100 + sin(i / 4) * 30, pr]]);
      final a = buildStrokeMesh(at(.1), feather: 0)!.parts.first, b = buildStrokeMesh(at(.95), feather: 0)!.parts.first;
      expect(a.pos, orderedEquals(b.pos));
    });
  });

  test('el dibujo viejo de prueba acepta las puntas nuevas', () async {
    for (final k in newTips) {
      for (final s in [scribble(k), Stroke('p', k, '#000000', 4, [5, 5, .5])]) {
        final rec = ui.PictureRecorder();
        paintStrokeLegacy(ui.Canvas(rec), s);
        rec.endRecording().dispose();
      }
    }
  });

  testWidgets('en un lote con otros trazos las puntas nuevas se dibujan igual que solas', (tester) async {
    await tester.runAsync(() async {
      final ss = [
        for (var i = 0; i < newTips.length; i++)
          Stroke('s$i', newTips[i], i.isEven ? '#1e63e9' : '#c0392b', 4,
              [for (var j = 0; j < 60; j++) ...[20 + j * 5.0, 30 + i * 50 + sin(j / 5) * 12, .5]])
            ..z = i,
      ];
      final one = ui.PictureRecorder();
      final c1 = ui.Canvas(one)..drawRect(const ui.Rect.fromLTWH(0, 0, 400, 400), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
      for (final s in ss) {
        paintStroke(c1, s);
      }
      final i1 = await one.endRecording().toImage(400, 400);
      final batched = ui.PictureRecorder();
      final c2 = ui.Canvas(batched)..drawRect(const ui.Rect.fromLTWH(0, 0, 400, 400), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
      paintStrokes(c2, ss);
      final i2 = await batched.endRecording().toImage(400, 400);
      final a = (await i1.toByteData())!, b = (await i2.toByteData())!;
      var bad = 0;
      for (var i = 0; i < a.lengthInBytes; i++) {
        if ((a.getUint8(i) - b.getUint8(i)).abs() > 4) bad++;
      }
      expect(bad, lessThan(a.lengthInBytes * .0005));
    });
  });
}
