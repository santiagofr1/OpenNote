import 'package:apuntes/widgets/auto_scroller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('speedFor: los mismos números valen para el eje horizontal (con el ancho)', () {
    expect(AutoScroller.speedFor(500, 1000), 0);
    expect(AutoScroller.speedFor(0, 1000), -AutoScroller.maxSpeed);
    expect(AutoScroller.speedFor(1000, 1000), AutoScroller.maxSpeed);
    expect(AutoScroller.speedFor(10, 800), lessThan(0));
    expect(AutoScroller.speedFor(790, 800), greaterThan(0));
  });

  Future<(ScrollController, GlobalKey)> build(WidgetTester t, Axis axis) async {
    final c = ScrollController(), key = GlobalKey();
    await t.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          key: key,
          width: 400,
          height: 400,
          child: ListView(
            controller: c,
            scrollDirection: axis,
            children: [SizedBox(width: 2000, height: 2000)],
          ),
        ),
      ),
    ));
    return (c, key);
  }

  testWidgets('onScrolled se llama solo cuando el scroll se movió', (t) async {
    final (c, key) = await build(t, Axis.vertical);
    var n = 0;
    final a = AutoScroller(c, key, onScrolled: () => n++);
    final box = t.getTopLeft(find.byKey(key));
    a.moved(box + const Offset(200, 395)); // borde de abajo
    await t.pump(const Duration(milliseconds: 16));
    await t.pump(const Duration(milliseconds: 16));
    expect(c.offset, greaterThan(0));
    expect(n, 2);
    a.moved(box + const Offset(200, 5)); // borde de arriba, y ya en el tope: no se mueve
    c.jumpTo(0);
    n = 0;
    await t.pump(const Duration(milliseconds: 16));
    expect(c.offset, 0);
    expect(n, 0, reason: 'en el tope no hay salto');
    a.stop();
  });

  testWidgets('horizontal usa dx y el ancho', (t) async {
    final (c, key) = await build(t, Axis.horizontal);
    var n = 0;
    final a = AutoScroller(c, key, axis: Axis.horizontal, onScrolled: () => n++);
    final box = t.getTopLeft(find.byKey(key));
    a.moved(box + const Offset(200, 395)); // abajo pero al medio en x: nada
    await t.pump(const Duration(milliseconds: 16));
    expect(c.offset, 0);
    a.moved(box + const Offset(395, 200)); // borde derecho
    await t.pump(const Duration(milliseconds: 16));
    expect(c.offset, greaterThan(0));
    expect(n, 1);
    a.stop();
  });
}
