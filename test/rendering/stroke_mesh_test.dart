import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/rendering/stroke_painter.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = 400;

/// Trazo de prueba: una onda con presión que sube y baja, y un giro cerrado al final (para probar las uniones).
Stroke wave(String k, {double w = 6, double o = 1, String color = '#22211e', int n = 70, bool sharp = true}) {
  final pts = <double>[];
  for (var i = 0; i < n; i++) {
    final t = i / (n - 1);
    pts.addAll([30 + t * 330, 200 + sin(t * pi * 3) * 90, .2 + .7 * sin(t * pi)]);
  }
  if (sharp) pts.addAll([330, 120, .6, 360, 118, .5]); // zigzag cerrado
  return Stroke('t', k, color, w, pts, o);
}

Future<ByteData> render(void Function(ui.Canvas) draw) async {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.drawRect(ui.Rect.fromLTWH(0, 0, _size.toDouble(), _size.toDouble()), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  draw(c);
  final img = await rec.endRecording().toImage(_size, _size);
  final d = (await img.toByteData())!;
  img.dispose();
  return d;
}

/// (diferencia media por canal 0..255, fracción de píxeles con algún canal a más de 48 de diferencia)
(double, double) compare(ByteData a, ByteData b) {
  var sum = 0, bad = 0;
  for (var i = 0; i < a.lengthInBytes; i += 4) {
    var mx = 0;
    for (var k = 0; k < 3; k++) {
      final d = (a.getUint8(i + k) - b.getUint8(i + k)).abs();
      sum += d;
      if (d > mx) mx = d;
    }
    if (mx > 48) bad++;
  }
  final px = a.lengthInBytes / 4;
  return (sum / (px * 3), bad / px);
}

void main() {
  // Umbrales: el dibujo nuevo no puede ser pixel a pixel igual (los bordes caen distinto, las uniones redondas son
  // polígonos, la curva se aproxima), pero a ojo tiene que ser el mismo trazo: diferencia media por canal < 1.0 de
  // 255 y menos del 2 % de los píxeles de la imagen con algún canal a más de 48. El lápiz tiene un piso más alto
  // porque el dibujo viejo apilaba alfa en cada unión de tramos (cuentas) y la malla es continua.
  final cases = <String, (Stroke, double, double)>{
    'bolígrafo': (wave('pen'), 1.0, .02),
    'pluma': (wave('fountain'), 1.0, .02),
    'fibra': (wave('fine', w: 5), 1.0, .02),
    'resaltador': (wave('hl', w: 18, color: '#f5c518', sharp: false), 1.0, .02),
    'lápiz': (wave('pencil', w: 5), 2.5, .03),
    'caligrafía': (wave('calli', w: 6), 1.0, .02),
    'bolígrafo con opacidad': (wave('pen', o: .5), 1.0, .02),
    'resaltador con opacidad': (wave('hl', w: 18, o: .4, color: '#f5c518', sharp: false), 1.0, .02),
    'un punto (bolígrafo)': (Stroke('p', 'pen', '#22211e', 8, [200, 200, .8]), 1.0, .02),
    'un punto (lápiz)': (Stroke('p', 'pencil', '#22211e', 8, [200, 200, .8]), 1.0, .02),
    'un punto (resaltador)': (Stroke('p', 'hl', '#f5c518', 18, [200, 200, .8]), 1.0, .02),
  };
  for (final e in cases.entries) {
    testWidgets('igual al dibujo de antes: ${e.key}', (tester) async {
      await tester.runAsync(() async {
        final (s, meanMax, badMax) = e.value;
        final old = await render((c) => paintStrokeLegacy(c, s));
        final neu = await render((c) => paintStroke(c, s));
        final (mean, bad) = compare(old, neu);
        // ignore: avoid_print
        print('${e.key}: media ${mean.toStringAsFixed(3)}, píxeles > 48: ${(bad * 100).toStringAsFixed(3)} %');
        expect(mean, lessThan(meanMax));
        expect(bad, lessThan(badMax));
      });
    });
  }

  testWidgets('con borde difuminado (antialias) sigue igual', (tester) async {
    await tester.runAsync(() async {
      final prev = kMeshFeather;
      kMeshFeather = 1;
      addTearDown(() => kMeshFeather = prev);
      for (final k in ['pen', 'fountain', 'fine', 'calli']) {
        final s = wave(k);
        final old = await render((c) => paintStrokeLegacy(c, s));
        final neu = await render((c) => paintStroke(c, s));
        final (mean, bad) = compare(old, neu);
        expect(mean, lessThan(1.0), reason: k);
        expect(bad, lessThan(.02), reason: k);
      }
    });
  });

  testWidgets('lote de trazos igual a dibujarlos de a uno', (tester) async {
    await tester.runAsync(() async {
      final ss = [
        for (var i = 0; i < 12; i++)
          Stroke('s$i', i % 4 == 3 ? 'fine' : 'pen', i % 5 == 4 ? '#c0392b' : '#22211e', 3, [
            for (var j = 0; j < 40; j++) ...[20 + j * 8.0, 20 + i * 30 + sin(j / 4 + i) * 12, .5],
          ])
            ..z = i,
      ];
      final one = await render((c) {
        for (final s in ss) {
          paintStroke(c, s);
        }
      });
      final batched = await render((c) => paintStrokes(c, ss));
      final (mean, bad) = compare(one, batched);
      expect(mean, lessThan(.05), reason: 'juntar en un lote no cambia nada');
      expect(bad, lessThan(.001));
      final legacy = await render((c) {
        for (final s in ss) {
          paintStrokeLegacy(c, s);
        }
      });
      // contra el dibujo de antes: la diferencia crece con la tinta (12 trazos, ~0.23 cada uno)
      expect(compare(legacy, batched).$1, lessThan(3.5));
      // el lote juntó los 10 trazos seguidos del mismo color en uno
      expect(ss.first.batchCache, isNotNull);
    });
  });

  group('malla', () {
    test('un punto es un círculo y no hay vértices fuera de la hoja de más', () {
      final m = buildStrokeMesh(Stroke('p', 'pen', '#000000', 8, [10, 20, .5]))!;
      expect(m.parts, hasLength(1));
      final r = m.parts.first;
      expect(r.vertexCount, 17);
      for (var i = 0; i < r.pos.length; i += 2) {
        expect((r.pos[i] - 10).abs(), lessThanOrEqualTo(8 * (.35 + 1.3 * .5) / 2 + .01));
      }
    });

    test('bytes por punto dentro del presupuesto (< 40 en bolígrafo, pluma, fibra y resaltador)', () {
      for (final k in ['pen', 'fountain', 'fine', 'hl']) {
        final s = wave(k, n: 2000, sharp: false);
        final m = buildStrokeMesh(s)!;
        final perPoint = m.bytes / s.n;
        // ignore: avoid_print
        print('$k: ${perPoint.toStringAsFixed(1)} B/punto');
        expect(perPoint, lessThan(40), reason: k);
      }
    });

    test('un trazo larguísimo se parte en partes de menos de 65k vértices', () {
      final s = wave('pencil', n: 40000, sharp: false);
      final m = buildStrokeMesh(s)!;
      expect(m.parts.length, greaterThan(1));
      for (final p in m.parts) {
        expect(p.vertexCount, lessThan(StrokeMesh.maxVertices));
        expect(p.idx.reduce(max), lessThan(p.vertexCount));
      }
    });

    test('índices válidos en todas las puntas, con giros cerrados y puntos repetidos', () {
      for (final k in ['pen', 'fountain', 'fine', 'hl', 'pencil', 'calli']) {
        final s = Stroke('z', k, '#112233', 4, [0, 0, .5, 0, 0, .5, 10, 0, .5, 0, 1, .5, 0, 1, .5, 20, 5, .9]);
        final m = buildStrokeMesh(s)!;
        for (final p in m.parts) {
          expect(p.idx.length % 3, 0);
          expect(p.idx.reduce(max), lessThan(p.vertexCount), reason: k);
          expect(p.pos.every((v) => v.isFinite), isTrue, reason: k);
        }
      }
    });
  });

  group('caché de la malla', () {
    test('se arma una vez y se descarta al cambiar el trazo', () {
      final s = wave('pen');
      final m1 = s.ensureMesh();
      expect(identical(s.ensureMesh(), m1), isTrue);
      final y0 = m1!.parts.first.pos[1];
      s.pts[1] += 10;
      s.invalidate();
      expect(s.mesh, isNull, reason: 'tocar los puntos y avisar descarta la malla');
      expect(s.ensureMesh()!.parts.first.pos[1], isNot(y0));
      s.pts[1] -= 10;
      s.invalidate();
      expect(s.ensureMesh()!.parts.first.pos[1], closeTo(y0, .01));
      s.translateY(50); // mover el trazo en el lugar: la malla se corre, no se recalcula
      final shifted = Float32List.fromList(s.mesh!.parts.first.pos);
      expect(shifted[1], closeTo(y0 + 50, .01));
      s.mesh = null;
      final rebuilt = s.ensureMesh()!.parts.first.pos;
      for (var i = 0; i < rebuilt.length; i++) {
        expect(shifted[i], closeTo(rebuilt[i], .01));
      }
      s.smooth();
      expect(s.mesh, isNull);
    });

    test('mover o escalar (puntos nuevos) y deshacer dan la malla de los puntos de ese momento', () {
      final s = wave('pen');
      final original = Float32List.fromList(s.ensureMesh()!.parts.first.pos);
      final before = List<double>.of(s.pts);
      // escalar x2 en el lugar, como la selección
      for (var i = 0; i < s.pts.length; i += 3) {
        s.pts[i] *= 2;
        s.pts[i + 1] *= 2;
      }
      s.invalidate();
      final scaled = s.ensureMesh()!.parts.first.pos;
      expect((scaled[1] - original[1]).abs(), greaterThan(1));
      // deshacer: vuelven los puntos
      for (var i = 0; i < before.length; i++) {
        s.pts[i] = before[i];
      }
      s.invalidate();
      final back = s.ensureMesh()!.parts.first.pos;
      expect(back, orderedEquals(original));
      // una copia movida no hereda la malla
      expect(s.moved(const ui.Offset(5, 5)).mesh, isNull);
    });

    test('el lote se rehace si cambia un trazo que no es el primero', () {
      final ss = [
        for (var i = 0; i < 4; i++) Stroke('s$i', 'pen', '#000000', 3, [10, 10.0 + i * 20, .5, 100, 10.0 + i * 20, .5]),
      ];
      final rec = ui.PictureRecorder();
      final c = ui.Canvas(rec);
      paintStrokes(c, ss);
      final b1 = ss.first.batchCache;
      expect(b1, isNotNull);
      paintStrokes(c, ss);
      expect(identical(ss.first.batchCache, b1), isTrue, reason: 'sin cambios se reusa');
      ss[2].pts[1] += 30;
      ss[2].invalidate();
      paintStrokes(c, ss);
      expect(identical(ss.first.batchCache, b1), isFalse);
      rec.endRecording().dispose();
    });
  });
}
