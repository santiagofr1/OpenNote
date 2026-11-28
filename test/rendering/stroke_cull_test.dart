import 'dart:ui' as ui;

import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/rendering/stroke_painter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Trazo corto de lapicera en la columna [i] (x = i * 100).
Stroke at(int i, {String k = 'pen'}) =>
    Stroke('s$i', k, '#000000', 4, [i * 100.0, 10, .5, i * 100.0 + 40, 20, .5, i * 100.0 + 80, 10, .5]);

void paint(List<Stroke> l, {ui.Rect? cull}) {
  final c = ui.Canvas(ui.PictureRecorder());
  paintStrokes(c, l, cull: cull);
}

void main() {
  final saved = meshFeather;
  tearDown(() => meshFeather = saved);

  test('los trazos fuera del recorte no arman su malla', () {
    final l = [for (var i = 0; i < 400; i++) at(i)];
    // 400 trazos x ~38 vértices: varios lotes; el recorte toca solo los primeros
    paint(l, cull: const ui.Rect.fromLTWH(0, 0, 500, 50));
    expect(l.first.mesh, isNotNull);
    expect(l.last.mesh, isNull);
    expect(l.where((s) => s.mesh == null).length, greaterThan(100));
    // solos (con capa) también
    final solo = [at(0, k: 'hl'), at(50, k: 'hl')];
    paint(solo, cull: const ui.Rect.fromLTWH(0, 0, 500, 50));
    expect(solo[0].mesh, isNotNull);
    expect(solo[1].mesh, isNull);
  });

  test('los lotes son los mismos con cualquier recorte (se reusa el caché)', () {
    final l = [for (var i = 0; i < 400; i++) at(i)];
    paint(l, cull: const ui.Rect.fromLTWH(0, 0, 500, 50));
    // todos los lotes que dibujó el primer recorte quedan en el primer trazo de cada grupo
    final firsts = <int, Object?>{for (var i = 0; i < l.length; i++) if (l[i].batchCache != null) i: l[i].batchCache};
    expect(firsts, isNotEmpty);
    paint(l, cull: const ui.Rect.fromLTWH(0, 0, 100000, 50)); // ahora todos
    for (final e in firsts.entries) {
      expect(identical(l[e.key].batchCache, e.value), isTrue, reason: 'el lote de ${e.key} se rehízo');
    }
    // y sin recorte tampoco cambian
    paint(l);
    for (final e in firsts.entries) {
      expect(identical(l[e.key].batchCache, e.value), isTrue);
    }
    // cada trazo con lote es el primero de su grupo: los grupos no se solapan
    final starts = [for (var i = 0; i < l.length; i++) if (l[i].batchCache != null) i];
    expect(starts.length, greaterThan(1));
  });

  test('meshIsColored coincide con la malla armada en cada punta', () {
    for (final f in [0.0, .5]) {
      meshFeather = f;
      for (final k in ['pen', 'fountain', 'pencil', 'fine', 'calli', 'hl', kCoverTip, 'paint-stars', 'paint-hearts']) {
        for (final n in [1, 2, 30]) {
          final s = Stroke('a', k, '#123456', 4, [for (var i = 0; i < n; i++) ...[i * 3.0, 10 + (i % 3), .5]]);
          expect(meshIsColored(s), buildStrokeMesh(s)!.colored, reason: '$k n=$n feather=$f');
        }
      }
    }
  });

  test('la estimación de vértices no se queda corta por mucho', () {
    for (final f in [0.0, .5]) {
      meshFeather = f;
      for (final k in ['pen', 'fountain', 'pencil', 'fine', 'calli', 'hl', kCoverTip, 'paint-stars', 'paint-hearts']) {
        for (final n in [1, 2, 10, 300]) {
          final s = Stroke('a', k, '#123456', 4, [for (var i = 0; i < n; i++) ...[i * 3.0, 10 + (i % 3), .5]]);
          expect(buildStrokeMesh(s)!.vertexCount, lessThanOrEqualTo(estimateMeshVertices(s) * 3 ~/ 2 + 20), reason: '$k n=$n');
        }
      }
    }
  });
}
