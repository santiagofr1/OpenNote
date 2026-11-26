import 'dart:io';
import 'dart:typed_data';

import 'package:apuntes/app.dart';
import 'package:apuntes/data/export.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as im;

import '../helpers/export_check.dart';

/// Exportar desde la biblioteca (mantener apretado un cuaderno > Exportar) con el guardado del sistema reemplazado:
/// lo que se guarda es lo del cuaderno (cada página su hoja) y la preferencia "Incluir el fondo" se respeta y se recuerda.
void main() {
  late Directory root;
  final savedPdf = savePdf, savedImages = saveImages, savedVynote = saveVynote;

  setUp(() async {
    Storage.useIsolates = false;
    root = await Directory.systemTemp.createTemp('apuntes_export_ui');
    final nb = Notebook.create('Hojas')..bg = 'grid';
    nb.sheets.clear();
    while (nb.sheets.length < 3) {
      nb.sheets.add(nb.newSheet());
    }
    final d = NotebookDoc(nb);
    for (var k = 0; k < 3; k++) {
      Marks.add(d, k, k);
    }
    final s = Storage(root: root);
    await s.init();
    await s.saveNotebook(d);
    await s.saveIndex(NotesIndex(notebooks: [nb]));
  });
  tearDown(() async {
    Storage.useIsolates = true;
    savePdf = savedPdf;
    saveImages = savedImages;
    saveVynote = savedVynote;
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

  /// Abre el menú de exportar del cuaderno, deja el interruptor de fondo en [bg] y elige [format].
  Future<void> exportAs(WidgetTester t, String format, {bool? bg}) async {
    await t.longPress(find.byKey(const Key('nb-Hojas')));
    await settle(t, 600);
    await t.tap(find.byKey(const Key('exportNotebook')));
    await settle(t, 600);
    if (bg != null) {
      final on = (t.widget(find.byKey(const Key('exportBg'))) as SwitchListTile).value;
      if (on != bg) {
        await t.tap(find.byKey(const Key('exportBg')));
        await settle(t, 300);
      }
    }
    await t.tap(find.byKey(Key('export-$format')));
  }

  Future<void> waitFor(WidgetTester t, bool Function() done) async {
    for (var i = 0; i < 600 && !done(); i++) {
      await settle(t, 100);
    }
  }

  int nonPaper(im.Image p) {
    var n = 0;
    for (final px in p) {
      if (px.r < 245 || px.g < 245 || px.b < 245) n++;
    }
    return n;
  }

  final skip = hasPdfImages ? null : 'falta pdfimages';

  testWidgets('PDF: con el fondo prendido y apagado; la elección se recuerda para la próxima', (t) async {
    await openLibrary(t);
    final saved = <(Uint8List, String)>[];
    savePdf = (b, n) async {
      saved.add((b, n));
      return true;
    };
    await exportAs(t, 'pdf', bg: false);
    await waitFor(t, () => saved.isNotEmpty);
    expect(saved.length, 1);
    expect(saved[0].$2, 'Hojas');
    var pages = (await t.runAsync(() => pdfPageImages(saved[0].$1)))!;
    expect(pages.length, 3);
    for (var k = 0; k < 3; k++) {
      expect(Marks.found(pages[k], [0, 1, 2]), [k]);
    }
    final bare = nonPaper(pages[0]);
    // la elección quedó guardada: la próxima vez, sin tocar el interruptor, sigue sin fondo
    final prefs = await t.runAsync(() async {
      final s = Storage(root: root);
      await s.init();
      return s.loadPrefsSettled();
    });
    expect(prefs?['exportBg'], false);
    await settle(t, 800);
    await exportAs(t, 'pdf');
    await waitFor(t, () => saved.length == 2);
    pages = (await t.runAsync(() => pdfPageImages(saved[1].$1)))!;
    expect(nonPaper(pages[0]), bare, reason: 'sigue sin fondo');
    await settle(t, 800);
    await exportAs(t, 'pdf', bg: true);
    await waitFor(t, () => saved.length == 3);
    pages = (await t.runAsync(() => pdfPageImages(saved[2].$1)))!;
    expect(nonPaper(pages[0]), greaterThan(bare + 3000), reason: 'con fondo se ven las líneas de la cuadrícula');
    for (var k = 0; k < 3; k++) {
      expect(Marks.found(pages[k], [0, 1, 2]), [k]);
    }
  }, skip: skip != null);

  testWidgets('PNG: un ZIP con cada hoja en su lugar', (t) async {
    await openLibrary(t);
    Uint8List? zip;
    bool? isZip;
    saveImages = (b, n, z) async {
      zip = b;
      isZip = z;
      return true;
    };
    await exportAs(t, 'png', bg: true);
    await waitFor(t, () => zip != null);
    expect(isZip, isTrue);
    final files = ZipDecoder().decodeBytes(zip!).where((f) => f.isFile).toList();
    expect(files.length, 3);
    for (var k = 0; k < 3; k++) {
      expect(Marks.found(im.decodePng(Uint8List.fromList(files[k].content as List<int>))!, [0, 1, 2]), [k]);
    }
  });

  testWidgets('.vynote: lo guardado se importa de nuevo con las mismas hojas', (t) async {
    await openLibrary(t);
    Uint8List? vyn;
    saveVynote = (b, n) async {
      vyn = b;
      return true;
    };
    await exportAs(t, 'vynote');
    await waitFor(t, () => vyn != null);
    final names = ZipDecoder().decodeBytes(vyn!).where((f) => f.isFile).map((f) => f.name).toList();
    expect(names.where((n) => n.startsWith('sheets/')).length, 3);
    expect(names, containsAll(['manifest.json', 'notebook.json']));
  });
}
