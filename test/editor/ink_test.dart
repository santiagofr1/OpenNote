import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/ink.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PointerDownEvent down(PointerDeviceKind kind, [int buttons = kPrimaryButton]) =>
      PointerDownEvent(kind: kind, buttons: buttons, pressure: .8, pressureMin: 0, pressureMax: 1);

  group('a quién le hace caso la hoja', () {
    test('el dedo nunca dibuja (scrollea; así se ignora la palma)', () {
      for (final t in Tool.values) {
        expect(penActionFor(down(PointerDeviceKind.touch), t), isNull);
      }
    });

    test('lápiz según la herramienta', () {
      final s = down(PointerDeviceKind.stylus);
      expect(penActionFor(s, Tool.pen), PenAction.draw);
      expect(penActionFor(s, Tool.hl), PenAction.draw);
      expect(penActionFor(s, Tool.select), PenAction.select);
      expect(penActionFor(s, Tool.text), isNull, reason: 'en modo texto el lápiz toca los campos');
    });

    test('botón del S Pen y punta goma borran, con cualquier herramienta', () {
      for (final b in [kPrimaryStylusButton, kSecondaryStylusButton]) {
        final e = down(PointerDeviceKind.stylus, kPrimaryButton | b);
        expect(wantsEraser(e), isTrue);
        expect(penActionFor(e, Tool.text), PenAction.erase);
        expect(penActionFor(e, Tool.select), PenAction.erase);
      }
      expect(penActionFor(down(PointerDeviceKind.invertedStylus), Tool.pen), PenAction.erase);
    });

    test('mouse: izquierdo dibuja, derecho borra, otros botones nada', () {
      expect(penActionFor(down(PointerDeviceKind.mouse, kPrimaryMouseButton), Tool.pen), PenAction.draw);
      expect(penActionFor(down(PointerDeviceKind.mouse, kSecondaryMouseButton), Tool.pen), PenAction.erase);
      expect(penActionFor(down(PointerDeviceKind.mouse, kMiddleMouseButton), Tool.pen), isNull);
      expect(penActionFor(down(PointerDeviceKind.mouse, kPrimaryMouseButton | kSecondaryMouseButton), Tool.pen), isNull);
    });
  });

  test('presión: normalizada en el lápiz, media para el resto', () {
    expect(pressureOf(down(PointerDeviceKind.stylus)), closeTo(.8, 1e-9));
    expect(pressureOf(down(PointerDeviceKind.mouse)), .5);
    expect(pressureOf(const PointerDownEvent(kind: PointerDeviceKind.stylus, pressure: 3, pressureMin: 1, pressureMax: 1)), .5,
        reason: 'sin rango');
  });

  test('appendInkPoint: descarta puntos casi iguales y suaviza la presión', () {
    final s = Stroke('s', 'pen', '#000000', 2, []);
    appendInkPoint(s, const Offset(0, 0), 1);
    appendInkPoint(s, const Offset(.2, .2), 0); // se movió menos de .6
    expect(s.n, 1);
    appendInkPoint(s, const Offset(10, 0), 0);
    expect(s.pts, [0, 0, 1, 10, 0, closeTo(.65, 1e-9)]);
    expect(s.bounds.right, greaterThan(10), reason: 'invalida los bounds');
  });

  test('strokesHit: solo los trazos que toca la goma', () {
    final p = NotebookDoc(Notebook.create('t'));
    p.strokes['a'] = Stroke('a', 'pen', '#000000', 2, [0, 0, .5, 100, 0, .5]);
    p.strokes['b'] = Stroke('b', 'pen', '#000000', 2, [0, 100, .5, 100, 100, .5]);
    expect(strokesHit(p, const Offset(50, 5), 8).map((s) => s.id), ['a']);
    expect(strokesHit(p, const Offset(50, 50), 8), isEmpty);
  });
}
