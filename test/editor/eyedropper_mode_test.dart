import 'dart:io';

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/eyedropper.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:apuntes/l10n/l10n.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Modo cuentagotas del editor: el panel se cierra, se avisa qué hacer, la lupa sigue al dedo, soltar toma el color de
/// lo que se ve y el panel vuelve a abrirse.
void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('apuntes_eye'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<({PageEditorState ed, ToolState tools, int Function() prefs})> open(WidgetTester t, {Tool tool = Tool.pen}) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final doc = NotebookDoc(Notebook.create('T'));
    final tools = ToolState()..tool = tool;
    var prefs = 0;
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      locale: const Locale('es'),
      home: Scaffold(
        body: PageEditor(doc: doc, tools: tools, store: Storage(root: root), onChanged: () {}, onPrefsChanged: () => prefs++),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
    return (ed: t.state<PageEditorState>(find.byType(PageEditor)), tools: tools, prefs: () => prefs);
  }

  /// Abre el panel desde la barra y toca el cuentagotas; espera la captura (que es asíncrona de verdad).
  Future<void> enter(WidgetTester t) async {
    await t.tap(find.byKey(const ValueKey('moreColors')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('eyedropper')));
    await t.pumpAndSettle();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump();
  }

  testWidgets('tocar el cuentagotas cierra el panel y deja el aviso con su botón de cancelar', (t) async {
    final h = await open(t);
    await enter(t);
    expect(h.ed.eyedropperTarget, EyeTarget.tool);
    expect(find.byKey(const Key('eyedropper')), findsNothing, reason: 'el panel se cerró');
    expect(find.text('Tocá la hoja para tomar un color'), findsOneWidget);
    expect(find.byTooltip('Cancelar cuentagotas'), findsOneWidget);
    expect(find.byKey(const Key('eyedropperLayer')), findsOneWidget);
    expect(find.byKey(const Key('eyedropperLoupe')), findsNothing);
  });

  testWidgets('cancelar con la X, con Escape o con atrás sale sin cambiar el color', (t) async {
    final h = await open(t);
    final c0 = h.tools.pen.color;
    await enter(t);
    await t.tap(find.byKey(const Key('eyedropperCancel')));
    await t.pump();
    expect(h.ed.eyedropperTarget, isNull);
    expect(find.byKey(const Key('eyedropperLayer')), findsNothing);

    await enter(t);
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pump();
    expect(h.ed.eyedropperTarget, isNull);

    await enter(t);
    expect(h.ed.cancelEyedropper(), isTrue);
    await t.pump();
    expect(h.ed.cancelEyedropper(), isFalse);
    expect(h.tools.pen.color, c0);
  });

  testWidgets('apoyar muestra la lupa arriba del dedo; soltar toma el color, lo aplica y vuelve a abrir el panel', (t) async {
    final h = await open(t);
    await enter(t);
    final at = const Offset(700, 500);
    final g = await t.startGesture(at, kind: PointerDeviceKind.stylus);
    await t.pump();
    final loupe = find.byKey(const Key('eyedropperLoupe'));
    expect(loupe, findsOneWidget);
    final c = t.getCenter(loupe);
    expect(c.dy, lessThan(at.dy - 40), reason: 'arriba del dedo');
    expect(t.getSize(loupe), const Size(96, 96));
    await g.moveTo(const Offset(720, 520));
    await t.pump();
    expect(loupe, findsOneWidget);
    await g.up();
    await t.pumpAndSettle();
    expect(h.ed.eyedropperTarget, isNull);
    expect(find.byKey(const Key('eyedropperLoupe')), findsNothing);
    expect(h.tools.pen.color, matches(RegExp(r'^#[0-9a-f]{6}$')));
    expect(h.tools.pen.color, isNot('#22211e'), reason: 'el papel no es el color de la tinta');
    expect(h.tools.penFav[h.tools.penFavSel], h.tools.pen.color, reason: 'el favorito elegido sigue al color');
    expect(find.byKey(const Key('eyedropper')), findsOneWidget, reason: 'vuelve el panel');
    expect(h.prefs(), greaterThan(0), reason: 'se persiste');
  });

  testWidgets('cerca del borde de arriba la lupa pasa abajo del dedo', (t) async {
    final h = await open(t);
    await enter(t);
    final g = await t.startGesture(const Offset(700, 60), kind: PointerDeviceKind.touch);
    await t.pump();
    expect(t.getCenter(find.byKey(const Key('eyedropperLoupe'))).dy, greaterThan(60 + 40));
    await g.up();
    await t.pumpAndSettle();
    expect(h.ed.eyedropperTarget, isNull);
  });

  testWidgets('en este modo no se dibuja ni se scrollea', (t) async {
    final h = await open(t);
    await enter(t);
    final y0 = h.ed.scroll.offset;
    final g = await t.startGesture(const Offset(600, 600), kind: PointerDeviceKind.stylus);
    await g.moveTo(const Offset(900, 650));
    await g.up();
    await t.pumpAndSettle();
    expect(h.ed.doc.strokes, isEmpty);
    // el panel volvió a abrirse: otra vez el cuentagotas desde ahí
    await t.tap(find.byKey(const Key('eyedropper')));
    await t.pumpAndSettle();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump();
    expect(h.ed.eyedropperTarget, EyeTarget.tool);
    final f = await t.startGesture(const Offset(600, 700), kind: PointerDeviceKind.touch);
    await f.moveTo(const Offset(600, 300));
    await t.pump();
    expect(h.ed.scroll.offset, y0);
    await f.up();
    await t.pumpAndSettle();
  });

  testWidgets('en Formas el cuentagotas del relleno aplica el color al relleno', (t) async {
    final h = await open(t, tool: Tool.shape);
    h.tools.shapeFill = true;
    h.tools.shapeKind = 'rect';
    await t.tap(find.byKey(const ValueKey('moreColors')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('eyedropper')));
    await t.pumpAndSettle();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump();
    expect(h.ed.eyedropperTarget, EyeTarget.shapeFill);
    final pen0 = h.tools.pen.color;
    final g = await t.startGesture(const Offset(800, 500), kind: PointerDeviceKind.stylus);
    await g.up();
    await t.pumpAndSettle();
    expect(h.tools.shapeFillColor, isNot('#93c5fd'));
    expect(h.tools.pen.color, pen0);
  });

  testWidgets('sobre la tinta toma el color del trazo', (t) async {
    final h = await open(t);
    h.tools.pen
      ..color = '#b91c1c'
      ..width = 14;
    final layers = find
        .descendant(of: find.byType(PageEditor), matching: find.byType(Listener))
        .evaluate()
        .map((e) => e.renderObject as RenderBox)
        .firstWhere((b) => b.hasSize && (b.size.width - kW * h.ed.scale).abs() < .5);
    final a = layers.localToGlobal(const Offset(200, 300) * 1.0 * h.ed.scale), b = layers.localToGlobal(const Offset(600, 300) * 1.0 * h.ed.scale);
    final g = await t.startGesture(a, kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 10; i++) {
      await g.moveTo(Offset.lerp(a, b, i / 10)!);
      await t.pump();
    }
    await g.up();
    await t.pump(const Duration(milliseconds: 500));
    expect(h.ed.doc.strokes.length, 1);
    h.tools.pen.color = '#1d4ed8'; // otro color
    await enter(t);
    final p = Offset.lerp(a, b, .5)!;
    final e = await t.startGesture(p, kind: PointerDeviceKind.stylus);
    await e.up();
    await t.pumpAndSettle();
    expect(h.tools.pen.color, '#b91c1c');
  });
}
