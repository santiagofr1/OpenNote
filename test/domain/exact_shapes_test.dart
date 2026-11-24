import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:apuntes/data/sheet_codec.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';

List<Offset> pts(List<double> p) => [for (var i = 0; i < p.length; i += 3) Offset(p[i], p[i + 1])];

void main() {
  group('snapToGrid', () {
    final u = unitsPerMm('a4');

    test('cuadriculado de 5 mm: va a la intersección más cercana', () {
      final xs = gridXs(5), ys = gridYs(5);
      final q = snapToGrid(Offset(xs[2] + 1.2, ys[3] - 1.4), 'grid', 5, 'a4');
      expect(q.dx, closeTo(xs[2], 1e-9));
      expect(q.dy, closeTo(ys[3], 1e-9));
      // el resultado cae en una línea (múltiplo de 5 mm en x)
      expect(unitsToMm(q.dx) % 5, anyOf(closeTo(0, 1e-6), closeTo(5, 1e-6)));
    });

    test('puntos y ejes usan el mismo paso (7 mm incluido)', () {
      for (final bg in ['dots', 'axes']) {
        final xs = gridXs(7), ys = gridYs(7);
        final q = snapToGrid(Offset(xs[1] + 2, ys[1] + 2), bg, 7, 'a4');
        expect(q, Offset(xs[1], ys[1]));
      }
    });

    test('milimetrado: múltiplos de 5 mm desde el origen', () {
      final o = gridOriginMm('mm', 10) * u;
      final q = snapToGrid(Offset(5 * u * 3 + 1, o + 5 * u * 4 + 2), 'mm', 5, 'a4');
      expect(q.dx, closeTo(15 * u, 1e-9));
      expect(q.dy, closeTo(o + 20 * u, 1e-9));
    });

    test('fondo sin cuadrícula: el mismo punto', () {
      for (final bg in ['blank', 'lined', 'cornell']) {
        expect(snapToGrid(const Offset(123.4, 567.8), bg, 8, 'a4'), const Offset(123.4, 567.8));
      }
    });
  });

  group('imán de 15 grados', () {
    test('a menos de 5 grados de un múltiplo se imanta, conservando el largo', () {
      const a = Offset(100, 100);
      final b = a + Offset(cos(32 * pi / 180), -sin(32 * pi / 180)) * 200; // 32 grados: cerca de 30
      final q = snapAngle15(a, b);
      expect((q - a).distance, closeTo(200, 1e-9));
      expect(atan2(-(q - a).dy, (q - a).dx) * 180 / pi, closeTo(30, 1e-9));
    });

    test('a más de 5 grados no se toca', () {
      const a = Offset.zero;
      final b = Offset(cos(38 * pi / 180), sin(38 * pi / 180)) * 100;
      expect(snapAngle15(a, b), b);
    });
  });

  group('shapeMeasure', () {
    final u = unitsPerMm('a4');
    test('recta y flecha: largo y ángulo antihorario', () {
      expect(shapeMeasure('line', Offset.zero, Offset(40 * u, 0), u), '40,0 mm · 0°');
      expect(shapeMeasure('arrow', Offset.zero, Offset(0, -30 * u), u), '30,0 mm · 90°');
      expect(shapeMeasure('line', Offset.zero, Offset(0, 30 * u), u), '30,0 mm · 270°');
      final b = Offset(cos(30 * pi / 180), -sin(30 * pi / 180)) * 52.3 * u;
      expect(shapeMeasure('line', Offset.zero, b, u), '52,3 mm · 30°');
    });
    test('rectángulo, elipse, círculo y triángulo', () {
      final b = Offset(40 * u, 25.5 * u);
      expect(shapeMeasure('rect', Offset.zero, b, u), '40,0 × 25,5 mm');
      expect(shapeMeasure('ellipse', Offset.zero, b, u), '40,0 × 25,5 mm');
      expect(shapeMeasure('circle', Offset.zero, Offset(18.2 * u, 0), u), 'r 18,2 mm');
      expect(shapeMeasure('triangle', Offset.zero, b, u), 'base 40,0 · alto 25,5 mm');
    });
  });

  group('exactShapePoints', () {
    const a = Offset(100, 100), b = Offset(300, 220);

    test('recta: de A a B', () {
      final p = pts(exactShapePoints('line', a, b));
      expect(p.first, a);
      expect(p.last, b);
    });

    test('flecha: A, B, punta, B, punta (largo min(18, .3 |AB|), a 28 grados)', () {
      final p = pts(exactShapePoints('arrow', a, b));
      expect(p.first, a);
      expect(p.last.dx, isNot(b.dx));
      // los vértices son los puntos donde cambia la dirección
      final verts = <Offset>[p.first];
      for (var i = 1; i < p.length - 1; i++) {
        final d1 = p[i] - p[i - 1], d2 = p[i + 1] - p[i];
        if ((d1.dx * d2.dy - d1.dy * d2.dx).abs() > 1e-6 * d1.distance * d2.distance ||
            d1.dx * d2.dx + d1.dy * d2.dy < 0) {
          verts.add(p[i]); // giro, o marcha atrás por el mismo camino
        }
      }
      verts.add(p.last);
      expect(verts.length, 5);
      expect(verts[1], b);
      expect(verts[3], b);
      expect((verts[2] - b).distance, closeTo(18, 1e-6));
      expect((verts[4] - b).distance, closeTo(18, 1e-6));
      final back = (a - b).direction;
      expect(((verts[2] - b).direction - back).abs(), closeTo(28 * pi / 180, 1e-6));
      expect(((verts[4] - b).direction - back).abs(), closeTo(28 * pi / 180, 1e-6));
    });

    test('flecha corta: la punta mide .3 del largo', () {
      final p = pts(exactShapePoints('arrow', Offset.zero, const Offset(30, 0)));
      final tail = p.sublist(p.indexOf(const Offset(30, 0)) + 1);
      final far = tail.map((q) => (q - const Offset(30, 0)).distance).reduce(max);
      expect(far, closeTo(9, 1e-6));
    });

    test('rectángulo: pasa por sus 4 esquinas y cierra', () {
      final p = pts(exactShapePoints('rect', b, a)); // al revés: da igual
      for (final c in [const Offset(100, 100), const Offset(300, 100), const Offset(300, 220), const Offset(100, 220)]) {
        expect(p.contains(c), isTrue, reason: '$c');
      }
      expect(p.first, p.last);
    });

    test('círculo: centro A y radio |AB|', () {
      final p = pts(exactShapePoints('circle', a, b));
      final r = (b - a).distance;
      for (final q in p) {
        expect((q - a).distance, closeTo(r, 1e-6));
      }
      expect(p.first, p.last);
    });

    test('elipse inscripta en el rectángulo A-B', () {
      final p = pts(exactShapePoints('ellipse', a, b));
      final r = Rect.fromPoints(a, b);
      expect(p.map((q) => q.dx).reduce(max), closeTo(r.right, .05));
      expect(p.map((q) => q.dx).reduce(min), closeTo(r.left, .05));
      expect(p.map((q) => q.dy).reduce(max), closeTo(r.bottom, .05));
      expect(p.map((q) => q.dy).reduce(min), closeTo(r.top, .05));
    });

    test('triángulo: base abajo y vértice arriba al medio; si B está arriba de A se invierte', () {
      final p = pts(exactShapePoints('triangle', a, b));
      expect(p.first, const Offset(200, 100)); // vértice arriba
      expect(p.contains(const Offset(100, 220)), isTrue);
      expect(p.contains(const Offset(300, 220)), isTrue);
      final inv = pts(exactShapePoints('triangle', b, a));
      expect(inv.first, const Offset(200, 220)); // vértice abajo
      expect(inv.contains(const Offset(100, 100)), isTrue);
      expect(inv.contains(const Offset(300, 100)), isTrue);
    });
  });

  group('manijas', () {
    test('esquina: la opuesta queda fija', () {
      const a = Offset(100, 100), b = Offset(300, 200);
      final (na, nb) = dragShapeHandle('rect', a, b, 0, const Offset(50, 60));
      expect(Rect.fromPoints(na, nb), Rect.fromLTRB(50, 60, 300, 200));
    });

    test('triángulo: arrastrar una esquina de arriba no lo da vuelta', () {
      const a = Offset(100, 100), b = Offset(300, 200);
      final (na, nb) = dragShapeHandle('triangle', a, b, 0, const Offset(50, 60));
      expect(triangleInverted(na, nb), isFalse);
    });

    test('círculo: el centro mueve todo, el borde cambia el radio', () {
      const a = Offset(100, 100), b = Offset(130, 100);
      expect(dragShapeHandle('circle', a, b, 0, const Offset(200, 200)), (const Offset(200, 200), const Offset(230, 200)));
      expect(dragShapeHandle('circle', a, b, 1, const Offset(100, 150)), (a, const Offset(100, 150)));
    });
  });

  group('relleno en el trazo', () {
    test('con y sin relleno: ida y vuelta por JSON y por el archivo de la hoja', () {
      final con = Stroke('a', 'fine', '#000000', 2, [1, 2, .5, 30, 40, .5, 5, 60, .5], 1, null, '#93c5fd');
      final sin = Stroke('b', 'pen', '#000000', 2, [1, 2, .5, 30, 40, .5]);
      expect(jsonEncode(con.toJson()), contains('"f":"#93c5fd"'));
      expect(sin.toJson().containsKey('f'), isFalse);
      expect(Stroke.fromJson(jsonDecode(jsonEncode(con.toJson())) as Map).fill, '#93c5fd');
      expect(Stroke.fromJson(jsonDecode(jsonEncode(sin.toJson())) as Map).fill, isNull);
      final back = decodeSheet(encodeSheet(SheetContent(strokes: [con, sin], texts: [], items: [])));
      expect(back.strokes.firstWhere((s) => s.id == 'a').fill, '#93c5fd');
      expect(back.strokes.firstWhere((s) => s.id == 'b').fill, isNull);
    });

    test('moved y transformed conservan el relleno', () {
      final s = Stroke('a', 'fine', '#000000', 2, [1, 2, .5, 30, 40, .5], 1, null, '#fde68a');
      expect(s.moved(const Offset(5, 5)).fill, '#fde68a');
      expect(s.transformed(const Xform(shift: Offset(1, 1), scale: 2)).fill, '#fde68a');
    });
  });

  test('prefs: las opciones de formas se guardan y se leen', () {
    final t = ToolState()
      ..shapeKind = 'triangle'
      ..shapeFill = true
      ..shapeFillColor = '#fca5a5'
      ..shapeGrid = false;
    final u = ToolState()..load(jsonDecode(jsonEncode(t.toJson())) as Map);
    expect((u.shapeKind, u.shapeFill, u.shapeFillColor, u.shapeGrid), ('triangle', true, '#fca5a5', false));
    expect(ToolState().shapeGrid, isTrue);
  });
}
