import 'dart:math';
import 'dart:ui' as ui;

import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/rendering/stroke_painter.dart';
import 'package:flutter_test/flutter_test.dart';

/// El borde difuminado (en píxeles de pantalla) tiene que dar niveles de alfa intermedios en el costado del trazo:
/// sin él, `drawVertices` pinta todo o nada y un trazo de 2-3 px se ve dentado.
void main() {
  const size = 120;
  final prev = meshFeather;
  tearDown(() => meshFeather = prev);

  // diagonal fina: w = 1.8 unidades a escala 1.6 mide ~2.9 px
  const scale = 1.6;
  Stroke diagonal() => Stroke('d', 'pen', '#000000', 1.8, [
        for (var i = 0; i <= 20; i++) ...[5 + i * 3.0, 8 + i * 2.0, .5],
      ]);

  Future<List<int>> alphaRow(double feather) async {
    meshFeather = feather;
    final s = diagonal();
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    c.scale(scale);
    paintStroke(c, s);
    final img = await rec.endRecording().toImage(size, size);
    final d = (await img.toByteData())!;
    img.dispose();
    const y = 40; // una fila que cruza el trazo en diagonal
    return [for (var x = 0; x < size; x++) d.getUint8((y * size + x) * 4 + 3)];
  }

  int intermedios(List<int> a) => a.where((v) => v > 10 && v < 245).length;

  /// Cantidad de píxeles con alfa intermedio de toda la imagen y su cobertura total.
  Future<(int, double)> medir(Stroke s, double feather) async {
    meshFeather = feather;
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    c.scale(scale);
    paintStroke(c, s);
    final img = await rec.endRecording().toImage(size, size);
    final d = (await img.toByteData())!;
    img.dispose();
    var mid = 0;
    double cov = 0;
    for (var i = 3; i < d.lengthInBytes; i += 4) {
      final a = d.getUint8(i);
      if (a > 10 && a < 245) mid++;
      cov += a / 255;
    }
    return (mid, cov);
  }

  testWidgets('con borde hay más niveles de alfa intermedios que sin borde (todas las puntas)', (tester) async {
    await tester.runAsync(() async {
      final tips = <String, double>{'pen': 1.8, 'fountain': 1.8, 'fine': 1.8, 'hl': 6, 'pencil': 2, 'calli': 2, 'paint-star': 4};
      for (final e in tips.entries) {
        final s = Stroke('d', e.key, '#000000', e.value, [for (var i = 0; i <= 20; i++) ...[5 + i * 3.0, 8 + i * 2.0, .5]]);
        final (sinMid, sinCov) = await medir(s, 0);
        s.releaseMesh();
        final (conMid, conCov) = await medir(s, featherForPxPerUnit(scale));
        // ignore: avoid_print
        print('${e.key}: píxeles intermedios sin borde $sinMid, con borde $conMid (cobertura $sinCov -> $conCov)');
        expect(conMid, greaterThan(sinMid), reason: e.key);
        expect((conCov - sinCov).abs() / max(sinCov, 1), lessThan(.3), reason: '${e.key}: no engorda ni adelgaza de más');
      }
    });
  });

  testWidgets('con borde hay más niveles de alfa intermedios que sin borde', (tester) async {
    await tester.runAsync(() async {
      final sin = await alphaRow(0);
      final con = await alphaRow(featherForPxPerUnit(scale));
      // ignore: avoid_print
      print('niveles de alfa intermedios en la fila: sin borde ${intermedios(sin)}, con borde ${intermedios(con)}');
      expect(sin.any((v) => v > 245), isTrue, reason: 'el trazo se dibujó');
      expect(con.any((v) => v > 245), isTrue, reason: 'y con borde conserva un núcleo opaco');
      expect(intermedios(con), greaterThan(intermedios(sin)));
      expect(intermedios(con), greaterThanOrEqualTo(2));
      // el trazo no engorda ni adelgaza de más (la cobertura total es parecida)
      num cover(List<int> a) => a.fold<num>(0, (t, v) => t + v) / 255;
      expect((cover(con) - cover(sin)).abs() / max(cover(sin), 1), lessThan(.25));
    });
  });
}
