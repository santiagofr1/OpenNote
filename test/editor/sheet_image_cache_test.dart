import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:apuntes/rendering/ink_layers.dart';
import 'package:apuntes/rendering/sheet_image_cache.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Caché de imágenes de la tinta: una hoja quieta se dibuja con una imagen y vuelve a vectorial al cambiar.
void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('apuntes_imgcache');
    SheetImageCache.defaultMinPoints = 0; // en los tests, cualquier tinta vale una imagen
  });
  tearDown(() {
    SheetImageCache.defaultMinPoints = 1500;
    root.deleteSync(recursive: true);
  });

  Stroke line(String id, double x0, double y0, double x1, double y1) =>
      Stroke(id, 'pen', '#000000', 4, [x0, y0, .5, (x0 + x1) / 2, (y0 + y1) / 2, .8, x1, y1, .5]);

  NotebookDoc armado({int sheets = 1}) {
    final doc = NotebookDoc(Notebook.create('T'));
    while (doc.sheetCount < sheets) {
      doc.addSheet();
    }
    for (var k = 0; k < sheets; k++) {
      doc.strokes['a$k'] = line('a$k', 150, k * kSheetStep + 350, 350, k * kSheetStep + 550);
      doc.strokes['b$k'] = line('b$k', 300, k * kSheetStep + 450, 900, k * kSheetStep + 450);
    }
    return doc;
  }

  final tools = ToolState()..tool = Tool.select;

  Future<PageEditorState> open(WidgetTester t, NotebookDoc doc) async {
    t.view.physicalSize = const Size(1600, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    tools.zoom = 1;
    Widget app() => MaterialApp(
          home: Scaffold(
            body: PageEditor(doc: doc, tools: tools, store: Storage(root: root), onChanged: () {}, onPrefsChanged: () {}),
          ),
        );
    await t.pumpWidget(app());
    await t.pump(const Duration(milliseconds: 300));
    return t.state<PageEditorState>(find.byType(PageEditor));
  }

  /// Deja pasar el tiempo de quietud y espera (de verdad) a que termine el rasterizado de la imagen.
  Future<void> settle(WidgetTester t) async {
    await t.pump(const Duration(milliseconds: 400)); // vence el temporizador: se graba y se pide la imagen
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump();
    await t.pump();
  }

  testWidgets('(a) una hoja visible que queda quieta pasa a dibujarse con imagen', (t) async {
    final doc = armado();
    final ed = await open(t, doc);
    final id = doc.sheets[0].id;
    await settle(t);
    expect(ed.sheetUsesImage(id), isTrue);
    expect(ed.imageCache.imageCount, greaterThan(0));
  });

  testWidgets('(b) escribir en la hoja la invalida y vuelve a vectorial; al quedar quieta se regenera', (t) async {
    final doc = armado();
    final ed = await open(t, doc);
    final id = doc.sheets[0].id;
    await settle(t);
    expect(ed.sheetUsesImage(id), isTrue);
    final before = ed.imageCache.generated;

    doc.strokes['nuevo'] = line('nuevo', 500, 700, 800, 900);
    await t.pump();
    expect(ed.sheetUsesImage(id), isFalse, reason: 'recién escrito: vectorial');
    expect(ed.imageCache.imageCount, 0, reason: 'la imagen vieja se soltó');

    await t.pump(const Duration(milliseconds: 100));
    expect(ed.sheetUsesImage(id), isFalse, reason: 'todavía no pasó el rato de quietud');
    await settle(t);
    expect(ed.sheetUsesImage(id), isTrue);
    expect(ed.imageCache.generated, greaterThan(before));
  });

  testWidgets('(c) cambiar el zoom la invalida (se estira la vieja) y se regenera al quedar quieto', (t) async {
    final doc = armado();
    final ed = await open(t, doc);
    final id = doc.sheets[0].id;
    await settle(t);
    expect(ed.sheetUsesImage(id), isTrue);
    final w0 = ed.imageCache.bytes;

    tools.zoom = 1.3;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PageEditor(doc: doc, tools: tools, store: Storage(root: root), onChanged: () {}, onPrefsChanged: () {}),
      ),
    ));
    await t.pump();
    expect(ed.sheetUsesImage(id), isFalse, reason: 'otro tamaño: la imagen no sirve tal cual');
    expect(ed.imageCache.imageCount, 1, reason: 'sigue la vieja, que se dibuja estirada mientras tanto');

    await settle(t);
    expect(ed.sheetUsesImage(id), isTrue);
    expect(ed.imageCache.bytes, greaterThan(w0), reason: 'más píxeles a más zoom');
  });

  testWidgets('con más zoom que el tope (2x el ancho de pantalla) queda vectorial y sin imagen', (t) async {
    final doc = armado();
    final ed = await open(t, doc);
    await settle(t);
    tools.zoom = 4;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PageEditor(doc: doc, tools: tools, store: Storage(root: root), onChanged: () {}, onPrefsChanged: () {}),
      ),
    ));
    await settle(t);
    expect(ed.sheetUsesImage(doc.sheets[0].id), isFalse);
    expect(ed.imageCache.imageCount, 0, reason: 'no se guarda una imagen enorme');
  });

  testWidgets('(d) descargar la hoja libera su imagen', (t) async {
    final doc = armado(sheets: 3);
    final ed = await open(t, doc);
    await settle(t);
    final id = doc.sheets[0].id;
    expect(ed.sheetUsesImage(id), isTrue);
    final count = ed.imageCache.imageCount;
    doc.takeDirty(); // como si ya se hubiera guardado: una hoja sucia no se descarga
    expect(doc.detachSheet(id), isTrue);
    await t.pump();
    expect(ed.sheetUsesImage(id), isFalse);
    expect(ed.imageCache.imageCount, lessThan(count), reason: 'se soltó la imagen de esa hoja');
  });

  testWidgets('hay un tope de imágenes: nunca más de maxImages', (t) async {
    final doc = armado(sheets: 8);
    final ed = await open(t, doc);
    ed.imageCache.maxImages = 2;
    for (var i = 0; i < 6; i++) {
      await settle(t);
      ed.scroll.jumpTo(ed.scroll.offset + 700);
      await t.pump();
    }
    await settle(t);
    expect(ed.imageCache.imageCount, lessThanOrEqualTo(2));
  });

  testWidgets('(f) lo que se arrastra no queda de fantasma: durante el arrastre es vectorial; al soltar se regenera', (t) async {
    final doc = armado();
    final ed = await open(t, doc);
    final id = doc.sheets[0].id;
    await settle(t);
    expect(ed.sheetUsesImage(id), isTrue);
    // selecciona 'a0' (de 150,350 a 350,550) con un recuadro de ventana
    final layers = find
        .descendant(of: find.byType(PageEditor), matching: find.byType(Listener))
        .evaluate()
        .map((e) => e.renderObject as RenderBox)
        .firstWhere((b) => b.hasSize && (b.size.width - kW * ed.scale).abs() < .5);
    Offset at(double x, double y) => layers.localToGlobal(Offset(x, y) * ed.scale);
    var g = await t.startGesture(at(100, 300), kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 8; i++) {
      await g.moveTo(Offset.lerp(at(100, 300), at(400, 600), i / 8)!);
      await t.pump();
    }
    await g.up();
    await t.pump();
    expect(ed.sel.strokes, {'a0'});
    // empieza a arrastrarla
    g = await t.startGesture(at(250, 450), kind: PointerDeviceKind.stylus);
    for (var i = 1; i <= 4; i++) {
      await g.moveTo(at(250, 450) + Offset(30.0 * i, 0));
      await t.pump();
    }
    await t.pump(const Duration(milliseconds: 500));
    expect(ed.sel.moving, isTrue);
    expect(ed.sheetUsesImage(id), isFalse, reason: 'mientras se arrastra, la hoja va vectorial (sin el trazo oculto)');
    expect(ed.imageCache.imageCount, 0, reason: 'la imagen con el trazo se soltó');
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await t.pump();
    expect(ed.sheetUsesImage(id), isFalse, reason: 'tampoco se genera una imagen mientras hay trazos ocultos');
    await g.up();
    await t.pump();
    await settle(t);
    expect(ed.sheetUsesImage(id), isTrue);
  });

  // ---- pintura: la imagen se ve igual que los trazos ----
  Future<ui.Image> render(InkPainter p, Size size) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    p.paint(c, size);
    return rec.endRecording().toImage(size.width.round(), size.height.round());
  }

  Future<Uint8List> bytes(ui.Image im) async => (await im.toByteData())!.buffer.asUint8List();

  /// Fracción de bytes que difieren en más de [tol] y diferencia máxima.
  ({double frac, int max}) diff(Uint8List a, Uint8List b, {int tol = 6}) {
    expect(a.length, b.length);
    var bad = 0, mx = 0;
    for (var i = 0; i < a.length; i++) {
      final d = (a[i] - b[i]).abs();
      if (d > tol) bad++;
      if (d > mx) mx = d;
    }
    return (frac: bad / a.length, max: mx);
  }

  group('InkPainter con caché', () {
    const scale = .5;
    final size = Size(kW * scale, kSheetH * scale);
    const sheet = Rect.fromLTWH(0, 0, kW, kSheetH);

    InkPainter vec(NotebookDoc doc, List<Stroke> ss, {Set<String> hidden = const {}}) =>
        InkPainter(doc, ss, sheet, scale, ValueNotifier(0), () => hidden);

    InkPainter cached(NotebookDoc doc, List<Stroke> ss, SheetImageCache cache, {Set<String> hidden = const {}}) =>
        InkPainter(doc, ss, sheet, scale, ValueNotifier(0), () => hidden, cache: cache, cacheKey: 'k', sheetId: 'h', dpr: 1);

    testWidgets('(e) con imagen se ve igual que vectorial (con tolerancia)', (t) async {
      await t.runAsync(() async {
        final doc = armado();
        final ss = doc.strokes.values.toList();
        final cache = SheetImageCache(minPoints: 0, quiet: const Duration(milliseconds: 20));
        final p = cached(doc, ss, cache);
        final inicial = await bytes(await render(p, size)); // vectorial: arranca la cuenta
        expect(cache.usesImage('h'), isFalse);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(cache.usesImage('h'), isTrue, reason: 'ya se generó');
        final conImagen = await bytes(await render(p, size));
        final vectorial = await bytes(await render(vec(doc, ss), size));
        // la imagen no es lo mismo que nada, y es igual al vectorial
        expect(diff(inicial, vectorial).frac, lessThan(.001));
        final d = diff(conImagen, vectorial);
        expect(d.frac, lessThan(.002), reason: 'máx dif ${d.max}');
        var tinta = 0;
        for (var i = 0; i < vectorial.length; i += 4) {
          if (vectorial[i] < 128) tinta++;
        }
        expect(tinta, greaterThan(200), reason: 'el dibujo tiene que haber algo');
        cache.dispose();
      });
    });

    testWidgets('(f) con trazos ocultos no se usa la imagen: queda igual que vectorial sin ellos', (t) async {
      await t.runAsync(() async {
        final doc = armado();
        final ss = doc.strokes.values.toList();
        final cache = SheetImageCache(minPoints: 0, quiet: const Duration(milliseconds: 20));
        await render(cached(doc, ss, cache), size);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        expect(cache.usesImage('h'), isTrue);
        final oculto = await bytes(await render(cached(doc, ss, cache, hidden: {'a0'}), size));
        final esperado = await bytes(await render(vec(doc, ss, hidden: {'a0'}), size));
        expect(diff(oculto, esperado).frac, lessThan(.001), reason: 'sin fantasma del trazo oculto');
        expect(cache.usesImage('h'), isFalse, reason: 'la imagen con el trazo se soltó');
        cache.dispose();
      });
    });
  });
}
