import 'dart:io';

import 'package:apuntes/app.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Cuaderno bloqueado con PIN (acciones de la biblioteca). El bloqueo solo se pide al ABRIR (`LibraryScreen._open`):
/// cualquier otra acción que saque el contenido por otro camino lo esquiva. Acá: duplicar.
void main() {
  late Directory root;

  setUp(() async {
    Storage.useIsolates = false;
    root = await Directory.systemTemp.createTemp('apuntes_pin');
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

  testWidgets('duplicar un cuaderno con PIN pide el PIN y la copia queda con el mismo PIN', (t) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(() async {
      final s = Storage(root: root);
      await s.init();
      final nb = Notebook('n1', 'Secreto', pin: hashPin('1234'));
      nb.sheets.add(nb.newSheet());
      final d = NotebookDoc(nb);
      d.texts['t1'] = TextBlock('t1', 90, 44, 800, 'contenido privado');
      await s.saveNotebook(d);
      await s.saveIndex(NotesIndex(notebooks: [nb]));
    });
    await t.pumpWidget(ApuntesApp(root: root));
    for (var i = 0; i < 100 && find.byKey(const Key('nb-Secreto')).evaluate().isEmpty; i++) {
      await settle(t, 100);
    }
    await settle(t, 600);
    await t.longPress(find.byKey(const Key('nb-Secreto')));
    await settle(t, 400);
    await t.tap(find.text('Duplicar'));
    await settle(t, 600);
    // con un PIN equivocado no se copia nada
    await t.enterText(find.byKey(const Key('pinField')), '0000');
    await t.tap(find.byKey(const Key('pinOk')));
    await settle(t, 800);
    expect(find.byKey(const Key('nb-Secreto (copia)')), findsNothing);
    await t.longPress(find.byKey(const Key('nb-Secreto')));
    await settle(t, 400);
    await t.tap(find.text('Duplicar'));
    await settle(t, 600);
    await t.enterText(find.byKey(const Key('pinField')), '1234');
    await t.tap(find.byKey(const Key('pinOk')));
    await settle(t, 3000);
    expect(find.byKey(const Key('nb-Secreto (copia)')), findsOneWidget, reason: 'se creó la copia');

    NotesIndex? idx;
    for (var i = 0; i < 15; i++) {
      await settle(t, 300);
      idx = await t.runAsync(() async {
        final s = Storage(root: root);
        await s.init();
        return s.loadIndex();
      });
      if (idx!.notebooks.length == 2) break;
    }
    expect(idx!.notebooks.length, 2);
    for (final n in idx.notebooks) {
      expect(n.pin, hashPin('1234'), reason: '"${n.name}" tiene que seguir bloqueado: la copia tiene el mismo contenido privado');
    }
  });
}
