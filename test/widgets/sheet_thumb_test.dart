import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:apuntes/data/export.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/rendering/sheet_render.dart';
import 'package:apuntes/widgets/sheet_thumb.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Miniaturas con PDF e imágenes (issue #19): antes se dibujaban sin ellas y la página salía en blanco.
void main() {
  late Directory root;
  late Storage store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('apuntes_thumb');
    store = Storage(root: root);
    await store.init();
  });
  tearDown(() async {
    thumbImagesLoader = loadThumbImages;
    await root.delete(recursive: true);
  });

  Future<ui.Image> solid(int w, int h, Color color) async {
    final rec = ui.PictureRecorder();
    ui.Canvas(rec).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = color);
    return rec.endRecording().toImageSync(w, h);
  }

  Item pdfItem() => Item('p', 'pdf', 100, 100, 800, 1100, file: 'a.pdf', page: 2);

  NotebookDoc docWith(Item it) {
    final nb = Notebook.create('Con PDF');
    return NotebookDoc(nb)..items[it.id] = it;
  }

  Widget host(GlobalKey key, NotebookDoc doc, {int version = 0}) => Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(width: 200, height: 283, child: SheetThumb(doc: doc, version: version, store: store)),
          ),
        ),
      );

  Future<ui.Image> capture(WidgetTester t, GlobalKey key) async {
    final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    return (await t.runAsync(() => b.toImage()))!;
  }

  Future<int> pixel(WidgetTester t, ui.Image img, int x, int y) async {
    final data = (await t.runAsync(() => img.toByteData()))!;
    final o = (y * img.width + x) * 4;
    return (data.getUint8(o) << 16) | (data.getUint8(o + 1) << 8) | data.getUint8(o + 2);
  }

  testWidgets('la página de PDF se dibuja con la imagen cargada (no en blanco)', (t) async {
    final it = pdfItem();
    thumbImagesLoader = (s, d, k, px) async => {pdfImageKey(it): await solid(50, 70, const Color(0xFFFF0000))};
    final key = GlobalKey();
    await t.pumpWidget(host(key, docWith(it)));
    await t.pump();
    await t.pump();
    final img = await capture(t, key);
    // centro del rect del PDF: x 100..900 de 1000, y 100..1200 de 1414 (la miniatura mide 200x283)
    expect(await pixel(t, img, 100, 130), 0xFF0000);
  });

  testWidgets('sin imágenes en la hoja no se llama al cargador', (t) async {
    var calls = 0;
    thumbImagesLoader = (s, d, k, px) async {
      calls++;
      return {};
    };
    final key = GlobalKey();
    await t.pumpWidget(host(key, NotebookDoc(Notebook.create('Vacío'))));
    await t.pump();
    expect(calls, 0);
  });

  testWidgets('al desmontar se liberan las imágenes', (t) async {
    final it = pdfItem();
    late ui.Image loaded;
    thumbImagesLoader = (s, d, k, px) async => {pdfImageKey(it): loaded = await solid(10, 10, const Color(0xFFFF0000))};
    final key = GlobalKey();
    await t.pumpWidget(host(key, docWith(it)));
    await t.pump();
    await t.pump();
    expect(loaded.debugDisposed, isFalse);
    await t.pumpWidget(const SizedBox());
    expect(loaded.debugDisposed, isTrue);
  });

  testWidgets('una carga que llega tarde (ya desmontado) se libera sin usarse', (t) async {
    final it = pdfItem();
    final llega = Completer<Map<String, ui.Image>>();
    thumbImagesLoader = (s, d, k, px) => llega.future;
    final key = GlobalKey();
    await t.pumpWidget(host(key, docWith(it)));
    await t.pumpWidget(const SizedBox());
    final loaded = await solid(10, 10, const Color(0xFFFF0000));
    llega.complete({pdfImageKey(it): loaded});
    await t.pump();
    expect(loaded.debugDisposed, isTrue);
  });

  testWidgets('la versión sola no vuelve a pedir; cambiar las imágenes de la hoja sí, y suelta las viejas', (t) async {
    final it = pdfItem();
    final made = <ui.Image>[];
    thumbImagesLoader = (s, d, k, px) async {
      final i = await solid(10, 10, const Color(0xFFFF0000));
      made.add(i);
      return {pdfImageKey(it): i};
    };
    final key = GlobalKey();
    final doc = docWith(it);
    await t.pumpWidget(host(key, doc));
    await t.pump();
    await t.pump();
    expect(made, hasLength(1));
    // un trazo en la hoja abierta sube la versión: las imágenes no cambiaron, no se vuelven a pedir
    await t.pumpWidget(host(key, doc, version: 1));
    await t.pump();
    await t.pump();
    expect(made, hasLength(1));
    // el PDF cambió de tamaño: hay que pedirlo de nuevo
    it.w = it.w / 2;
    await t.pumpWidget(host(key, doc, version: 2));
    await t.pump();
    await t.pump();
    expect(made, hasLength(2));
    expect(made[0].debugDisposed, isTrue);
    expect(made[1].debugDisposed, isFalse);
  });

  testWidgets('loadThumbImages decodifica la imagen al ancho de la miniatura, no al original', (t) async {
    final src = await solid(2000, 1000, const Color(0xFF00FF00));
    final png = (await t.runAsync(() async => (await src.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List()))!;
    await t.runAsync(() async {
      await Directory('${root.path}/media').create(recursive: true);
      await store.media('foto.png').writeAsBytes(png);
    });
    final it = Item('i', 'image', 0, 0, 500, 250, file: 'foto.png');
    final doc = docWith(it);
    final m = (await t.runAsync(() => loadThumbImages(store, doc, 0, 200)))!;
    expect(m.keys, ['foto.png']);
    expect(m['foto.png']!.width, 100); // 500 de 1000 de ancho de hoja * 200 px
    for (final i in m.values) {
      i.dispose();
    }
    // una hoja sin imágenes ni PDF no toca el disco
    final vacio = (await t.runAsync(() => loadThumbImages(store, NotebookDoc(Notebook.create('x')), 0, 200)))!;
    expect(vacio, isEmpty);
  });
}
