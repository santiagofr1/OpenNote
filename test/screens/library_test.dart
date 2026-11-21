import 'dart:io';

import 'package:apuntes/app.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/screens/library/library_drag.dart';
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

  /// Lee el índice del disco. Con [until], reintenta hasta 5 s a que las escrituras en
  /// segundo plano lleguen (en CI el disco es más lento que 300 ms).
  Future<NotesIndex> disk(WidgetTester t, {bool Function(NotesIndex)? until}) => t.runAsync(() async {
        NotesIndex idx;
        var waited = 0;
        do {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          waited += 300;
          final s = Storage(root: root);
          await s.init();
          idx = await s.loadIndex();
        } while (until != null && !until(idx) && waited < 5000);
        return idx;
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
    expect((await disk(t, until: (i) => i.notebooks.firstWhere((n) => n.name == 'Suelto').folder == 'f2'))
        .notebooks.firstWhere((n) => n.name == 'Suelto').folder, 'f2');

    await tap(t, k('folder-Facultad'));
    await tap(t, k('folder-Análisis'));
    await hold(t, k('nb-Suelto'));
    await tap(t, k('moveTo'));
    await tap(t, k('moveTarget-Inicio'));
    expect(k('nb-Suelto'), findsNothing);
    expect((await disk(t, until: (i) => i.notebooks.firstWhere((n) => n.name == 'Suelto').folder == null))
        .notebooks.firstWhere((n) => n.name == 'Suelto').folder, isNull);
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

  group('mover arrastrando', () {
    /// Mantener apretado [from] y llevarlo (de a pasos) hasta [to]; si [drop], lo suelta ahí.
    Future<TestGesture> drag(WidgetTester t, Finder from, Finder to, {bool drop = true}) async {
      final g = await t.startGesture(t.getCenter(from));
      await t.pump(const Duration(milliseconds: 600));
      final a = t.getCenter(from), b = t.getCenter(to);
      for (var i = 1; i <= 8; i++) {
        await g.moveTo(Offset.lerp(a, b, i / 8)!);
        await t.pump(const Duration(milliseconds: 30));
      }
      if (drop) {
        await g.up();
        await settle(t, 600);
      }
      return g;
    }

    testWidgets('soltar un cuaderno sobre una carpeta lo mueve y avisa con Deshacer', (t) async {
      await start(t);
      await drag(t, k('nb-Suelto'), k('folder-Facultad'));
      expect(k('nb-Suelto'), findsNothing, reason: 'ya no está en el inicio');
      expect(find.text('Movido a Inicio / Facultad'), findsOneWidget);
      var idx = await disk(t, until: (i) => i.notebooks.firstWhere((n) => n.id == 'n2').folder == 'f1');
      expect(idx.notebooks.firstWhere((n) => n.id == 'n2').folder, 'f1');

      await t.pump(const Duration(seconds: 1));
      await t.tap(find.text('Deshacer'));
      await settle(t, 600);
      expect(k('nb-Suelto'), findsOneWidget);
      idx = await disk(t, until: (i) => i.notebooks.firstWhere((n) => n.id == 'n2').folder == null);
      expect(idx.notebooks.firstWhere((n) => n.id == 'n2').folder, isNull);
    });

    testWidgets('mantener apretado abre el menú YA, sin soltar; soltar sin mover lo deja abierto', (t) async {
      await start(t);
      final g = await t.startGesture(t.getCenter(k('nb-Suelto')));
      await t.pump(const Duration(milliseconds: 700));
      expect(k('moveTo'), findsOneWidget, reason: 'el menú aparece mientras sigue apretado');
      expect(k('optionsMenu'), findsOneWidget);
      await g.up();
      await settle(t, 600);
      expect(k('moveTo'), findsOneWidget, reason: 'soltar sin mover lo deja abierto');
      expect(find.textContaining('Movido'), findsNothing);
      await t.tap(find.text('Renombrar'));
      await settle(t, 600);
      expect(find.byType(TextField), findsWidgets, reason: 'tocar una opción anda normal');
    });

    testWidgets('con el menú abierto, mover más de 10 px lo cierra y arrastra', (t) async {
      await start(t);
      final g = await t.startGesture(t.getCenter(k('nb-Suelto')));
      await t.pump(const Duration(milliseconds: 700));
      expect(k('moveTo'), findsOneWidget);
      final a = t.getCenter(k('nb-Suelto')), b = t.getCenter(k('folder-Facultad'));
      for (var i = 1; i <= 8; i++) {
        await g.moveTo(Offset.lerp(a, b, i / 8)!);
        await t.pump(const Duration(milliseconds: 30));
      }
      expect(k('moveTo'), findsNothing, reason: 'el menú se cerró al moverse');
      await g.up();
      await settle(t, 600);
      expect(find.text('Movido a Inicio / Facultad'), findsOneWidget);
      expect(k('moveTo'), findsNothing);
    });

    testWidgets('el menú se cierra tocando afuera y con atrás (sin salir de la pantalla)', (t) async {
      await start(t);
      await hold(t, k('nb-Suelto'));
      expect(k('moveTo'), findsOneWidget);
      await t.tapAt(const Offset(5, 5));
      await settle(t, 400);
      expect(k('moveTo'), findsNothing);
      expect(k('nb-Suelto'), findsOneWidget);

      await hold(t, k('folder-Facultad'));
      expect(k('moveTo'), findsOneWidget);
      await t.binding.handlePopRoute();
      await settle(t, 400);
      expect(k('moveTo'), findsNothing);
      expect(k('nb-Suelto'), findsOneWidget);
    });

    testWidgets('soltar en cualquier otro lado no mueve nada', (t) async {
      await start(t);
      final g = await drag(t, k('nb-Suelto'), k('folder-Facultad'), drop: false);
      await g.moveBy(const Offset(0, 300));
      await t.pump(const Duration(milliseconds: 50));
      await g.up();
      await settle(t, 600);
      expect(find.textContaining('Movido'), findsNothing);
      expect(k('nb-Suelto'), findsOneWidget);
      expect(k('moveTo'), findsNothing, reason: 'tampoco abre el menú: se movió');
    });

    testWidgets('soltar una carpeta sobre las migas la sube; sobre Inicio la saca de todo', (t) async {
      await start(t);
      await tap(t, k('folder-Facultad'));
      await drag(t, k('folder-Análisis'), k('crumb-inicio'));
      expect(find.text('Movida a Inicio'), findsOneWidget);
      expect(k('folder-Análisis'), findsNothing);
      final idx = await disk(t, until: (i) => i.folderById('f2')!.parent == null);
      expect(idx.folderById('f2')!.parent, isNull);
      await t.pump(const Duration(seconds: 1)); // que termine de entrar el aviso
      await t.tap(find.text('Deshacer'));
      await settle(t, 600);
      expect(k('folder-Análisis'), findsOneWidget, reason: 'volvió a Facultad');
    });

    testWidgets('una carpeta no se puede soltar adentro de sí misma ni de una hija', (t) async {
      await start(t);
      // Facultad sobre sí misma: no hay destino
      await drag(t, k('folder-Facultad'), k('folder-Facultad'));
      expect(find.textContaining('Movida'), findsNothing);
      final idx = await disk(t);
      expect(idx.folderById('f1')!.parent, isNull);
      // la lógica pura también lo rechaza
      final d = LibraryDrag.folder(idx.folderById('f1')!);
      expect(d.canDropOn(idx, 'f2'), isFalse, reason: 'hija');
      expect(d.canDropOn(idx, 'f1'), isFalse, reason: 'sí misma');
      expect(d.canDropOn(idx, null), isFalse, reason: 'ya está en el inicio');
    });

    testWidgets('el scroll no se rompe: arrastrar el fondo con el dedo sigue siendo scroll', (t) async {
      await start(t, size: const Size(600, 500));
      final sc = t.state<ScrollableState>(find.byType(Scrollable).first);
      await t.drag(find.byType(CustomScrollView), const Offset(0, -200));
      await t.pump();
      expect(sc.position.pixels, greaterThanOrEqualTo(0));
      expect(find.textContaining('Movido'), findsNothing);
    });
  });
}
