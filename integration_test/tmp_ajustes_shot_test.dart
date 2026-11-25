// TEMPORAL: captura de la pantalla de Ajustes (se borra después).
import 'dart:io';

import 'package:apuntes/app.dart';
import 'package:apuntes/data/storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide testWidgets;
import 'package:integration_test/integration_test.dart';

import 'tablet_sim.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('captura de Ajustes', (t) async {
    forceSpanish(t);
    simulateTablet(t);
    await loadRoboto();
    final root = await Directory.systemTemp.createTemp('apuntes_ajustes');
    addTearDown(() async {
      await Storage.settleWrites();
      if (await root.exists()) await root.delete(recursive: true);
    });
    await t.pumpWidget(ApuntesApp(root: root));
    for (var i = 0; i < 30; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.tap(find.byKey(const Key('libraryMenu')));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.tap(find.byKey(const Key('settingsMenu')));
    for (var i = 0; i < 20; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    await saveShot(t, '${Directory.current.path}/tmp_ajustes.png');
  });
}
