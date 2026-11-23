import 'dart:math';
import 'dart:ui' as ui;

import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/rendering/stroke_painter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Microbenchmark orientativo (en la PC, rasterizador por software): una hoja densa de ~46k puntos
/// (800 trazos de bolígrafo de 57 puntos) con el dibujo de antes contra las mallas.
/// Imprime los números; solo exige que las mallas ya armadas graben más rápido que el método viejo.
void main() {
  List<Stroke> sheet() {
    final r = Random(1);
    return [
      for (var i = 0; i < 800; i++)
        Stroke('s$i', 'pen', '#22211e', 2.6, [
          for (var j = 0; j < 57; j++) ...[40 + (i % 8) * 90 + j * 1.4, 30 + (i ~/ 8) * 13 + sin(j / 5 + i) * 4 + r.nextDouble() * .3, .3 + .4 * r.nextDouble()],
        ])
          ..z = i,
    ];
  }

  int recordUs(void Function(ui.Canvas) draw) {
    final sw = Stopwatch()..start();
    final rec = ui.PictureRecorder();
    draw(ui.Canvas(rec));
    final p = rec.endRecording();
    sw.stop();
    p.dispose();
    return sw.elapsedMicroseconds;
  }

  Future<int> rasterUs(void Function(ui.Canvas) draw) async {
    final rec = ui.PictureRecorder();
    draw(ui.Canvas(rec));
    final p = rec.endRecording();
    final sw = Stopwatch()..start();
    final img = await p.toImage(800, 1400);
    sw.stop();
    img.dispose();
    p.dispose();
    return sw.elapsedMicroseconds;
  }

  testWidgets('46k puntos: grabar y rasterizar, antes contra mallas', (tester) async {
    await tester.runAsync(() async {
      final ss = sheet();
      final pts = ss.fold<int>(0, (a, s) => a + s.n);
      void legacy(ui.Canvas c) {
        for (final s in ss) {
          paintStrokeLegacy(c, s);
        }
      }

      legacy(ui.Canvas(ui.PictureRecorder())); // calentar el JIT
      final oldRec = recordUs(legacy), oldRaster = await rasterUs(legacy);
      final coldRec = recordUs((c) => paintStrokes(c, ss)); // arma mallas y lotes
      final warmRec = recordUs((c) => paintStrokes(c, ss));
      final warmRaster = await rasterUs((c) => paintStrokes(c, ss));
      final bytes = ss.fold<int>(0, (a, s) => a + s.mesh!.bytes);
      final t0 = Stopwatch()..start();
      for (final s in ss) {
        s.mesh = null;
        s.ensureMesh();
      }
      t0.stop();
      // ignore: avoid_print
      print('puntos: $pts, malla: ${(bytes / 1024 / 1024).toStringAsFixed(2)} MB (${(bytes / pts).toStringAsFixed(1)} B/punto)\n'
          'viejo   grabar ${oldRec / 1000} ms, rasterizar ${oldRaster / 1000} ms\n'
          'mallas  grabar (frío, arma todo) ${coldRec / 1000} ms, grabar (tibio) ${warmRec / 1000} ms, rasterizar ${warmRaster / 1000} ms\n'
          'armar las mallas de 46k puntos: ${t0.elapsedMilliseconds} ms');
      expect(warmRec, lessThan(oldRec));
      expect(bytes / pts, lessThan(40));
    });
  });

  testWidgets('costo del borde difuminado: vértices y tiempo de armado, con y sin borde', (tester) async {
    await tester.runAsync(() async {
      final ss = sheet();
      final prev = meshFeather;
      addTearDown(() => meshFeather = prev);
      (int, int, int) armar(double f) {
        for (final s in ss) {
          buildStrokeMesh(s, feather: f); // calentar
        }
        final sw = Stopwatch()..start();
        var v = 0, b = 0;
        for (final s in ss) {
          final m = buildStrokeMesh(s, feather: f)!;
          v += m.vertexCount;
          b += m.bytes;
        }
        sw.stop();
        return (v, b, sw.elapsedMilliseconds);
      }

      final (v0, b0, t0) = armar(0);
      final (v1, b1, t1) = armar(featherForPxPerUnit(1.5));
      // ignore: avoid_print
      print('armado de 46k puntos: sin borde $v0 vértices, ${(b0 / 1024 / 1024).toStringAsFixed(2)} MB, $t0 ms; '
          'con borde $v1 vértices, ${(b1 / 1024 / 1024).toStringAsFixed(2)} MB, $t1 ms');
      // y rasterizar con borde (lotes ya armados)
      for (final s in ss) {
        s.mesh = null;
      }
      meshFeather = featherForPxPerUnit(1.5);
      paintStrokes(ui.Canvas(ui.PictureRecorder()), ss);
      final conBorde = await rasterUs((c) => paintStrokes(c, ss));
      // ignore: avoid_print
      print('rasterizar con borde: ${conBorde / 1000} ms');
      expect(v1, greaterThan(v0));
    });
  });
}
