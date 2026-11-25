import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/pen_panel.dart';
import 'package:apuntes/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ToolState ts;

  Future<void> open(WidgetTester t, {int? editFav, double h = 1600}) async {
    ts = ToolState()..tool = Tool.pen;
    await t.binding.setSurfaceSize(Size(800, h));
    t.view.devicePixelRatio = 1;
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: L.localizationsDelegates,
      supportedLocales: L.supportedLocales,
      locale: const Locale('es'),
      
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            key: const Key('open'),
            onPressed: () => showPenPanel(ctx, ts, () {}, editFav: editFav),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await t.tap(find.byKey(const Key('open')));
    await t.pumpAndSettle();
  }

  // un color de la paleta que no es ningún favorito
  String paletteColor() => palette.firstWhere((c) => !ts.favorites.contains(c) && c != ts.pen.color);

  Finder swatch(String c) => find.byWidgetPredicate((w) => w is Container && w.constraints?.maxWidth == 30 && (w.decoration as BoxDecoration?)?.color == parseColor(c)).first;

  double scrollPos(WidgetTester t) => t.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;

  test('sanity: la paleta tiene colores fuera de los favoritos', () {
    expect(palette.length, greaterThan(10));
  });

  testWidgets('arrastrar en el cuadrado cambia el color y no scrollea el panel', (t) async {
    await open(t, h: 700); // bajo: el panel tiene scroll
    await t.ensureVisible(find.text('Color personalizado'));
    await t.pumpAndSettle();
    await t.tap(find.text('Color personalizado'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('colorSquare')));
    await t.pumpAndSettle();
    final antes = ts.pen.color;
    final sq = find.byKey(const Key('colorSquare'));
    expect(sq, findsOneWidget);
    final pos0 = scrollPos(t);
    expect(pos0, greaterThan(0));
    await t.tapAt(t.getTopLeft(sq) + const Offset(40, 30));
    await t.pump();
    expect(ts.pen.color, isNot(antes));
    final tras = ts.pen.color;
    await t.drag(sq, const Offset(0, 80));
    await t.pump();
    expect(scrollPos(t), pos0);
    expect(ts.pen.color, isNot(tras));
    // control: fuera del cuadrado el mismo gesto sí scrollea
    await t.drag(find.text('Color personalizado'), const Offset(0, 80));
    await t.pump();
    expect(scrollPos(t), isNot(pos0));
    expect(find.byKey(const Key('colorHex')), findsOneWidget);
    expect(find.byKey(const Key('colorHue')), findsOneWidget);
  });

  testWidgets('Cambiar: la paleta y el selector guardan en el favorito marcado', (t) async {
    await open(t);
    final favs0 = List<String>.from(ts.favorites);
    await t.tap(find.byKey(const Key('favEdit')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('colorSquare')), findsOneWidget);
    final c = paletteColor();
    await t.tap(swatch(c));
    await t.pump();
    expect(ts.favorites[0], c);
    expect(ts.favorites.sublist(1), favs0.sublist(1));
    await t.drag(find.byKey(const Key('colorSquare')), const Offset(30, 40));
    await t.pump();
    expect(ts.favorites[0], ts.pen.color);
    expect(palette.contains(ts.favorites[0]), isFalse);
    await t.tap(find.byKey(const Key('favEdit')));
    await t.pump();
    expect(find.text('Cambiar'), findsOneWidget);
  });

  testWidgets('mantener apretado un favorito lo edita y solo cambia ese', (t) async {
    await open(t);
    final favs0 = List<String>.from(ts.favorites);
    await t.longPress(find.byKey(const ValueKey('panelFav-2')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('colorSquare')), findsOneWidget);
    await t.tapAt(t.getTopLeft(find.byKey(const Key('colorSquare'))) + const Offset(100, 70));
    await t.pump();
    expect(ts.favorites[2], ts.pen.color);
    expect(ts.favorites[2], isNot(favs0[2]));
    for (final i in [0, 1, 3]) {
      expect(ts.favorites[i], favs0[i]);
    }
  });

  testWidgets('sin editar, elegir de la paleta no toca los favoritos', (t) async {
    await open(t);
    final favs0 = List<String>.from(ts.favorites);
    final c = paletteColor();
    await t.tap(swatch(c));
    await t.pump();
    expect(ts.pen.color, c);
    expect(ts.favorites, favs0);
  });

  testWidgets('showPenPanel(editFav: 1) abre editando el 1 con el selector visible', (t) async {
    await open(t, editFav: 1);
    expect(find.byKey(const Key('colorSquare')), findsOneWidget);
    expect(find.text('Listo'), findsOneWidget);
    expect(find.byIcon(Icons.edit), findsOneWidget);
    expect(ts.pen.color, ts.favorites[1]);
  });
}
