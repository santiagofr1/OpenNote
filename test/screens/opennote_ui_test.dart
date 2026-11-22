import 'dart:io';
import 'dart:typed_data';

import 'package:apuntes/app.dart';
import 'package:apuntes/data/export.dart';
import 'package:apuntes/data/media_import.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exportar (mantener apretado un cuaderno) e importar ("+") archivos `.opennote` desde la biblioteca.
void main() {
  late Directory root;
  final savedPickers = Pickers.opennote, savedSave = saveOpennote;

  setUp(() async {
    Storage.useIsolates = false;
    root = await Directory.systemTemp.createTemp('apuntes_opennote_ui');
    final nb = Notebook.create('Hojas');
    nb.sheets.add(nb.newSheet());
    final d = NotebookDoc(nb);
    d.texts['t0'] = TextBlock('t0', 90, 44, 800, 'hola');
    final s = Storage(root: root);
    await s.init();
    await s.saveNotebook(d);
    await s.saveIndex(NotesIndex(notebooks: [nb]));
  });
  tearDown(() async {
    Storage.useIsolates = true;
    Pickers.opennote = savedPickers;
    saveOpennote = savedSave;
    await root.delete(recursive: true);
  });

  Future<void> settle(WidgetTester t, [int ms = 600]) async {
    for (var i = 0; i < ms ~/ 100; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> openLibrary(WidgetTester t) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ApuntesApp(root: root));
    for (var i = 0; i < 50 && find.byKey(const Key('nb-Hojas')).evaluate().isEmpty; i++) {
      await settle(t, 100);
    }
    await settle(t, 800);
  }

  testWidgets('exportar desde la biblioteca y volver a importar: el cuaderno nuevo es otro, con "(importado)"', (t) async {
    await openLibrary(t);
    Uint8List? saved;
    String? savedName;
    saveOpennote = (bytes, name) async {
      saved = bytes;
      savedName = name;
      return true;
    };
    await t.longPress(find.byKey(const Key('nb-Hojas')));
    await settle(t, 600);
    await t.tap(find.byKey(const Key('exportNotebook')));
    await settle(t, 600);
    await t.tap(find.byKey(const Key('export-opennote')));
    for (var i = 0; i < 30 && saved == null; i++) {
      await settle(t, 100);
    }
    expect(saved, isNotNull);
    expect(savedName, 'Hojas');

    Pickers.opennote = () async => saved;
    await t.tap(find.byKey(const Key('new')));
    await settle(t, 600);
    await t.tap(find.byKey(const Key('importNotebook')));
    for (var i = 0; i < 50 && find.byKey(const Key('nb-Hojas (importado)')).evaluate().isEmpty; i++) {
      await settle(t, 100);
    }
    expect(find.byKey(const Key('nb-Hojas (importado)')), findsOneWidget);
    expect(find.byKey(const Key('nb-Hojas')), findsOneWidget);
    final idx = await t.runAsync(() async {
      final s = Storage(root: root);
      await s.init();
      return s.loadIndex();
    });
    expect(idx!.notebooks.length, 2);
    expect(idx.notebooks[0].id, isNot(idx.notebooks[1].id));
  });

  testWidgets('un archivo roto se rechaza con un aviso y no agrega nada', (t) async {
    await openLibrary(t);
    Pickers.opennote = () async => Uint8List.fromList([1, 2, 3]);
    await t.tap(find.byKey(const Key('new')));
    await settle(t, 600);
    await t.tap(find.byKey(const Key('importNotebook')));
    await settle(t, 1000);
    expect(find.textContaining('No se pudo importar'), findsOneWidget);
    expect(find.byKey(const Key('nb-Hojas (importado)')), findsNothing);
  });
}
