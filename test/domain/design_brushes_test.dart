import 'dart:math';

import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

Stroke wave(String k, {double w = 8, int n = 60}) {
  final pts = <double>[];
  for (var i = 0; i < n; i++) {
    final t = i / (n - 1);
    pts.addAll([30 + t * 330, 200 + sin(t * pi * 3) * 60, .6]);
  }
  return Stroke('t', k, '#b91c1c', w, pts);
}

void main() {
  final ids = [for (final (id, _) in designTips) id];

  test('la lista de diseños coincide con las puntas que conoce la malla', () {
    expect(ids.toSet(), designTipIds);
    expect(ids.every(isDesignTip), isTrue);
    expect(isDesignTip('pen'), isFalse);
  });

  for (final k in ids) {
    group(k, () {
      test('genera una malla no vacía con índices válidos', () {
        final m = buildStrokeMesh(wave(k))!;
        expect(m.vertexCount, greaterThan(0));
        for (final p in m.parts) {
          expect(p.idx, isNotEmpty);
          expect(p.idx.length % 3, 0);
          expect(p.idx.reduce(max), lessThan(p.vertexCount));
          expect(p.pos.every((v) => v.isFinite), isTrue);
        }
      });

      test('es determinística: dos builds dan los mismos vértices', () {
        final a = buildStrokeMesh(wave(k))!, b = buildStrokeMesh(wave(k))!;
        expect(a.parts.length, b.parts.length);
        for (var i = 0; i < a.parts.length; i++) {
          expect(a.parts[i].pos, b.parts[i].pos);
          expect(a.parts[i].idx, b.parts[i].idx);
        }
      });

      test('bounds contiene todos los vértices (también con grosor chico y grande)', () {
        for (final w in [.6, 3.0, 8.0, 16.0]) {
          final s = wave(k, w: w);
          final r = s.bounds.inflate(.01);
          for (final part in buildStrokeMesh(s)!.parts) {
            for (var i = 0; i < part.pos.length; i += 2) {
              expect(r.contains(Offset(part.pos[i], part.pos[i + 1])), isTrue, reason: '$k w=$w vértice $i');
            }
          }
        }
      });

      test('un punto solo deja una forma, dentro de bounds', () {
        final s = Stroke('p', k, '#000000', 8, [100, 100, .5]);
        final m = buildStrokeMesh(s)!;
        expect(m.vertexCount, greaterThan(2));
        expect(m.parts.single.idx, isNotEmpty);
        final r = s.bounds.inflate(.01);
        for (var i = 0; i < m.parts.single.pos.length; i += 2) {
          expect(r.contains(Offset(m.parts.single.pos[i], m.parts.single.pos[i + 1])), isTrue);
        }
      });

      test('la primera estampa sale en el inicio del trazo', () {
        final p = buildStrokeMesh(wave(k))!.parts.first.pos;
        final near = [for (var i = 0; i < p.length; i += 2) (Offset(p[i], p[i + 1]) - const Offset(30, 200)).distance];
        expect(near.reduce(min), lessThan(8 * kDesignRadius * 1.5));
      });

      test('un trazo larguísimo no pasa el tope de vértices', () {
        final pts = <double>[];
        for (var i = 0; i < 40000; i++) {
          pts.addAll([i * 1.5, 100 + (i.isEven ? 0 : 6), .5]);
        }
        final m = buildStrokeMesh(Stroke('l', k, '#000000', 16, pts))!;
        expect(m.parts.length, greaterThan(1));
        for (final p in m.parts) {
          expect(p.vertexCount, lessThan(StrokeMesh.maxVertices));
          expect(p.idx.reduce(max), lessThan(p.vertexCount));
        }
      });

      test('dos puntos muy lejanos (un tramo larguísimo) tampoco pasan el tope', () {
        final m = buildStrokeMesh(Stroke('l', k, '#000000', 16, [0, 0, .5, 500000, 0, .5]))!;
        for (final p in m.parts) {
          expect(p.vertexCount, lessThan(StrokeMesh.maxVertices));
          expect(p.idx.reduce(max), lessThan(p.vertexCount));
        }
      });
    });
  }

  test('una punta desconocida (trazo de una versión nueva) se arma como bolígrafo', () {
    final m = buildStrokeMesh(wave('desconocida'))!;
    expect(m.vertexCount, buildStrokeMesh(wave('pen'))!.vertexCount);
  });

  test('la goma toca la forma aunque no esté sobre la línea central', () {
    final p = Offset(100 + 8 * kDesignRadius * .8, 100);
    expect(Stroke('g', 'stars', '#000000', 8, [100, 100, .5]).hitBy(p, 1), isTrue);
    expect(Stroke('g', 'pen', '#000000', 8, [100, 100, .5]).hitBy(p, 1), isFalse);
  });
}
