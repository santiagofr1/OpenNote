import 'dart:convert';
import 'dart:math' show cos, sin;

import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/color_chooser.dart';
import 'package:apuntes/editor/eyedropper.dart';
import 'package:apuntes/editor/pen_panel.dart';
import 'package:apuntes/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ToolState ts;
  EyeTarget? eye;

  Future<void> open(WidgetTester t, {double h = 1600, double w = 800, Tool tool = Tool.pen, double textScale = 1}) async {
    ts = ToolState()..tool = tool;
    eye = null;
    await t.binding.setSurfaceSize(Size(w, h));
    t.view.devicePixelRatio = 1;
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      locale: const Locale('es'),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            key: const Key('open'),
            onPressed: () async => eye = await showPenPanel(ctx, ts, () {}),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await t.tap(find.byKey(const Key('open')));
    await t.pumpAndSettle();
  }

  // escribe un color en el campo hex de la rueda (la rueda siempre está a la vista)
  Future<void> setHex(WidgetTester t, String digits) async {
    await t.ensureVisible(find.byKey(const Key('colorHex')));
    await t.enterText(find.byKey(const Key('colorHex')), digits);
    await t.pump();
  }

  DateTime now = DateTime(2026, 1, 1);
  setUp(() {
    now = DateTime(2026, 1, 1);
    ToolState.clock = () => now;
  });
  tearDown(() => ToolState.clock = DateTime.now);

  double scrollPos(WidgetTester t) => t.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;

  HSVColor hsvOf(String hex) => HSVColor.fromColor(parseColor(hex));

  Offset wheelCenter(WidgetTester t) => t.getCenter(find.byKey(const Key('colorWheel')));
  double wheelRadius(WidgetTester t) => t.getSize(find.byKey(const Key('colorWheel'))).width / 2;

  /// Un punto del anillo a [deg] grados (0 = las 3 en punto, creciendo en el sentido del reloj).
  Offset onRing(WidgetTester t, double deg) {
    final a = deg * 3.141592653589793 / 180;
    final r = wheelRadius(t) - 11;
    return wheelCenter(t) + Offset(r * cos(a), r * sin(a));
  }

  group('vistas', () {
    testWidgets('el selector muestra la rueda directo, sin vista Paleta ni botones de vista', (t) async {
      await open(t);
      expect(find.byKey(const Key('colorWheel')), findsOneWidget);
      expect(find.byKey(const Key('colorViewPalette')), findsNothing);
      expect(find.byKey(const Key('colorViewWheel')), findsNothing);
      expect(find.byKey(const Key('eyedropper')), findsOneWidget);
      expect(find.byTooltip('Paleta'), findsNothing);
      expect(find.byTooltip('Cuentagotas'), findsOneWidget);
      expect(find.byKey(const Key('colorRing')), findsOneWidget);
      expect(find.byKey(const Key('colorSquare')), findsOneWidget);
      expect(find.byKey(const Key('colorHex')), findsOneWidget);
      expect(find.byKey(const Key('colorHue')), findsNothing, reason: 'ya no hay barritas');
    });

    testWidgets('el Decorador ofrece Auto, Claro y Oscuro sobre la rueda y ya no los colores fijos', (t) async {
      await open(t, tool: Tool.paint);
      expect(find.byKey(const Key('paintShapeAuto')), findsOneWidget);
      expect(find.byKey(const Key('shapeColor-light')), findsOneWidget);
      expect(find.byKey(const Key('shapeColor-dark')), findsOneWidget);
      for (final c in ['#ffffff', '#c0c4cc', '#d4a937']) {
        expect(find.byKey(Key('shapeColor-$c')), findsNothing);
      }
    });

    testWidgets('el encabezado muestra el hex del color actual en mayúsculas', (t) async {
      await open(t);
      await setHex(t, '3B82F6');
      await t.pump();
      expect(find.text('#3B82F6'), findsOneWidget);
    });

    testWidgets('el cuentagotas cierra el panel y devuelve el destino', (t) async {
      await open(t);
      await t.tap(find.byKey(const Key('eyedropper')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('eyedropper')), findsNothing);
      expect(eye, EyeTarget.tool);
    });

    testWidgets('en las formas y el Decorador el destino del cuentagotas es el que corresponde', (t) async {
      await open(t, tool: Tool.shape);
      ts.shapeFill = true;
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('open')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('eyedropper')));
      await t.pumpAndSettle();
      expect(eye, EyeTarget.shapeFill);

      await open(t, tool: Tool.paint);
      final eyes = find.byKey(const Key('eyedropper'));
      expect(eyes, findsNWidgets(2), reason: 'el fondo y el color de las formitas');
      await t.ensureVisible(eyes.first);
      await t.tap(eyes.first);
      await t.pumpAndSettle();
      expect(eye, EyeTarget.tool);

      await open(t, tool: Tool.paint);
      await t.ensureVisible(find.byKey(const Key('eyedropper')).last);
      await t.tap(find.byKey(const Key('eyedropper')).last);
      await t.pumpAndSettle();
      expect(eye, EyeTarget.paintShape);
    });
  });

  group('rueda', () {
    testWidgets('tocar el anillo cambia el tono y deja la saturación y el brillo', (t) async {
      await open(t);
      await setHex(t, '3B82F6');
      final antes = hsvOf(ts.pen.color);
      await t.tapAt(onRing(t, 0)); // a las 3 en punto: rojo
      await t.pump();
      final d = hsvOf(ts.pen.color);
      expect(d.hue < 3 || d.hue > 357, isTrue, reason: 'hue ${d.hue}');
      expect(d.saturation, closeTo(antes.saturation, .02));
      expect(d.value, closeTo(antes.value, .02));
      await t.tapAt(onRing(t, 120)); // abajo a la izquierda... en pantalla 120° es verde
      await t.pump();
      expect(hsvOf(ts.pen.color).hue, closeTo(120, 3));
      await t.tapAt(onRing(t, 240));
      await t.pump();
      expect(hsvOf(ts.pen.color).hue, closeTo(240, 3));
    });

    testWidgets('arrastrar desde el anillo sigue moviendo el tono aunque el dedo entre al cuadrado', (t) async {
      await open(t);
      await setHex(t, '3B82F6');
      final s0 = hsvOf(ts.pen.color).saturation;
      final g = await t.startGesture(onRing(t, 0));
      await g.moveTo(wheelCenter(t) + const Offset(0, 30)); // adentro del cuadrado, hacia las 6
      await t.pump();
      final d = hsvOf(ts.pen.color);
      expect(d.hue, closeTo(90, 4));
      expect(d.saturation, closeTo(s0, .02));
      await g.up();
    });

    testWidgets('tocar y arrastrar en el cuadrado cambia saturación y brillo y deja el tono', (t) async {
      await open(t);
      await setHex(t, '3B82F6');
      final h0 = hsvOf(ts.pen.color).hue;
      final sq = find.byKey(const Key('colorSquare'));
      await t.tapAt(t.getTopLeft(sq) + const Offset(1, 1)); // blanco: saturación 0, brillo 1
      await t.pump();
      expect(hsvOf(ts.pen.color).saturation, lessThan(.03));
      expect(hsvOf(ts.pen.color).value, greaterThan(.97));
      await t.tapAt(t.getBottomRight(sq) - const Offset(1, 1)); // negro
      await t.pump();
      expect(hsvOf(ts.pen.color).value, lessThan(.03));
      await t.tapAt(t.getTopRight(sq) + const Offset(-1, 1)); // el tono puro
      await t.pump();
      final d = hsvOf(ts.pen.color);
      expect(d.saturation, greaterThan(.97));
      expect(d.value, greaterThan(.97));
      expect(d.hue, closeTo(h0, 3));
    });

    testWidgets('arrastrar desde el cuadrado hacia afuera queda en el borde y no cambia el tono', (t) async {
      await open(t);
      await setHex(t, '3B82F6');
      final h0 = hsvOf(ts.pen.color).hue;
      final g = await t.startGesture(wheelCenter(t));
      await g.moveTo(wheelCenter(t) + const Offset(400, -400)); // muy afuera, arriba a la derecha
      await t.pump();
      final d = hsvOf(ts.pen.color);
      expect(d.saturation, greaterThan(.97));
      expect(d.value, greaterThan(.97));
      expect(d.hue, closeTo(h0, 3));
      await g.up();
    });

    testWidgets('arrastrar en la rueda no scrollea el panel; afuera el mismo gesto sí', (t) async {
      await open(t, h: 700); // bajo: el panel tiene scroll
      await t.ensureVisible(find.byKey(const Key('colorWheel')));
      await t.pumpAndSettle();
      final pos0 = scrollPos(t);
      expect(pos0, greaterThan(0));
      final antes = ts.pen.color;
      final g = await t.startGesture(wheelCenter(t));
      await g.moveBy(const Offset(0, 60));
      await t.pump();
      await g.moveBy(const Offset(0, 40));
      await g.up();
      await t.pump();
      expect(scrollPos(t), pos0);
      expect(ts.pen.color, isNot(antes));
      await t.drag(find.byKey(const Key('colorHexLabel')), const Offset(0, 80));
      await t.pump();
      expect(scrollPos(t), isNot(pos0));
    });

    testWidgets('mover la rueda no suma a recientes; sí al cerrar el panel', (t) async {
      await open(t);
      await setHex(t, '3B82F6');
      final rec0 = List<String>.from(ts.recent);
      await t.tapAt(onRing(t, 0));
      await t.pump();
      expect(ts.recent, rec0);
      final c = ts.pen.color;
      await t.tapAt(const Offset(5, 5));
      await t.pumpAndSettle();
      expect(ts.recent.first, c);
    });

    testWidgets('si el color cambia desde afuera, la rueda se resincroniza', (t) async {
      await open(t);
      await t.tap(find.byKey(const ValueKey('panelFav-2'))); // #b91c1c: el color cambia desde afuera de la rueda
      await t.pump();
      final field = t.widget<TextField>(find.byKey(const Key('colorHex')));
      expect(field.controller!.text, 'B91C1C');
    });
  });

  group('hex', () {
    testWidgets('un hex válido se aplica', (t) async {
      await open(t);
      await t.enterText(find.byKey(const Key('colorHex')), 'ff8800');
      await t.pump();
      expect(ts.pen.color, '#ff8800');
      expect(hsvOf(ts.pen.color).hue, closeTo(32, 1));
    });

    testWidgets('minúsculas y letras que no son hex se filtran', (t) async {
      await open(t);
      await t.enterText(find.byKey(const Key('colorHex')), 'xyz12ab');
      await t.pump();
      final c = t.widget<TextField>(find.byKey(const Key('colorHex'))).controller!;
      expect(c.text, '12AB');
      expect(ts.pen.color, '#22211e', reason: 'incompleto: no se aplica');
    });

    testWidgets('uno inválido no se aplica y marca el borde con el color de error', (t) async {
      await open(t);
      final antes = ts.pen.color;
      await t.enterText(find.byKey(const Key('colorHex')), '12');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(ts.pen.color, antes);
      final err = Theme.of(t.element(find.byKey(const Key('colorHex')))).colorScheme.error;
      final dec = t.widget<TextField>(find.byKey(const Key('colorHex'))).decoration!;
      expect((dec.enabledBorder as OutlineInputBorder).borderSide.color, err);
      expect((dec.focusedBorder as OutlineInputBorder).borderSide.color, err);
    });

    testWidgets('con 3 cifras al confirmar se duplican', (t) async {
      await open(t);
      await t.enterText(find.byKey(const Key('colorHex')), 'f80');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(ts.pen.color, '#ff8800');
    });
  });

  group('favoritos', () {
    testWidgets('no hay botón Cambiar y la ayuda explica el mantener apretado', (t) async {
      await open(t);
      expect(find.byKey(const Key('favEdit')), findsNothing);
      expect(find.text('Cambiar'), findsNothing);
      expect(find.text('Mantené apretado un favorito para reemplazarlo por el color actual.'), findsOneWidget);
      expect(find.byIcon(Icons.edit), findsNothing);
    });

    testWidgets('mantener apretado un favorito guarda ahí el color actual y solo cambia ese', (t) async {
      await open(t);
      final favs0 = List<String>.from(ts.favorites);
      const c = '#7b3a43';
      await setHex(t, '7B3A43');
      await t.longPress(find.byKey(const ValueKey('panelFav-2')));
      await t.pumpAndSettle();
      expect(ts.favorites[2], c);
      for (final i in [0, 1, 3]) {
        expect(ts.favorites[i], favs0[i]);
      }
      expect(ts.pen.color, c, reason: 'el color actual no cambia');
    });

    testWidgets('guarda también un color de la rueda', (t) async {
      await open(t);
      await t.tapAt(onRing(t, 200));
      await t.pump();
      final c = ts.pen.color;
      await t.longPress(find.byKey(const ValueKey('panelFav-0')));
      await t.pumpAndSettle();
      expect(ts.favorites[0], c);
    });

    testWidgets('la animación de confirmación escala la muestra y vuelve', (t) async {
      await open(t);
      ts.pen.color = '#7b3a43';
      final f = find.byKey(const ValueKey('panelFav-1'));
      final g = await t.startGesture(t.getCenter(f));
      await t.pump(const Duration(milliseconds: 600)); // pasa el tiempo del toque largo
      await g.up();
      await t.pump();
      await t.pump(const Duration(milliseconds: 110));
      final scale = find.descendant(of: f, matching: find.byType(ScaleTransition)).evaluate().isEmpty
          ? find.ancestor(of: f, matching: find.byType(ScaleTransition))
          : find.descendant(of: f, matching: find.byType(ScaleTransition));
      final peak = t.widget<ScaleTransition>(scale.first).scale.value;
      expect(peak, greaterThan(1.05));
      await t.pumpAndSettle();
      expect(t.widget<ScaleTransition>(scale.first).scale.value, 1.0);
    });

    testWidgets('si el favorito ya tiene ese color no hace nada', (t) async {
      await open(t);
      final favs0 = List<String>.from(ts.favorites);
      await t.tap(find.byKey(const ValueKey('panelFav-1')));
      await t.pump();
      expect(ts.pen.color, favs0[1]);
      now = now.add(const Duration(seconds: 3)); // ya no cuenta como el toque de recién
      await t.longPress(find.byKey(const ValueKey('panelFav-1')));
      await t.pumpAndSettle();
      expect(ts.favorites, favs0);
      expect(ts.saveFavorite(1), isFalse);
    });

    testWidgets('tocar un favorito usa ese color y no toca los favoritos', (t) async {
      await open(t);
      final favs0 = List<String>.from(ts.favorites);
      await t.tap(find.byKey(const ValueKey('panelFav-3')));
      await t.pump();
      expect(ts.pen.color, favs0[3]);
      expect(ts.favorites, favs0);
    });

    testWidgets('elegir un color en la rueda no toca los favoritos', (t) async {
      await open(t);
      final favs0 = List<String>.from(ts.favorites);
      await setHex(t, '7B3A43');
      expect(ts.pen.color, '#7b3a43');
      expect(ts.favorites, favs0);
    });

    testWidgets('un toque justo antes del mantener apretado no se traga el color: se guarda el de la rueda', (t) async {
      await open(t);
      await setHex(t, '7B3A43');
      final f = find.byKey(const ValueKey('panelFav-0'));
      await t.tap(f);
      await t.longPress(f);
      await t.pumpAndSettle();
      expect(ts.favorites[0], '#7b3a43');
      expect(ts.pen.color, '#7b3a43', reason: 'el toque se deshizo');
      expect(find.text('#7B3A43'), findsOneWidget, reason: 'el encabezado muestra el color restaurado');
    });

    testWidgets('si el mantener apretado llega más de 2 s después del toque, no hace nada', (t) async {
      await open(t);
      final fav0 = ts.favorites[0];
      await setHex(t, '7B3A43');
      final f = find.byKey(const ValueKey('panelFav-0'));
      await t.tap(f);
      now = now.add(const Duration(seconds: 3));
      await t.longPress(f);
      await t.pumpAndSettle();
      expect(ts.favorites[0], fav0);
      expect(ts.pen.color, fav0);
    });

    testWidgets('mantener apretado sin toque previo guarda el color actual', (t) async {
      await open(t);
      await setHex(t, '7B3A43');
      await t.longPress(find.byKey(const ValueKey('panelFav-0')));
      await t.pumpAndSettle();
      expect(ts.favorites[0], '#7b3a43');
      expect(ts.pen.color, '#7b3a43');
    });

    testWidgets('en el Decorador los favoritos del fondo funcionan igual', (t) async {
      await open(t, tool: Tool.paint);
      final favs0 = List<String>.from(ts.paintFav);
      ts.paint.color = '#7b3a43';
      await t.ensureVisible(find.byKey(const ValueKey('panelFav-0')));
      await t.longPress(find.byKey(const ValueKey('panelFav-0')));
      await t.pumpAndSettle();
      expect(ts.paintFav[0], '#7b3a43');
      expect(ts.paintFav.sublist(1), favs0.sublist(1));
      expect(ts.penFav, ToolState().penFav, reason: 'los del lápiz no se tocan');
    });
  });

  group('recientes', () {
    testWidgets('hay una fila de recientes y tocar uno lo usa', (t) async {
      await open(t);
      expect(find.byKey(const Key('colorRecent')), findsOneWidget);
      final c = ts.recent[3];
      await t.tap(find.descendant(of: find.byKey(const Key('colorRecent')), matching: find.byType(ColorDot)).at(3));
      await t.pump();
      expect(ts.pen.color, c);
    });

  });

  group('ToolState', () {
    test('un colorView viejo en los ajustes se ignora y ya no se guarda', () {
      final b = ToolState()..load({'colorView': 'wheel'});
      expect(b.toJson().containsKey('colorView'), isFalse);
      expect(() => ToolState().load({'colorView': 'otra'}), returnsNormally);
      expect(jsonDecode(jsonEncode(b.toJson())), isA<Map>());
    });

    test('saveFavorite guarda el color actual de la herramienta en curso', () {
      final a = ToolState()..tool = Tool.hl;
      a.hl.color = '#123456';
      expect(a.saveFavorite(2), isTrue);
      expect(a.hlFav[2], '#123456');
      expect(a.penFav, ToolState().penFav);
      expect(a.saveFavorite(2), isFalse);
      expect(a.saveFavorite(9), isFalse);
    });
  });

  group('sin desbordes', () {
    for (final tool in [Tool.pen, Tool.hl, Tool.paint, Tool.shape]) {
      {
        testWidgets('panel angosto y letra grande: ${tool.name}', (t) async {
          ts = ToolState()
            ..tool = tool
            ..shapeFill = true;
          await t.binding.setSurfaceSize(const Size(320, 700));
          t.view.devicePixelRatio = 1;
          addTearDown(() => t.binding.setSurfaceSize(null));
          await t.pumpWidget(MaterialApp(
            localizationsDelegates: L.localizationsDelegates,
            supportedLocales: L.supportedLocales,
            locale: const Locale('es'),
            builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.6)), child: child!),
            home: Builder(builder: (ctx) => Scaffold(body: TextButton(key: const Key('open'), onPressed: () => showPenPanel(ctx, ts, () {}), child: const Text('abrir')))),
          ));
          await t.tap(find.byKey(const Key('open')));
          await t.pumpAndSettle();
          final ex = t.takeException(); expect(ex == null ? null : (ex as FlutterError).toStringDeep(), isNull);
          expect(find.byKey(const Key('eyedropper')), findsWidgets);
        });
      }
    }
  });
}
