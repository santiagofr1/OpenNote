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
}
