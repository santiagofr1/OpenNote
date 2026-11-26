import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/toolbar.dart';
import 'package:apuntes/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester t,
    double w, {
    double h = 56,
    bool vertical = false,
    bool clip = false,
    bool Function(int)? onSave,
  }) async {
    final ts = ToolState()..dock = vertical ? 'left' : 'top';
    if (clip) ts.clipboard.strokes.add(Stroke('a', 'pen', '#000000', 1, [0, 0, .5, 1, 1, .5]));
    await t.binding.setSurfaceSize(Size(w, vertical ? h : 400));
    t.view.devicePixelRatio = 1;
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      locale: const Locale('es'),
      
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: vertical ? 60 : w,
              height: vertical ? h : null,
              child: EditorToolbar(
                ts: ts,
                vertical: vertical,
                grip: SizedBox(
                  width: vertical ? 60 : 26,
                  height: vertical ? 26 : 56,
                ),
                canUndo: true,
                canRedo: false,
                onToolTap: (_) {},
                onToolLongPress: (_) {},
                onPickColor: (_) {},
                onSaveFavorite: onSave ?? (_) => false,
                onOpenPanel: () {},
                onUndo: () {},
                onRedo: () {},
                onToggleZoomLock: () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('barra arriba: sin desbordes a 360, 600, 800 y 1280 dp', (
    t,
  ) async {
    for (final w in [360.0, 600.0, 800.0, 1280.0]) {
      await pump(t, w);
      expect(t.takeException(), isNull, reason: 'ancho $w');
    }
  });

  testWidgets('mantener apretado un favorito pide guardar el color actual ahí y la muestra hace la animación', (t) async {
    final pedidos = <int>[];
    await pump(t, 1400, onSave: (i) {
      pedidos.add(i);
      return true;
    });
    final fav = find.byKey(const ValueKey('fav-1'));
    final scale = find.ancestor(of: fav, matching: find.byType(ScaleTransition)).first;
    expect(t.widget<ScaleTransition>(scale).scale.value, 1.0);
    await t.longPress(fav);
    await t.pump(const Duration(milliseconds: 110));
    expect(pedidos, [1]);
    expect(t.widget<ScaleTransition>(scale).scale.value, greaterThan(1.05));
    await t.pumpAndSettle();
    expect(t.widget<ScaleTransition>(scale).scale.value, 1.0);
  });

  testWidgets('si no cambia nada (ya estaba ese color) no hay animación', (t) async {
    await pump(t, 1400); // onSave devuelve false
    final fav = find.byKey(const ValueKey('fav-1'));
    final scale = find.ancestor(of: fav, matching: find.byType(ScaleTransition)).first;
    await t.longPress(fav);
    await t.pump(const Duration(milliseconds: 110));
    expect(t.widget<ScaleTransition>(scale).scale.value, 1.0);
  });

  testWidgets('sin botones de Pegar ni de fondo (issue #29); sin colores no desborda con el ancho fijo', (t) async {
    await pump(t, 1400);
    expect(find.byTooltip('Pegar'), findsNothing);
    expect(find.byTooltip('Fondo de la hoja'), findsNothing);
    // ancho útil = _fixedWidth (632) + 12 de padding: justo entra, sin colores y sin desplazarse
    await pump(t, 644);
    expect(t.takeException(), isNull);
    expect(t.state<ScrollableState>(find.byType(Scrollable)).position.maxScrollExtent, 0);
    await pump(t, 600);
    expect(t.state<ScrollableState>(find.byType(Scrollable)).position.maxScrollExtent, greaterThan(0));
  });

  testWidgets('barra al costado: sin desbordes con alturas cortas', (t) async {
    for (final h in [200.0, 400.0, 800.0]) {
      await pump(t, 300, h: h, vertical: true);
      expect(t.takeException(), isNull, reason: 'alto $h');
    }
  });

  testWidgets(
    'ancho intermedio (648 dp, el que desbordaba 52 px) entra sin desplazarse',
    (t) async {
      await pump(t, 648);
      expect(t.takeException(), isNull);
      final scroll = t.state<ScrollableState>(find.byType(Scrollable));
      expect(scroll.position.maxScrollExtent, 0);
    },
  );

  testWidgets('con los 6 botones de herramienta, a 676 dp entra sin desplazarse', (t) async {
    await pump(t, 676, clip: true);
    expect(t.takeException(), isNull);
    final scroll = t.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.maxScrollExtent, 0);
  });
}
