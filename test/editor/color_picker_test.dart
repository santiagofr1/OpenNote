import 'dart:convert';
import 'dart:math' show cos, sin;

import 'package:apuntes/domain/domain.dart';
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
    Future<void> longPressDot(WidgetTester t, Finder f) async {
      await t.ensureVisible(f);
      await t.pumpAndSettle();
      await t.longPress(f);
      await t.pumpAndSettle();
    }

    testWidgets('la ayuda explica que se edita con la rueda y que mantener apretado borra; no hay Cambiar', (t) async {
      await open(t);
      expect(find.byKey(const Key('favEdit')), findsNothing);
      expect(find.text('Cambiar'), findsNothing);
      expect(find.text('Tocá un favorito y cambiale el color con la rueda. Mantenelo apretado para borrarlo.'), findsOneWidget);
    });

    testWidgets('tocar un favorito lo elige y usa su color sin tocar los favoritos', (t) async {
      await open(t);
      final favs0 = List<String>.from(ts.favorites);
      await t.tap(find.byKey(const ValueKey('panelFav-3')));
      await t.pump();
      expect(ts.pen.color, favs0[3]);
      expect(ts.favSel, 3);
      expect(ts.favorites, favs0);
    });

    testWidgets('elegir un favorito y escribir un hex lo edita, y el encabezado lo muestra', (t) async {
      await open(t);
      final favs0 = List<String>.from(ts.favorites);
      await t.tap(find.byKey(const ValueKey('panelFav-0')));
      await t.pump();
      await t.ensureVisible(find.byKey(const Key('colorHex')));
      await t.enterText(find.byKey(const Key('colorHex')), '7B3A43');
      await t.testTextInput.receiveAction(TextInputAction.done);
      await t.pump();
      expect(ts.favorites[0], '#7b3a43');
      expect(ts.favorites.sublist(1), favs0.sublist(1));
      expect(ts.pen.color, '#7b3a43');
      expect(find.text('#7B3A43'), findsOneWidget);
    });

    testWidgets('mover la rueda edita el favorito elegido', (t) async {
      await open(t);
      await t.tap(find.byKey(const ValueKey('panelFav-1')));
      await t.tapAt(onRing(t, 200));
      await t.pump();
      expect(ts.favorites[1], ts.pen.color);
      expect(ts.favorites[1], isNot(ToolState().penFav[1]));
    });

    testWidgets('el + suma un favorito con el color actual, lo elige y el hex solo cambia ese', (t) async {
      await open(t);
      final favs0 = List<String>.from(ts.favorites);
      final add = find.byKey(const ValueKey('panelFavAdd'));
      await t.ensureVisible(add);
      await t.tap(add);
      await t.pump();
      expect(ts.favorites.length, 5);
      expect(ts.favorites[4], ts.pen.color);
      expect(ts.favSel, 4);
      await setHex(t, '7B3A43');
      expect(ts.favorites[4], '#7b3a43');
      expect(ts.favorites.sublist(0, 4), favs0);
    });

    testWidgets('mantener apretado un favorito ofrece borrarlo', (t) async {
      await open(t);
      final favs0 = List<String>.from(ts.favorites);
      await longPressDot(t, find.byKey(const ValueKey('panelFav-1')));
      expect(find.byKey(const ValueKey('panelFavDelete')), findsOneWidget);
      expect(find.text('Borrar color'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('panelFavDelete')));
      await t.pumpAndSettle();
      expect(ts.favorites, [favs0[0], favs0[2], favs0[3]]);
      expect(find.byKey(const ValueKey('panelFav-3')), findsNothing);
    });

    testWidgets('con un solo favorito mantener apretado no abre menú', (t) async {
      await open(t);
      while (ts.favorites.length > 1) {
        ts.removeFavorite(0);
      }
      await t.tap(find.byKey(const ValueKey('panelFav-0'))); // se redibuja el panel con un solo favorito
      await t.pump();
      expect(find.byKey(const ValueKey('panelFav-1')), findsNothing);
      await longPressDot(t, find.byKey(const ValueKey('panelFav-0')));
      expect(find.byKey(const ValueKey('panelFavDelete')), findsNothing);
      expect(ts.favorites.length, 1);
    });

    testWidgets('con 8 favoritos no hay +', (t) async {
      await open(t);
      final add = find.byKey(const ValueKey('panelFavAdd'));
      await t.ensureVisible(add);
      for (var i = 0; i < 4; i++) {
        await t.tap(add);
        await t.pump();
      }
      expect(ts.favorites.length, 8);
      expect(add, findsNothing);
    });

    testWidgets('ya no hay fila de recientes', (t) async {
      await open(t);
      expect(find.byKey(const Key('colorRecent')), findsNothing);
      await open(t, tool: Tool.paint);
      expect(find.byKey(const Key('colorRecent')), findsNothing);
    });

    testWidgets('en el Decorador los favoritos del fondo funcionan igual', (t) async {
      await open(t, tool: Tool.paint);
      final favs0 = List<String>.from(ts.paintFav);
      await t.ensureVisible(find.byKey(const ValueKey('panelFav-0')));
      await t.tap(find.byKey(const ValueKey('panelFav-0')));
      await t.pump();
      await t.enterText(find.byKey(const Key('colorHex')).first, '7B3A43'); // el panel tiene otra rueda (formas)
      await t.pump();
      expect(ts.paintFav[0], '#7b3a43');
      expect(ts.paintFav.sublist(1), favs0.sublist(1));
      expect(ts.paint.color, '#7b3a43');
      expect(ts.penFav, ToolState().penFav, reason: 'los del lápiz no se tocan');
    });
  });

  group('ToolState', () {
    test('un colorView viejo en los ajustes se ignora y ya no se guarda', () {
      final b = ToolState()..load({'colorView': 'wheel'});
      expect(b.toJson().containsKey('colorView'), isFalse);
      expect(() => ToolState().load({'colorView': 'otra'}), returnsNormally);
      expect(jsonDecode(jsonEncode(b.toJson())), isA<Map>());
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
