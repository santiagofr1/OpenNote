import 'dart:io';

import 'package:apuntes/app.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// La biblioteca con carpetas: navegar, crear, mover, borrar y buscar (Storage real en una carpeta temporal).
void main() {
  late Directory root;

  setUp(() async {
    Storage.useIsolates = false;
    root = await Directory.systemTemp.createTemp('apuntes_library');
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

  // Inicio ─ Facultad ─ Análisis (cuaderno "Álgebra" en Facultad)
  //        └ cuaderno "Suelto"
  Future<void> seed() async {
    final fac = Folder('f1', 'Facultad');
    final ana = Folder('f2', 'Análisis', parent: 'f1');
    final idx = NotesIndex(notebooks: [Notebook('n1', 'Álgebra', folder: 'f1'), Notebook('n2', 'Suelto')], folders: [fac, ana]);
    await Future(() async {
      final s = Storage(root: root);
      await s.init();
      await s.saveIndex(idx);
    });
  }

  Future<void> start(WidgetTester t, {Size size = const Size(1600, 1000), double keyboard = 0}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    if (keyboard > 0) t.view.viewInsets = FakeViewPadding(bottom: keyboard);
    addTearDown(t.view.reset);
    await t.runAsync(seed);
    await t.pumpWidget(ApuntesApp(root: root));
    for (var i = 0; i < 100 && find.byKey(const Key('folder-Facultad')).evaluate().isEmpty; i++) {
      await settle(t, 100);
    }
    await settle(t, 600); // que termine la entrada del botón "+"
  }

  Future<NotesIndex> disk(WidgetTester t) => t.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300)); // que terminen las escrituras
        final s = Storage(root: root);
        await s.init();
        return s.loadIndex();
      }).then((v) => v!);

  Finder k(String key) => find.byKey(Key(key));
  Future<void> tap(WidgetTester t, Finder f) async {
    await t.tap(f);
    await settle(t, 600);
  }

  Future<void> hold(WidgetTester t, Finder f) async {
    await t.longPress(f);
    await settle(t, 400);
  }

  testWidgets('navegar: entrar a una carpeta, subir con la flecha, con las migas y con atrás', (t) async {
    await start(t);
    expect(k('folder-Facultad'), findsOneWidget);
    expect(k('nb-Suelto'), findsOneWidget);
    expect(k('nb-Álgebra'), findsNothing, reason: 'está adentro de Facultad');
    expect(k('folder-Análisis'), findsNothing);
    expect(find.text('1 cuaderno'), findsOneWidget, reason: 'cuenta de la carpeta');

    await tap(t, k('folder-Facultad'));
    expect(k('nb-Álgebra'), findsOneWidget);
    expect(k('folder-Análisis'), findsOneWidget);
    expect(k('nb-Suelto'), findsNothing);
    expect(k('up'), findsOneWidget);

    await tap(t, k('folder-Análisis'));
    expect(k('crumb-Facultad'), findsOneWidget);
    await tap(t, k('crumb-Facultad'));
    expect(k('nb-Álgebra'), findsOneWidget);

    await tap(t, k('up'));
    expect(k('nb-Suelto'), findsOneWidget);
    expect(k('up'), findsNothing);

    // atrás del sistema: sube de a un nivel antes de salir
    await tap(t, k('folder-Facultad'));
    await tap(t, k('folder-Análisis'));
    await t.binding.handlePopRoute();
    await settle(t, 300);
    expect(k('nb-Álgebra'), findsOneWidget);
    await t.binding.handlePopRoute();
    await settle(t, 300);
    expect(k('nb-Suelto'), findsOneWidget);
  });

  testWidgets('crear una carpeta nueva en la carpeta actual', (t) async {
    await start(t);
    await tap(t, k('folder-Facultad'));
    await tap(t, k('new'));
    await tap(t, k('newFolder'));
    await t.enterText(k('askText'), 'Parciales');
    await tap(t, k('askOk'));
    expect(k('folder-Parciales'), findsOneWidget);
    await tap(t, k('up'));
    expect(k('folder-Parciales'), findsNothing, reason: 'se creó adentro de Facultad');
    final idx = await disk(t);
    expect(idx.folders.firstWhere((f) => f.name == 'Parciales').parent, 'f1');
  });

  testWidgets('mover un cuaderno a una carpeta y de vuelta al inicio', (t) async {
    await start(t);
    await hold(t, k('nb-Suelto'));
    await tap(t, k('moveTo'));
    expect(k('moveTarget-Inicio'), findsOneWidget);
    expect(k('moveTarget-Análisis'), findsOneWidget, reason: 'el árbol muestra las subcarpetas');
    await tap(t, k('moveTarget-Análisis'));
    expect(k('nb-Suelto'), findsNothing);
    expect((await disk(t)).notebooks.firstWhere((n) => n.name == 'Suelto').folder, 'f2');

    await tap(t, k('folder-Facultad'));
    await tap(t, k('folder-Análisis'));
    await hold(t, k('nb-Suelto'));
    await tap(t, k('moveTo'));
    await tap(t, k('moveTarget-Inicio'));
    expect(k('nb-Suelto'), findsNothing);
    expect((await disk(t)).notebooks.firstWhere((n) => n.name == 'Suelto').folder, isNull);
  });

  testWidgets('carpeta: renombrar, mover (no entra en sí misma) y borrar sacando los cuadernos', (t) async {
    await start(t);
    await hold(t, k('folder-Facultad'));
    await tap(t, find.text('Renombrar'));
    await t.enterText(k('askText'), 'Uni');
    await tap(t, k('askOk'));
    expect(k('folder-Uni'), findsOneWidget);

    await hold(t, k('folder-Uni'));
    await tap(t, k('moveTo'));
    expect(k('moveTarget-Uni'), findsOneWidget);
    expect(k('moveTarget-Análisis'), findsNothing, reason: 'una carpeta no se mueve adentro de sus hijas');
    await tap(t, find.text('Cancelar'));

    await hold(t, k('folder-Uni'));
    await tap(t, find.text('Borrar'));
    expect(find.text('Sacar los cuadernos a Inicio'), findsOneWidget);
    await tap(t, k('folderKeep'));
    expect(k('folder-Uni'), findsNothing);
    expect(k('folder-Análisis'), findsOneWidget, reason: 'las subcarpetas suben al inicio');
    expect(k('nb-Álgebra'), findsOneWidget);
    final idx = await disk(t);
    expect(idx.folders.single.parent, isNull);
    expect(idx.notebooks.length, 2);
  });

  testWidgets('borrar todo pide una segunda confirmación', (t) async {
    await start(t);
    await hold(t, k('folder-Facultad'));
    await tap(t, find.text('Borrar'));
    await tap(t, k('folderDeleteAll'));
    expect(k('confirmDelete'), findsOneWidget);
    await tap(t, find.text('Cancelar'));
    expect(k('folder-Facultad'), findsOneWidget, reason: 'cancelado: no se borró nada');

    await hold(t, k('folder-Facultad'));
    await tap(t, find.text('Borrar'));
    await tap(t, k('folderDeleteAll'));
    await tap(t, k('confirmDelete'));
    expect(k('folder-Facultad'), findsNothing);
    expect(k('nb-Suelto'), findsOneWidget);
    final idx = await disk(t);
    expect(idx.folders, isEmpty);
    expect(idx.notebooks.map((n) => n.name), ['Suelto']);
  });

  testWidgets('buscar: en todas las carpetas, sin tildes ni mayúsculas, con la ruta; limpiar vuelve', (t) async {
    await start(t);
    await tap(t, k('folder-Facultad'));
    await tap(t, k('folder-Análisis'));
    await t.enterText(k('librarySearch'), 'ALGEBRA');
    await settle(t, 300);
    expect(k('nb-Álgebra'), findsOneWidget, reason: 'busca en todo, no solo en la carpeta actual');
    expect(find.text('Inicio / Facultad'), findsOneWidget, reason: 'ruta como subtítulo');
    expect(k('nb-Suelto'), findsNothing);

    await t.enterText(k('librarySearch'), 'analisis');
    await settle(t, 300);
    expect(k('folder-Análisis'), findsOneWidget);
    expect(find.text('Inicio / Facultad'), findsOneWidget);

    await t.enterText(k('librarySearch'), 'zzz');
    await settle(t, 300);
    expect(find.text('Sin resultados'), findsOneWidget);

    await tap(t, k('librarySearchClear'));
    expect(find.text('Esta carpeta está vacía'), findsOneWidget, reason: 'volvió a la carpeta actual (Análisis)');
    expect(k('crumb-Facultad'), findsOneWidget);
  });

  // Hojas y diálogos de la biblioteca: sin desbordes en vertical, horizontal y con el teclado abierto.
  for (final (name, size, kb) in [
    ('vertical', const Size(800, 1333), 0.0),
    ('horizontal', const Size(1333, 800), 0.0),
    ('vertical con teclado', const Size(800, 1333), 300.0),
    ('horizontal con teclado', const Size(1333, 800), 300.0),
  ]) {
    testWidgets('hojas y diálogos sin desbordes: $name', (t) async {
      await start(t, size: size, keyboard: kb);
      expect(t.takeException(), isNull, reason: 'la biblioteca sola');

      Future<void> step(String what) async {
        await settle(t, 400);
        expect(t.takeException(), isNull, reason: what);
      }

      Future<void> close() async {
        await t.tapAt(const Offset(2, 2)); // fuera de la hoja o diálogo
        await settle(t, 400);
        if (find.text('Cancelar').evaluate().isNotEmpty) await t.tap(find.text('Cancelar'));
        await settle(t, 400);
      }

      await t.tap(k('new'));
      await step('hoja "Nuevo"');
      await t.tap(k('newFolder'));
      await step('diálogo carpeta nueva');
      await close();

      await t.longPress(k('nb-Suelto'));
      await step('opciones de cuaderno');
      await t.tap(k('moveTo'));
      await step('mover cuaderno');
      await close();

      await t.longPress(k('folder-Facultad'));
      await step('opciones de carpeta');
      await t.tap(find.text('Renombrar'));
      await step('renombrar con teclado');
      await close();

      await t.longPress(k('folder-Facultad'));
      await settle(t, 400);
      await t.tap(k('moveTo'));
      await step('mover carpeta');
      await close();

      await t.longPress(k('folder-Facultad'));
      await settle(t, 400);
      await t.tap(find.text('Borrar'));
      await step('borrar carpeta');
      await t.tap(k('folderDeleteAll'));
      await step('confirmar borrar todo');
    });
  }
}
