// Captura de la app de PC (Linux) para el README: la misma biblioteca de ejemplo, con la sincronización conectada
// (remoto y cuenta de mentira, nunca el Google real). Se corre con tool/screenshot_pc.sh: abre el cuaderno
// "Física – Óptica", imprime `PCSHOT READY` y se queda quieto 20 s para que el script capture la ventana.

import 'dart:io';

import 'package:apuntes/app.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/sync/fake_backend.dart';
import 'package:apuntes/sync/fake_remote_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'screenshots_data.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester t, [int ms = 400]) async {
    for (var i = 0; i < ms ~/ 50; i++) {
      await t.pump(const Duration(milliseconds: 50));
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  testWidgets('captura de PC del README', (t) async {
    await t.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final root = await Directory.systemTemp.createTemp('apuntes_capturas_pc');
    try {
      final s = Storage(root: root);
      await s.init();
      await seedLibrary(s);

      final backend = FakeBackend(FakeRemoteStore(), account: 'ana@example.com');
      await backend.signIn();
      await t.pumpWidget(ApuntesApp(root: root, backend: backend));
      await settle(t, 3000);
      await t.tap(find.byKey(Key('nb-$nbPhysics')));
      await settle(t, 3500);
      for (var i = 0; i < 40 && find.byKey(const Key('syncIndicator')).evaluate().isEmpty; i++) {
        await settle(t, 100);
      }
      await settle(t, 3000); // que termine de sincronizar
      // ignore: avoid_print
      print('PCSHOT READY');
      // el reloj de pared (no el de los fotogramas) para que la ventana quede quieta y visible 20 s
      for (var i = 0; i < 200; i++) {
        await t.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await t.tap(find.byKey(const Key('back')));
      await settle(t, 1200);
    } finally {
      if (await root.exists()) await root.delete(recursive: true);
    }
  });
}
