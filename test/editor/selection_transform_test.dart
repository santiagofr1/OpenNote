import 'dart:math';
import 'dart:ui';

import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/selection.dart';
import 'package:flutter_test/flutter_test.dart';

/// Rotar y escalar lo seleccionado: la transformación, el imán del ángulo y qué le pasa a trazos, elementos y textos.
void main() {
  Stroke line(String id, double x0, double y0, double x1, double y1, {double w = 4, String k = 'pen'}) =>
      Stroke(id, k, '#000000', w, [x0, y0, .5, (x0 + x1) / 2, (y0 + y1) / 2, .6, x1, y1, .7]);

  NotebookDoc page() {
    final d = NotebookDoc(Notebook.create('t'));
    d.strokes['a'] = line('a', 100, 100, 200, 100);
    d.items['i'] = Item('i', 'sticky', 300, 100, 100, 80);
    d.texts['t'] = TextBlock('t', 100, 240, 300, 'hola');
    return d;
  }

  Matcher near(Offset o) => predicate<Offset>((p) => (p - o).distance < 1e-6, 'cerca de $o');

  group('Xform', () {
    test('mover es solo la traslación y es exacta', () {
      const x = Xform.move(Offset(.1, .2));
      expect(x.isMove, isTrue);
      expect(x.apply(const Offset(1.3, 2.7)), const Offset(1.3, 2.7) + const Offset(.1, .2));
    });

    test('escala 2 desde una esquina: la esquina no se mueve', () {
      const x = Xform(pivot: Offset(100, 100), scale: 2);
      expect(x.apply(const Offset(100, 100)), const Offset(100, 100));
      expect(x.apply(const Offset(150, 120)), const Offset(200, 140));
    });

    test('rotar 90° alrededor del centro', () {
      const x = Xform(pivot: Offset(50, 50), angle: pi / 2);
      expect(x.apply(const Offset(100, 50)), near(const Offset(50, 100)));
      expect(x.apply(const Offset(50, 50)), near(const Offset(50, 50)));
    });

    test('kx y ky estiran cada eje antes de escalar y girar', () {
      const x = Xform(pivot: Offset(100, 100), kx: 2);
      expect(x.isMove, isFalse);
      expect(x.apply(const Offset(150, 120)), const Offset(200, 120));
      expect(x.applyRect(const Rect.fromLTWH(100, 100, 50, 20)), const Rect.fromLTWH(100, 100, 100, 20));
      const y = Xform(pivot: Offset(100, 100), ky: 3, scale: 2);
      expect(y.apply(const Offset(150, 120)), const Offset(200, 220));
      expect(const Xform(kx: 1, ky: 1).isMove, isTrue);
    });

    test('imán: a menos de 4° de 0, 90, 180 y 270 queda justo', () {
      double deg(double a) => a * pi / 180;
      expect(snapAngle(deg(3)), 0);
      expect(snapAngle(deg(-3.9)), 0);
      expect(snapAngle(deg(87)), pi / 2);
      expect(snapAngle(deg(93.5)), pi / 2);
      expect(snapAngle(deg(178)), pi);
      expect(snapAngle(deg(-91)), -pi / 2);
      expect(snapAngle(deg(5)), deg(5), reason: 'lejos del imán: queda libre');
      expect(snapAngle(deg(40)), deg(40));
    });
  });

  group('Stroke.transformed', () {
    test('escala 2 desde una esquina: puntos y grosor', () {
      final s = line('a', 100, 100, 200, 100, w: 4);
      final m = s.transformed(const Xform(pivot: Offset(100, 100), scale: 2));
      expect(m.pts, [100, 100, .5, 200, 100, .6, 300, 100, .7]);
      expect(m.w, 8);
      expect(m.k, s.k);
      expect(m.id, s.id);
      expect(m.bounds.width, closeTo(s.bounds.width * 2, 1e-9), reason: 'el rectángulo se recalcula (no hereda el viejo)');
      expect(s.w, 4, reason: 'el original no se toca');
    });

    test('rotar 90° alrededor del centro: los puntos giran y el grosor queda', () {
      final s = line('a', 100, 100, 200, 100, w: 4);
      final m = s.transformed(const Xform(pivot: Offset(150, 100), angle: pi / 2));
      expect(Offset(m.pts[0], m.pts[1]), near(const Offset(150, 50)));
      expect(Offset(m.pts[6], m.pts[7]), near(const Offset(150, 150)));
      expect(m.w, 4);
      expect(m.pts[2], .5, reason: 'la presión no cambia');
    });

    test('estirar en x: duplica el ancho, no engorda el trazo', () {
      final s = line('a', 100, 100, 200, 130, w: 4);
      final m = s.transformed(const Xform(pivot: Offset(100, 100), kx: 2));
      expect(m.pts, [100, 100, .5, 200, 115, .6, 300, 130, .7]);
      expect(m.w, 4);
    });

    test('la copia no hereda la malla y conserva el z', () {
      final s = line('a', 0, 0, 10, 0)..z = 5;
      s.ensureMesh();
      final m = s.transformed(const Xform.move(Offset(7, 3)));
      expect(m.z, 5);
      expect(m.mesh, isNull, reason: 'la malla se arma de nuevo con los puntos nuevos');
      expect(m.pts.take(2), [7, 3]);
    });
  });

  group('arrastre de manijas en Selection', () {
    test('escalar desde la esquina de abajo-derecha: uniforme, ancla arriba-izquierda', () {
      final d = page(), sel = Selection()..replace(strokes: ['a']);
      final r = sel.contentRect(d)!;
      sel.startHandle(d, Handle.br, r.bottomRight);
      expect(sel.moving, isTrue);
      // el lápiz se va al doble de la diagonal: escala 2
      sel.dragTo(r.topLeft + (r.bottomRight - r.topLeft) * 2);
      expect(sel.drag!.xf.pivot, r.topLeft);
      expect(sel.drag!.xf.scale, closeTo(2, 1e-9));
      expect(sel.drag!.xf.angle, 0);
    });

    test('la escala no baja del mínimo (no queda de 0)', () {
      final d = page(), sel = Selection()..replace(strokes: ['a']);
      final r = sel.contentRect(d)!;
      sel.startHandle(d, Handle.br, r.bottomRight);
      sel.dragTo(r.topLeft); // justo sobre el ancla
      expect(sel.drag!.xf.scale, greaterThan(0));
      sel.dragTo(r.topLeft - const Offset(50, 50)); // del otro lado
      expect(sel.drag!.xf.scale, sel.drag!.minScale);
    });

    test('un elemento no baja de 60 de ancho ni de alto (las notas)', () {
      final d = page(), sel = Selection()..replace(items: ['i']);
      final r = sel.contentRect(d)!;
      sel.startHandle(d, Handle.br, r.bottomRight);
      sel.dragTo(r.topLeft);
      sel.applyToBlocks(d);
      expect(d.items['i']!.w, closeTo(100 * 60 / 80, 1e-9), reason: 'el alto de 80 llega a 60 y el ancho va con él');
      expect(d.items['i']!.h, closeTo(60, 1e-9));
    });

    test('rotar: relativo a donde se agarró, con imán', () {
      final d = page(), sel = Selection()..replace(strokes: ['a']);
      final c = sel.contentRect(d)!.center;
      sel.startHandle(d, Handle.rotate, c + const Offset(0, -100));
      sel.dragTo(c + const Offset(100, 0)); // de arriba a la derecha: 90° en sentido horario
      expect(sel.drag!.xf.pivot, c);
      expect(sel.drag!.xf.angle, closeTo(pi / 2, 1e-12));
      sel.dragTo(c + Offset(100 * sin(30 * pi / 180), -100 * cos(30 * pi / 180)));
      expect(sel.drag!.xf.angle, closeTo(30 * pi / 180, 1e-9), reason: 'ángulo libre lejos del imán');
      sel.dragTo(c + Offset(100 * sin(2 * pi / 180), -100 * cos(2 * pi / 180)));
      expect(sel.drag!.xf.angle, 0, reason: 'a 2° se pega a 0');
    });

    test('elementos: al escalar se escala su rectángulo desde el ancla; al rotar solo se mueve el centro', () {
      final d = page(), sel = Selection()..replace(items: ['i']);
      final it = d.items['i']!;
      final r0 = it.rect;
      sel.startHandle(d, Handle.br, r0.bottomRight);
      sel.drag!.xf = Xform(pivot: r0.topLeft, scale: 2);
      sel.applyToBlocks(d);
      expect(it.rect, Rect.fromLTWH(300, 100, 200, 160));
      sel.drag = null;

      sel.startHandle(d, Handle.rotate, const Offset(100, 100));
      const rot = Xform(pivot: Offset(100, 100), angle: pi / 2);
      sel.drag!.xf = rot;
      sel.applyToBlocks(d);
      // arranca de lo que ya quedó (200 x 160) y el centro gira
      expect(it.rect.center, near(rot.apply(const Offset(300 + 100, 100 + 80))));
      expect(it.w, 200, reason: 'rotar no cambia el tamaño');
      expect(it.h, 160);
    });

    test('textos: al escalar multiplican su escala (el ancho w no cambia) y la identidad los deja exactos', () {
      final d = page(), sel = Selection()..replace(texts: ['t']);
      final t = d.texts['t']!;
      final r0 = sel.contentRect(d)!;
      sel.startHandle(d, Handle.br, r0.bottomRight);
      sel.drag!.xf = Xform(pivot: r0.topLeft - const Offset(50, 50), scale: 2);
      sel.applyToBlocks(d);
      expect(t.w, 300);
      expect(t.body.plainText, 'hola');
      expect(Offset(t.x, t.y), isNot(Offset(r0.left, r0.top)));
      expect(t.scale, closeTo(2, 1e-9));
      final c = Offset(t.x, t.y) + (r0.center - r0.topLeft) * 2; // su centro fue a donde lleva la transformación
      expect(c, near(sel.drag!.xf.apply(r0.center)));
      sel.drag!.xf = const Xform();
      sel.applyToBlocks(d);
      expect(Offset(t.x, t.y), r0.topLeft);
      expect(t.scale, 1);
    });

    test('contentRect y bounds se calculan sobre lo original mientras se arrastra', () {
      final d = page(), sel = Selection()..replace(strokes: ['a'], items: ['i'], texts: ['t']);
      final before = sel.bounds(d);
      final r = sel.contentRect(d)!;
      sel.startHandle(d, Handle.tl, r.topLeft);
      sel.drag!.xf = Xform(pivot: r.bottomRight, scale: 3);
      sel.applyToBlocks(d);
      expect(sel.bounds(d), before);
      expect(sel.contentRect(d), r);
    });

    test('estirar con el lado derecho: solo kx, el lado izquierdo queda fijo', () {
      final d = page(), sel = Selection()..replace(strokes: ['a']);
      final r = sel.contentRect(d)!;
      sel.startHandle(d, Handle.right, r.centerRight);
      expect(sel.drag!.pivot, r.centerLeft);
      sel.dragTo(r.centerLeft + (r.centerRight - r.centerLeft) * 2);
      expect(sel.drag!.xf.kx, closeTo(2, 1e-9));
      expect(sel.drag!.xf.ky, 1);
      expect(sel.drag!.xf.scale, 1);
    });

    test('estirar con el lado izquierdo respeta el mínimo', () {
      final d = page(), sel = Selection()..replace(items: ['i']);
      final r = sel.contentRect(d)!;
      sel.startHandle(d, Handle.left, r.centerLeft);
      sel.dragTo(r.centerRight + const Offset(50, 0)); // pasa al otro lado del ancla
      expect(sel.drag!.xf.kx, closeTo(60 / 100, 1e-9));
    });

    test('estirar hacia abajo: solo ky', () {
      final d = page(), sel = Selection()..replace(items: ['i']);
      final r = sel.contentRect(d)!;
      sel.startHandle(d, Handle.bottom, r.bottomCenter);
      sel.dragTo(r.bottomCenter + Offset(0, r.height));
      expect(sel.drag!.xf.ky, closeTo(2, 1e-9));
      expect(sel.drag!.xf.kx, 1);
    });

    test('estirar un elemento: el ancho se duplica, el alto no y el lado opuesto queda fijo', () {
      final d = page(), sel = Selection()..replace(items: ['i']);
      final r = sel.contentRect(d)!;
      sel.startHandle(d, Handle.right, r.centerRight);
      sel.dragTo(r.centerRight + Offset(r.width, 0));
      sel.applyToBlocks(d);
      final it = d.items['i']!;
      expect(it.w, closeTo(200, 1e-9));
      expect(it.h, 80);
      expect(it.x, closeTo(300, 1e-9));
      expect(it.y, closeTo(100, 1e-9));
    });

    test('estirar un texto: el ancho se duplica y la escala no cambia', () {
      final d = page(), sel = Selection()..replace(texts: ['t']);
      final r = sel.contentRect(d)!;
      sel.startHandle(d, Handle.right, r.centerRight);
      sel.dragTo(r.centerRight + Offset(r.width, 0)); // kx = 2
      sel.applyToBlocks(d);
      final t = d.texts['t']!;
      expect(sel.drag!.xf.kx, closeTo(2, 1e-9));
      expect(t.w, closeTo(r.width * 2, 1e-6), reason: 'parte del ancho que se ve (el texto corto no llena la caja)');
      expect(t.scale, 1);
      expect(t.x, closeTo(100, 1e-6));
      expect(sel.contentRect(d), r, reason: 'el original se reconstruye con su ancho');
    });
  });
}
