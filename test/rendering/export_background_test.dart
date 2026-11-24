import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/rendering/sheet_render.dart';
import 'package:apuntes/screens/notebook/menus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exportar con o sin fondo de hoja (issue #39).
void main() {
  NotebookDoc sample(String bg, {String? image}) {
    final nb = Notebook.create('Fondo');
    nb.sheets[0]
      ..bg = bg
      ..paper = '#fbf3e0'
      ..image = image;
    return NotebookDoc(nb);
  }

  /// Pinta la hoja 0 a 0.5 px por unidad y devuelve los bytes RGBA.
  Future<List<int>> pixels(NotebookDoc d, bool background, {Map<String, ui.Image>? images}) async {
    const k = .5;
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec)..scale(k);
    paintSheet(c, d, 0, k, images: images, background: background);
    final img = await rec.endRecording().toImage((kW * k).round(), (kSheetH * k).round());
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    return data!.buffer.asUint8List();
  }

  bool allWhite(List<int> p) {
    for (var i = 0; i < p.length; i += 4) {
      if (p[i] != 255 || p[i + 1] != 255 || p[i + 2] != 255 || p[i + 3] != 255) return false;
    }
    return true;
  }

  testWidgets('paintSheet sin fondo: todo blanco puro; con fondo, no', (t) async {
    final d = sample('grid');
    final sin = await t.runAsync(() => pixels(d, false));
    final con = await t.runAsync(() => pixels(d, true));
    expect(allWhite(sin!), isTrue);
    expect(allWhite(con!), isFalse);
    // el primer pixel es papel crema (no blanco) con fondo
    expect(con.sublist(0, 3), isNot([255, 255, 255]));
    expect(sin.sublist(0, 3), [255, 255, 255]);
  });

  testWidgets('paintSheet sin fondo no dibuja el fondo de imagen', (t) async {
    final d = sample('image', image: 'x.png');
    final c = await t.runAsync(() async {
      final rec = ui.PictureRecorder();
      final cv = ui.Canvas(rec);
      final src = ui.PictureRecorder();
      ui.Canvas(src).drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = const Color(0xFF000000));
      final img = await src.endRecording().toImage(4, 4);
      paintSheet(cv, d, 0, .5, images: {bgImageKey('x.png'): img}, background: false);
      final out = await rec.endRecording().toImage(20, 20);
      final data = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List();
    });
    expect(allWhite(c!), isTrue, reason: 'ni papel ni imagen');
  });

  test('ToolState guarda exportBg y lo lee (por defecto prendido)', () {
    expect(ToolState().exportBackground, isTrue);
    final ts = ToolState()..exportBackground = false;
    expect(ts.toJson()['exportBg'], false);
    expect((ToolState()..load(ts.toJson())).exportBackground, isFalse);
    expect((ToolState()..load({'tool': 'pen'})).exportBackground, isTrue);
  });

  testWidgets('la hoja Exportar muestra el switch y cambiarlo persiste', (t) async {
    Storage.useIsolates = false;
    addTearDown(() => Storage.useIsolates = true);
    final root = (await t.runAsync(() => Directory.systemTemp.createTemp('apuntes_exportbg')))!;
    addTearDown(() => root.deleteSync(recursive: true));
    final store = Storage(root: root);
    await t.runAsync(store.init);
    final ts = ToolState();
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    unawaited(showExportSheet(ctx, store, ts));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('exportBg')), findsOneWidget);
    expect(find.text('Incluir el fondo de la hoja'), findsOneWidget);
    await t.tap(find.byKey(const Key('exportBg')));
    await t.pumpAndSettle();
    expect(ts.exportBackground, isFalse);
    Map? prefs;
    for (var i = 0; i < 20 && prefs?['exportBg'] == null; i++) {
      // deja terminar el guardado (E/S real)
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 100));
      prefs = await t.runAsync<Map?>(() => store.loadPrefs());
    }
    expect(prefs?['exportBg'], false);
  });
}
