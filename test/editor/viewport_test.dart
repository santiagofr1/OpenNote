import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/touch_gestures.dart';
import 'package:apuntes/editor/viewport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SheetLayout', () {
    test('zoom 1: la hoja entra a lo ancho con margen', () {
      final l = SheetLayout(800, 1);
      expect(l.sheetWidth, 800 - 48);
      expect(l.scale, (800 - 48) / kW);
      expect(l.sheetLeft, 24);
      expect(l.contentWidth, 800);
      expect(SheetLayout(600, 1).sheetLeft, 6, reason: 'pantalla chica: margen chico');
      expect(SheetLayout(2000, 1).sheetWidth, 1100, reason: 'tope de ancho');
    });

    test('con zoom el contenido se hace más ancho que el visor', () {
      final l = SheetLayout(800, 2);
      expect(l.sheetWidth, (800 - 48) * 2);
      expect(l.contentWidth, l.sheetWidth + 48);
    });

    test('toPage y scrollFor son inversas: el punto bajo el dedo queda quieto al hacer zoom', () {
      const focal = Offset(300, 400), scroll0 = Offset(0, 900);
      final before = SheetLayout(800, 1), after = SheetLayout(800, 2.5);
      final anchor = before.toPage(focal, scroll0);
      final scroll1 = after.scrollFor(anchor, focal);
      final again = after.toPage(focal, scroll1);
      expect(again.dx, closeTo(anchor.dx, 1e-9));
      expect(again.dy, closeTo(anchor.dy, 1e-9));
      expect(before.toPage(Offset(before.sheetLeft, kTopPad), Offset.zero), Offset.zero);
    });
  });

  group('TouchTracker', () {
    test('pellizco: el zoom sigue la distancia entre los dedos', () {
      final t = TouchTracker();
      t.down(1, const Offset(100, 100));
      expect(t.pinch(), isNull);
      t.down(2, const Offset(300, 100));
      t.startPinch(1.5);
      t.move(2, const Offset(500, 100));
      final p = t.pinch()!;
      expect(p.zoom, closeTo(3, 1e-9));
      expect(p.focal, const Offset(300, 100));
      t.up(2);
      expect(t.pinch(), isNull, reason: 'con un dedo no hay pellizco');
      expect(t.count, 1);
      t.up(1);
      t.up(1);
      expect(t.count, 0, reason: 'nunca negativo');
    });
  });

  group('StillPressTimer', () {
    testWidgets('dispara a los 500 ms si el dedo no se movió', (tester) async {
      final fired = <Offset>[];
      final t = StillPressTimer(fired.add);
      t.start(const Offset(10, 10));
      t.moved(const Offset(15, 15)); // menos de 12: sigue
      await tester.pump(const Duration(milliseconds: 499));
      expect(fired, isEmpty);
      await tester.pump(const Duration(milliseconds: 2));
      expect(fired, [const Offset(10, 10)]);
    });

    testWidgets('moverse o cancelar lo frena', (tester) async {
      final fired = <Offset>[];
      final t = StillPressTimer(fired.add);
      t.start(Offset.zero);
      t.moved(const Offset(20, 0));
      await tester.pump(const Duration(seconds: 1));
      t.start(Offset.zero);
      t.cancel();
      await tester.pump(const Duration(seconds: 1));
      expect(fired, isEmpty);
    });
  });
}
