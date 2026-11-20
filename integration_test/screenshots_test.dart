// Capturas de la app para el README, con datos de ejemplo en una carpeta temporal (nunca tus cuadernos).
// Se corre con tool/screenshots.sh (usa `flutter drive`; los PNG quedan en docs/img/).

import 'dart:io';

import 'package:apuntes/app.dart';
import 'package:apuntes/data/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'screenshots_data.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester t, [int ms = 400]) async {
    for (var i = 0; i < ms ~/ 50; i++) {
      await t.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  testWidgets('capturas del README', (t) async {
    final root = await Directory.systemTemp.createTemp('apuntes_capturas');
    try {
      final s = Storage(root: root);
      await s.init();
      await seedLibrary(s);

      await t.pumpWidget(ApuntesApp(root: root));
      await settle(t, 3000); // que carguen las miniaturas

      // en Android hay que pasar la superficie a imagen una sola vez, antes de la primera captura
      await binding.convertFlutterSurfaceToImage();
      await t.pump();
      await settle(t, 600);

      Future<void> shot(String name) async {
        await t.pump();
        await binding.takeScreenshot(name);
      }

      await shot('03_biblioteca');

      await t.tap(find.byKey(const Key('nb-Física – Óptica')));
      await settle(t, 3500);
      await shot('01_cuaderno');

      await t.tap(find.byKey(const Key('pagesBtn')));
      await settle(t, 1500);
      expect(find.byKey(const Key('pagesPanel')), findsOneWidget);
      await shot('02_panel_hojas');

      // salir: que el guardado termine antes de borrar la carpeta
      await t.tap(find.byKey(const Key('back')));
      await settle(t, 1200);
    } finally {
      if (await root.exists()) await root.delete(recursive: true);
    }
  });
}
