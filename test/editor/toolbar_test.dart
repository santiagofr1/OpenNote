import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester t,
    double w, {
    double h = 56,
    bool vertical = false,
    bool clip = false,
  }) async {
    final ts = ToolState()..dock = vertical ? 'left' : 'top';
    if (clip) ts.clipboard.strokes.add(Stroke('a', 'pen', '#000000', 1, [0, 0, .5, 1, 1, .5]));
    await t.binding.setSurfaceSize(Size(w, vertical ? h : 400));
    t.view.devicePixelRatio = 1;
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
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
                bg: 'plain',
                onToolTap: (_) {},
                onToolLongPress: (_) {},
                onPickColor: (_) {},
                onBg: (_) {},
                onOpenPanel: () {},
                onUndo: () {},
                onRedo: () {},
                onToggleZoomLock: () {},
                onPaste: () {},
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

  testWidgets('con portapapeles y los 6 botones de herramienta, a 676 dp entra sin desplazarse', (t) async {
    await pump(t, 676, clip: true);
    expect(t.takeException(), isNull);
    final scroll = t.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.maxScrollExtent, 0);
  });
}
