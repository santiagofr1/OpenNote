import 'package:apuntes/editor/fast_scroller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ScrollController c;

  Future<void> armar(WidgetTester t, {int items = 200}) async {
    c = ScrollController();
    addTearDown(c.dispose);
    t.view.physicalSize = const Size(800, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          ListView.builder(controller: c, itemExtent: 100, itemCount: items, itemBuilder: (_, i) => Text('$i')),
          Positioned(top: 0, bottom: 0, right: 0, width: 200, child: FastScroller(controller: c, label: () => 'L')),
        ]),
      ),
    ));
  }

  final thumb = find.byKey(const Key('fastScrollThumb'));
  IgnorePointer ignorer() => find.ancestor(of: thumb, matching: find.byType(IgnorePointer)).evaluate().map((e) => e.widget as IgnorePointer).first;
  double opacidad(WidgetTester t) => t.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

  testWidgets('al principio el pulgar no recibe toques y está transparente', (t) async {
    await armar(t);
    expect(ignorer().ignoring, isTrue);
    expect(opacidad(t), 0);
  });

  testWidgets('al scrollear aparece y después de un rato se esconde solo', (t) async {
    await armar(t);
    c.jumpTo(500);
    await t.pump();
    expect(opacidad(t), 1);
    expect(ignorer().ignoring, isFalse);
    await t.pump(const Duration(milliseconds: 1600));
    await t.pumpAndSettle();
    expect(opacidad(t), 0);
    expect(ignorer().ignoring, isTrue);
  });

  testWidgets('arrastrar el pulgar lleva al final, con burbuja mientras se arrastra', (t) async {
    await armar(t);
    c.jumpTo(500);
    await t.pump();
    await t.drag(thumb, const Offset(0, 2000));
    await t.pump();
    expect(c.offset, c.position.maxScrollExtent);
    expect(find.text('L'), findsNothing);

    c.jumpTo(0);
    await t.pump();
    final g = await t.startGesture(t.getCenter(thumb));
    await g.moveBy(const Offset(0, 100));
    await t.pump();
    expect(find.text('L'), findsOneWidget);
    await g.up();
    await t.pump();
    expect(find.text('L'), findsNothing);
    await t.pump(const Duration(milliseconds: 1600));
    await t.pumpAndSettle();
  });

  testWidgets('con contenido corto no se dibuja nada', (t) async {
    await armar(t, items: 5);
    c.jumpTo(c.position.maxScrollExtent);
    await t.pump();
    expect(thumb, findsNothing);
  });
}
