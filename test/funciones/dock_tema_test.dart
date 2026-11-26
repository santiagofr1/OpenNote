import 'dart:io';
import 'dart:math';

import 'package:apuntes/app.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/editor/dock_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../helpers/l10n_app.dart';

/// Barra acoplable (arriba / izquierda / derecha) y tema claro / oscuro.
void main() {
  group('barra acoplable', () {
    /// Un lienzo con estado propio: cuenta cuántas veces se creó (si la barra cambia de lugar o se esconde el modo
    /// lectura, lo que se está escribiendo en el lienzo no se tiene que perder).
    var lienzosCreados = 0;

    Widget montar({required String dock, bool oculta = false, required void Function(String) onDock, required List<bool> verticales}) => l10nApp(
          SizedBox(
            width: 800,
            height: 600,
            child: DockLayout(
              dock: dock,
              hideToolbar: oculta,
              canvas: const _Lienzo(),
              toolbar: (vertical, grip) {
                verticales.add(vertical);
                return Container(key: const Key('barra'), color: Colors.blue, child: grip);
              },
              onDock: onDock,
            ),
          ),
        );

    setUp(() => lienzosCreados = 0);
    _Lienzo.onCreate = () => lienzosCreados++;

    testWidgets('arriba la barra es horizontal; a los costados, vertical; el lienzo ocupa lo que queda', (t) async {
      for (final dock in ['top', 'left', 'right']) {
        final v = <bool>[];
        await t.pumpWidget(montar(dock: dock, onDock: (_) {}, verticales: v));
        await t.pump(const Duration(milliseconds: 400));
        expect(v.last, dock != 'top', reason: dock);
        final barra = t.getRect(find.byKey(const Key('barra'))), lienzo = t.getRect(find.byType(_Lienzo));
        expect(barra.overlaps(lienzo), isFalse, reason: '$dock: la barra no tapa el lienzo');
        switch (dock) {
          case 'top':
            expect(barra.bottom, lessThanOrEqualTo(lienzo.top + 1e-6));
          case 'left':
            expect(barra.right, lessThanOrEqualTo(lienzo.left + 1e-6));
          default:
            expect(lienzo.right, lessThanOrEqualTo(barra.left + 1e-6));
        }
      }
    });

    testWidgets('modo lectura: no hay barra y el lienzo ocupa todo', (t) async {
      await t.pumpWidget(montar(dock: 'top', oculta: true, onDock: (_) {}, verticales: []));
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('barra')), findsNothing);
      expect(t.getSize(find.byType(_Lienzo)), const Size(800, 600));
    });

    testWidgets('BUG sospechado: entrar y salir del modo lectura no reconstruye el lienzo (lo dice el comentario de DockLayout)', (t) async {
      for (final dock in ['top', 'left']) {
        lienzosCreados = 0;
        await t.pumpWidget(montar(dock: dock, onDock: (_) {}, verticales: []));
        await t.pump(const Duration(milliseconds: 400));
        expect(lienzosCreados, 1);
        await t.pumpWidget(montar(dock: dock, oculta: true, onDock: (_) {}, verticales: []));
        await t.pump(const Duration(milliseconds: 400));
        await t.pumpWidget(montar(dock: dock, onDock: (_) {}, verticales: []));
        await t.pump(const Duration(milliseconds: 400));
        expect(lienzosCreados, 1, reason: '$dock: el lienzo se creó de nuevo ($lienzosCreados veces): se pierde lo que tenía adentro');
      }
    });

    testWidgets('arrastrar la agarradera a cualquier lado de la pantalla acopla donde corresponde (propiedad, semilla 1)', (t) async {
      final r = Random(1);
      final elegidos = <String>[];
      await t.pumpWidget(montar(dock: 'top', onDock: elegidos.add, verticales: []));
      await t.pump(const Duration(milliseconds: 400));
      final origen = t.getCenter(find.byIcon(Symbols.drag_indicator));
      final caja = t.getTopLeft(find.byType(DockLayout));
      var n = 0;
      for (var i = 0; i < 60; i++) {
        final destino = caja + Offset(r.nextDouble() * 800, r.nextDouble() * 600);
        if ((destino - origen).distance < 60) continue; // un arrastre muy corto no es un arrastre
        elegidos.clear();
        final g = await t.startGesture(origen);
        for (var s = 1; s <= 6; s++) {
          await g.moveTo(Offset.lerp(origen, destino, s / 6)!);
          await t.pump(const Duration(milliseconds: 16));
        }
        await g.up();
        await t.pump(const Duration(milliseconds: 100));
        final p = destino - caja;
        final esperado = (p.dy < 600 * .22 && p.dx > 800 * .2 && p.dx < 800 * .8) ? 'top' : (p.dx < 400 ? 'left' : 'right');
        expect(elegidos, [esperado], reason: 'soltó en $p');
        n++;
      }
      expect(n, greaterThan(30), reason: 'que la propiedad no sea vacía');
    });

    testWidgets('un arrastre cancelado (el sistema se queda con el gesto) no cambia de lugar la barra y no deja la vista previa', (t) async {
      final elegidos = <String>[];
      await t.pumpWidget(montar(dock: 'top', onDock: elegidos.add, verticales: []));
      await t.pump(const Duration(milliseconds: 400));
      final origen = t.getCenter(find.byIcon(Symbols.drag_indicator));
      final g = await t.startGesture(origen);
      await g.moveTo(origen + const Offset(-300, 200));
      await t.pump(const Duration(milliseconds: 50));
      await g.cancel();
      await t.pump(const Duration(milliseconds: 400));
      expect(elegidos, isEmpty);
      expect(find.byType(IgnorePointer), findsWidgets); // (el widget sigue sano)
      expect(t.takeException(), isNull);
    });

    testWidgets('tocar la agarradera sin arrastrar no cambia nada', (t) async {
      final elegidos = <String>[];
      await t.pumpWidget(montar(dock: 'left', onDock: elegidos.add, verticales: []));
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.byIcon(Symbols.drag_indicator));
      await t.pump(const Duration(milliseconds: 400));
      expect(elegidos, isEmpty);
    });
  });

  group('tema claro y oscuro', () {
    late Directory root;
    setUp(() async {
      Storage.useIsolates = false;
      root = await Directory.systemTemp.createTemp('apuntes_tema');
    });
    tearDown(() async {
      Storage.useIsolates = true;
      if (await root.exists()) await root.delete(recursive: true);
    });

    Future<void> settle(WidgetTester t, [int ms = 600]) async {
      for (var i = 0; i < ms ~/ 100; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    for (final b in [Brightness.light, Brightness.dark]) {
      testWidgets('la biblioteca y un cuaderno se abren en modo ${b.name}: fondo del lado que corresponde, sin errores ni desbordes', (t) async {
        t.view.physicalSize = const Size(1600, 1000);
        t.view.devicePixelRatio = 1;
        t.platformDispatcher.platformBrightnessTestValue = b;
        addTearDown(t.view.reset);
        addTearDown(t.platformDispatcher.clearPlatformBrightnessTestValue);
        await t.pumpWidget(ApuntesApp(root: root));
        await settle(t, 1500);
        expect(find.text('Cuadernos'), findsOneWidget);
        final fondo = t.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor ?? Theme.of(t.element(find.byType(Scaffold).first)).colorScheme.surface;
        expect(fondo.computeLuminance() < .5, b == Brightness.dark, reason: 'fondo $fondo en modo ${b.name}');
        final cs = Theme.of(t.element(find.byType(Scaffold).first)).colorScheme;
        expect(cs.brightness, b);
        // el texto se lee sobre cada fondo (contraste WCAG >= 4.5)
        double contraste(Color x, Color y) {
          final a = x.computeLuminance() + .05, c = y.computeLuminance() + .05;
          return max(a, c) / min(a, c);
        }

        for (final (nombre, primero, segundo) in [
          ('onSurface/surface', cs.onSurface, cs.surface),
          ('onPrimary/primary', cs.onPrimary, cs.primary),
          ('onSurfaceVariant/surfaceContainerHigh', cs.onSurfaceVariant, cs.surfaceContainerHigh),
          ('onPrimaryContainer/primaryContainer', cs.onPrimaryContainer, cs.primaryContainer),
          ('onError/error', cs.onError, cs.error),
        ]) {
          expect(contraste(primero, segundo), greaterThanOrEqualTo(4.5), reason: '$nombre en ${b.name}');
        }
        await t.tap(find.byKey(const Key('new')));
        await settle(t);
        await t.tap(find.byKey(const Key('newFolder')));
        await settle(t);
        await t.enterText(find.byKey(const Key('askText')), 'Oscura');
        await t.tap(find.byKey(const Key('askOk')));
        await settle(t);
        expect(find.byKey(const Key('folder-Oscura')), findsOneWidget);
        expect(t.takeException(), isNull);
      });
    }

  });
}

class _Lienzo extends StatefulWidget {
  const _Lienzo();
  static void Function()? onCreate;
  @override
  State<_Lienzo> createState() => _LienzoState();
}

class _LienzoState extends State<_Lienzo> {
  @override
  void initState() {
    super.initState();
    _Lienzo.onCreate?.call();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand(child: ColoredBox(color: Colors.white));
}
