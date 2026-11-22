import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:apuntes/data/sheet_codec.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/selection.dart';
import 'package:apuntes/rendering/text_layout.dart';
import 'package:flutter_test/flutter_test.dart';

/// El texto con teclado como una entidad más (issue #12): escala y giro en el modelo, en el JSON, en el hit-test y en la
/// transformación de la selección.
void main() {
  TextBlock block({double s = 1, double a = 0}) => TextBlock('t', 100, 240, 300, 'hola mundo', scale: s, angle: a);

  group('modelo y JSON', () {
    test('sin escala ni giro no se guarda nada nuevo, y los archivos viejos cargan igual', () {
      final j = block().toJson();
      expect(j.containsKey('s'), isFalse);
      expect(j.containsKey('a'), isFalse);
      final t = TextBlock.fromJson({'id': 't', 'x': 1, 'y': 2, 'w': 300, 'text': 'viejo'});
      expect(t.scale, 1);
      expect(t.angle, 0);
      expect(t.transformed, isFalse);
    });

    test('escala y giro van en "s" y "a", se leen y copy los conserva', () {
      final t = block(s: 1.5, a: .3);
      final j = jsonDecode(jsonEncode(t.toJson())) as Map;
      expect(j['s'], 1.5);
      expect(j['a'], .3);
      final back = TextBlock.fromJson(j);
      expect(back.scale, 1.5);
      expect(back.angle, closeTo(.3, 1e-12));
      expect(back.transformed, isTrue);
      final c = t.copy(d: const Offset(5, 5));
      expect(c.scale, 1.5);
      expect(c.angle, .3);
      expect(c.x, 105);
    });

    test('pasa por el formato de hoja (.sheet y por lo tanto .opennote)', () {
      final content = SheetContent(texts: [block(s: 2, a: pi / 2)]);
      final back = decodeSheet(encodeSheet(content));
      expect(back.texts.single.scale, 2);
      expect(back.texts.single.angle, closeTo(pi / 2, 1e-9));
    });

    test('la huella de la hoja cambia si cambia el giro', () {
      final a = sheetDigest(SheetContent(texts: [block()])), b = sheetDigest(SheetContent(texts: [block(a: .5)]));
      expect(a, isNot(b));
    });
  });

  group('rectángulo y hit-test', () {
    test('la escala agranda el rectángulo desde la esquina de arriba a la izquierda', () {
      final r1 = textRect(block()), r2 = textRect(block(s: 2));
      expect(r2.topLeft, r1.topLeft);
      expect(r2.width, closeTo(r1.width * 2, 1e-9));
      expect(r2.height, closeTo(r1.height * 2, 1e-9));
    });

    test('girado 90°: el rectángulo que lo envuelve es el de lado cambiado y alrededor del mismo centro', () {
      final r = textRect(block()), b = textBounds(block(a: pi / 2));
      expect(b.center.dx, closeTo(r.center.dx, 1e-6));
      expect(b.center.dy, closeTo(r.center.dy, 1e-6));
      expect(b.width, closeTo(r.height, 1e-6));
      expect(b.height, closeTo(r.width, 1e-6));
    });

    test('hit-test con el polígono girado: toca adentro girado y no en las esquinas vacías del bounding box', () {
      final t = block(a: pi / 4);
      final r = textRect(t), c = r.center;
      expect(textHit(t, c, 0), isTrue);
      // un punto sobre el eje del texto (lejos del centro) sigue dentro
      expect(textHit(t, c + Offset.fromDirection(pi / 4, r.width / 2 - 5), 0), isTrue);
      // el mismo punto sin girar (a la derecha del centro) ya está afuera del texto girado si es más alto que el rectángulo
      expect(textHit(t, c + Offset(0, r.width / 2 - 5), 0), isFalse);
      // una esquina del bounding box no es del texto
      final bb = textBounds(t);
      expect(textHit(t, bb.topLeft + const Offset(2, 2), 0), isFalse);
    });

    test('Selection.hitStack y selectIn (ventana y captura) usan el rectángulo girado', () {
      final doc = NotebookDoc(Notebook.create('x'));
      doc.texts['t'] = block(a: pi / 4);
      final sel = Selection();
      final c = textRect(doc.texts['t']!).center;
      expect(sel.hitStack(doc, c, 1).map((e) => e.id), ['t']);
      final bb = textBounds(doc.texts['t']!);
      expect(sel.hitStack(doc, bb.topLeft + const Offset(2, 2), 1), isEmpty);
      sel.selectIn(doc, bb.inflate(10));
      expect(sel.texts, {'t'}, reason: 'ventana: el bounding box entra');
      sel.selectIn(doc, Rect.fromCenter(center: c, width: 10, height: 10), capture: true);
      expect(sel.texts, {'t'});
      sel.selectIn(doc, Rect.fromLTWH(bb.left - 30, bb.top - 30, 20, 20), capture: true);
      expect(sel.texts, isEmpty);
    });
  });

  group('transformación de la selección', () {
    NotebookDoc page({TextBlock? t}) {
      final d = NotebookDoc(Notebook.create('t'));
      d.texts['t'] = t ?? block();
      return d;
    }

    test('escalar con una esquina multiplica la escala y mueve el texto desde el pivote', () {
      final d = page();
      final sel = Selection()..replace(texts: ['t']);
      final r0 = textRect(d.texts['t']!, d.lineAt(240));
      sel.startHandle(d, Handle.br, r0.bottomRight);
      sel.drag!.xf = Xform(pivot: sel.drag!.pivot, scale: 2);
      sel.applyToBlocks(d);
      final t = d.texts['t']!;
      expect(t.scale, closeTo(2, 1e-9));
      final r1 = textRect(t, d.lineAt(240));
      expect(r1.width, closeTo(r0.width * 2, 1e-6));
      expect((r1.topLeft - r0.topLeft).distance, lessThan(1e-6), reason: 'el pivote es la esquina de arriba a la izquierda del recuadro');
      // volver a la identidad lo deja como estaba
      sel.drag!.xf = const Xform();
      sel.applyToBlocks(d);
      expect(t.scale, 1);
      expect(t.angle, 0);
      expect(Offset(t.x, t.y), Offset(r0.left, r0.top));
    });

    test('rotar suma al giro y lleva el centro alrededor del pivote; un texto ya girado sigue sumando', () {
      final d = page(t: block(a: .2));
      final sel = Selection()..replace(texts: ['t']);
      sel.startHandle(d, Handle.rotate, const Offset(0, 0));
      final pivot = sel.drag!.pivot;
      sel.drag!.xf = Xform(pivot: pivot, angle: pi / 2);
      sel.applyToBlocks(d);
      final t = d.texts['t']!;
      expect(t.angle, closeTo(.2 + pi / 2, 1e-9));
      // con un solo texto el pivote es el centro de su recuadro: el centro no se mueve
      final c = textRect(t, d.lineAt(t.y)).center;
      expect((c - pivot).distance, lessThan(1e-6));
    });

    test('con dos textos, rotar mueve el centro de cada uno alrededor del pivote común', () {
      final d = page();
      d.texts['u'] = TextBlock('u', 500, 240, 200, 'otro');
      final sel = Selection()..replace(texts: ['t', 'u']);
      sel.startHandle(d, Handle.rotate, Offset.zero);
      final pivot = sel.drag!.pivot;
      final cu0 = textRect(d.texts['u']!, d.lineAt(240)).center;
      sel.drag!.xf = Xform(pivot: pivot, angle: pi);
      sel.applyToBlocks(d);
      final cu = textRect(d.texts['u']!, d.lineAt(d.texts['u']!.y)).center;
      expect((cu - (pivot * 2 - cu0)).distance, lessThan(1e-6), reason: 'media vuelta: el simétrico respecto del pivote');
      expect(d.texts['u']!.angle, closeTo(pi, 1e-9));
    });

    test('el recuadro de la selección sigue al texto girado y un texto no baja de 1/4 de tamaño', () {
      final d = page(t: block(a: pi / 2));
      final sel = Selection()..replace(texts: ['t']);
      final b = sel.contentRect(d)!;
      expect(b.width, closeTo(textBounds(d.texts['t']!, d.lineAt(240)).width, 1e-9));
      sel.startHandle(d, Handle.br, b.bottomRight);
      expect(sel.drag!.minScale, greaterThanOrEqualTo(.25));
    });
  });
}
