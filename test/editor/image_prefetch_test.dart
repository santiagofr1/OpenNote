import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:apuntes/rendering/ink_layers.dart';
import 'package:apuntes/rendering/sheet_image_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Etapa 4: prefetch de imágenes en la dirección del scroll, franjas, vectorial recortado en lo que falta y desalojo LRU.
void main() {
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('apuntes_prefetch');
    SheetImageCache.defaultMinPoints = 0;
  });
  tearDown(() {
    SheetImageCache.defaultMinPoints = 12000;
    root.deleteSync(recursive: true);
  });

  Stroke line(String id, double x0, double y0, double x1, double y1) =>
      Stroke(id, 'pen', '#000000', 4, [x0, y0, .5, (x0 + x1) / 2, (y0 + y1) / 2, .8, x1, y1, .5]);

  NotebookDoc armado(int sheets) {
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

  group('prefetchPlan', () {
    List<int> plan(int first, int last, int dir, {int count = 10}) =>
        SheetImageCache.prefetchPlan(first: first, last: last, dir: dir, count: count);

    test('hacia abajo: las visibles y las 2 siguientes', () => expect(plan(3, 4, 1), [3, 4, 5, 6]));
    test('hacia arriba: las visibles y las 2 anteriores (la más cercana primero)', () => expect(plan(3, 4, -1), [3, 4, 2, 1]));
    test('quieto: solo las visibles', () => expect(plan(3, 4, 0), [3, 4]));
    test('en los bordes del cuaderno no se pasa', () {
      expect(plan(8, 9, 1), [8, 9]);
      expect(plan(0, 0, -1), [0]);
      expect(plan(7, 8, 1), [7, 8, 9]);
    });
    test('franjas: cubren todas las filas sin huecos ni solapes', () {
      for (final h in [707, 1000, 2121, 4001]) {
        var prev = 0;
        for (var i = 0; i < 4; i++) {
          final (a, b) = SheetImageCache.stripRange(h, 4, i);
          expect(a, prev);
          expect(b, greaterThan(a));
          prev = b;
        }
        expect(prev, h);
      }
    });
  });

  group('en el editor', () {
    final tools = ToolState()..tool = Tool.select;

    Future<PageEditorState> open(WidgetTester t, NotebookDoc doc) async {
      t.view.physicalSize = const Size(1000, 1600); // vertical, como la tablet: una hoja y pico por pantalla
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      tools.zoom = 1;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: PageEditor(doc: doc, tools: tools, store: Storage(root: root), onChanged: () {}, onPrefsChanged: () {}),
        ),
      ));
      // el trabajo de la caché va por scheduleTask (un Timer.run): se suelta el editor para que no quede pendiente
      addTearDown(() => t.pumpWidget(const SizedBox(), duration: const Duration(milliseconds: 1)));
      await t.pump(const Duration(milliseconds: 300));
      return t.state<PageEditorState>(find.byType(PageEditor));
    }

    /// Cuadros y tiempo real, SIN llegar a los 300 ms de quietud (el temporizador de la quietud corre con el reloj de prueba).
    Future<void> frames(WidgetTester t, {int n = 20}) async {
      for (var i = 0; i < n; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await t.pump(const Duration(milliseconds: 5));
      }
    }

    bool ready(PageEditorState ed, NotebookDoc doc, int k) => ed.imageCache.entriesOf(doc.sheets[k].id).any((e) => e.hasImage);

    testWidgets('scrolleando hacia abajo se genera la de adelante (sin esperar quietud) ', (t) async {
      final doc = armado(8);
      final ed = await open(t, doc);
      ed.scroll.jumpTo(3 * kSheetStep * ed.scale + 200);
      await t.pump(const Duration(milliseconds: 10));
      ed.scroll.jumpTo(ed.scroll.offset + 60); // hacia abajo
      await t.pump(const Duration(milliseconds: 10));
      await frames(t);
      final v = ed.imageCache.visibleSheets;
      expect(v, contains(doc.sheets[3].id));
      expect(ready(ed, doc, 4), isTrue, reason: 'la que viene abajo ya tiene imagen');
      expect(ed.imageCache.generated, greaterThan(0));
    });

    testWidgets('scrolleando hacia arriba se genera la de arriba y no la de abajo', (t) async {
      final doc = armado(8);
      final ed = await open(t, doc);
      ed.scroll.jumpTo(4 * kSheetStep * ed.scale + 400);
      await t.pump(const Duration(milliseconds: 10));
      ed.scroll.jumpTo(ed.scroll.offset - 60); // hacia arriba
      await t.pump(const Duration(milliseconds: 10));
      await frames(t);
      expect(ready(ed, doc, 3), isTrue, reason: 'la de arriba ya tiene imagen');
      expect(ready(ed, doc, 6), isFalse, reason: 'la de abajo no');
      expect(ready(ed, doc, 7), isFalse);
    });

    testWidgets('a lo sumo maxJobsPerFrame trabajos por cuadro y un toImage a la vez', (t) async {
      final doc = armado(8);
      final ed = await open(t, doc);
      ed.scroll.jumpTo(3 * kSheetStep * ed.scale + 200);
      await t.pump(const Duration(milliseconds: 10));
      ed.scroll.jumpTo(ed.scroll.offset + 60);
      var maxPerFrame = 0, total = 0;
      for (var i = 0; i < 20; i++) {
        final before = ed.imageCache.jobsStarted;
        await t.pump(const Duration(milliseconds: 10));
        final d = ed.imageCache.jobsStarted - before;
        maxPerFrame = max(maxPerFrame, d);
        total += d;
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      }
      expect(maxPerFrame, lessThanOrEqualTo(ed.imageCache.maxJobsPerFrame));
      expect(ed.imageCache.maxRasterInFlight, 1);
      expect(total, greaterThan(3), reason: 'se generó por franjas, en varios cuadros');
    });

    testWidgets('editar una hoja invalida sus franjas y su imagen; las demás no', (t) async {
      final doc = armado(4);
      final ed = await open(t, doc);
      for (var i = 0; i < 3; i++) {
        await t.pump(const Duration(milliseconds: 400));
        await frames(t, n: 16);
      }
      final id = doc.sheets[0].id;
      expect(ed.sheetUsesImage(id), isTrue);
      final e = ed.imageCache.entriesOf(id).first;
      expect(e.readyStripKeys.length, 4);
      final other = ed.imageCache.stripsReady - 4;

      doc.strokes['nuevo'] = line('nuevo', 500, 700, 800, 900);
      await t.pump();
      expect(e.readyStripKeys, isEmpty);
      expect(ed.sheetUsesImage(id), isFalse);
      expect(ed.imageCache.stripsReady, other, reason: 'las otras hojas siguen con sus franjas');
    });
  });

  group('InkPainter con franjas', () {
    const scale = .5;
    final size = Size(kW * scale, kSheetH * scale);
    const sheet = Rect.fromLTWH(0, 0, kW, kSheetH);

    InkPainter painter(NotebookDoc doc, SheetImageCache cache, {String id = 'h', Set<String> hidden = const {}}) =>
        InkPainter(doc, doc.strokes.values.toList(), sheet, scale, ValueNotifier(0), () => hidden,
            cache: cache, cacheKey: 'k-$id', sheetId: id, dpr: 1);

    SheetImageCache nuevo({int strips = 4}) => SheetImageCache(minPoints: 0, quiet: const Duration(milliseconds: 20), stripCount: strips)
      ..framePaced = false;

    Future<ui.Image> render(InkPainter p) async {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      c.drawRect(Offset.zero & size, Paint()..color = Colors.white);
      p.paint(c, size);
      return rec.endRecording().toImage(size.width.round(), size.height.round());
    }

    Future<Uint8List> bytes(ui.Image im) async => (await im.toByteData())!.buffer.asUint8List();

    int inkPixels(Uint8List b) {
      var n = 0;
      for (var i = 0; i < b.length; i += 4) {
        if (b[i] < 128) n++;
      }
      return n;
    }

    /// Pinta, pide generar y espera a que termine (de verdad).
    Future<void> generar(InkPainter p, SheetImageCache cache, {String id = 'h'}) async {
      await render(p);
      cache.protectedSheets = {...cache.protectedSheets, id};
      cache.prefetch([id]);
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }

    testWidgets('el compuesto de 4 franjas es igual (casi píxel a píxel) a la imagen entera', (t) async {
      await t.runAsync(() async {
        final doc = armado(1);
        final c1 = nuevo(strips: 1), c4 = nuevo(strips: 4);
        final p1 = painter(doc, c1), p4 = painter(doc, c4);
        await generar(p1, c1);
        await generar(p4, c4);
        expect(c1.stripsReady, 1);
        expect(c4.stripsReady, 4);
        final a = await bytes(await render(p1)), b = await bytes(await render(p4));
        expect(c4.entriesOf('h').first.mode, InkPaintMode.image);
        var bad = 0, mx = 0;
        for (var i = 0; i < a.length; i++) {
          final d = (a[i] - b[i]).abs();
          if (d > 2) bad++;
          mx = max(mx, d);
        }
        expect(bad / a.length, lessThan(.0005), reason: 'máx dif $mx');
        expect(inkPixels(b), greaterThan(200));
        c1.dispose();
        c4.dispose();
      });
    });

    testWidgets('armar una franja cuesta menos que la hoja entera', (t) async {
      await t.runAsync(() async {
        final r = Random(3);
        final doc = NotebookDoc(Notebook.create('T'));
        for (var i = 0; i < 700; i++) {
          final x = r.nextDouble() * 900, y = r.nextDouble() * 1300;
          doc.strokes['s$i'] = Stroke('s$i', 'pen', '#000000', 3, [
            for (var j = 0; j < 60; j++) ...[x + j * 2.0, y + sin(j / 4) * 12, .6]
          ]);
        }
        final p = InkPainter(doc, doc.strokes.values.toList(), sheet, 1, ValueNotifier(0), () => const {});
        const w = 1000, h = 1414;
        Future<int> time(int y0, int y1) async {
          final sw = Stopwatch()..start();
          final pic = p.recordStrip(w, h, y0, y1)!;
          final im = await pic.toImage(w, y1 - y0);
          im.dispose();
          pic.dispose();
          return sw.elapsedMicroseconds;
        }

        await time(0, h); // calentar
        final whole = <int>[], strip = <int>[];
        for (var i = 0; i < 5; i++) {
          whole.add(await time(0, h));
          final (y0, y1) = SheetImageCache.stripRange(h, 4, 1 + i % 2);
          strip.add(await time(y0, y1));
        }
        whole.sort();
        strip.sort();
        expect(strip[2], lessThan(whole[2] * .8), reason: 'franja ${strip[2]} µs, hoja ${whole[2]} µs');
      });
    });

    testWidgets('hoja visible sin imagen: vectorial nítido (nunca miniatura); llega la buena y es igual', (t) async {
      await t.runAsync(() async {
        final doc = armado(1);
        final cache = nuevo();
        final p = painter(doc, cache);
        final e = cache.entry('k-h', 'h');
        await render(p);
        expect(e.mode, InkPaintMode.vector, reason: 'sin nada generado: vectorial como siempre');
        final vectorial = await bytes(await render(p));

        await generar(p, cache);
        expect(cache.usesImage('h'), isTrue);
        await render(p);
        expect(e.mode, InkPaintMode.image);

        // la imagen buena se desaloja: mientras tanto se ve vectorial, igual de nítido
        cache.protectedSheets = const {}; // que no se regenere sola enseguida
        cache.visibleSheets = {'h'};
        e.evict();
        e.refused = true; // y que no se regenere mientras miramos
        final sinImagen = await bytes(await render(p));
        expect(e.mode, InkPaintMode.vector);
        var bad = 0;
        for (var i = 0; i < sinImagen.length; i++) {
          if ((sinImagen[i] - vectorial[i]).abs() > 6) bad++;
        }
        expect(bad / sinImagen.length, lessThan(.002), reason: 'sin imagen se ve igual que el vectorial, no una versión borrosa');

        // llega la buena: se vuelve a la imagen
        e.refused = false;
        cache.protectedSheets = {'h'};
        cache.prefetch(['h']);
        await Future<void>.delayed(const Duration(milliseconds: 600));
        final buena = await bytes(await render(p));
        expect(e.mode, InkPaintMode.image);
        expect(cache.usesImage('h'), isTrue);
        bad = 0;
        for (var i = 0; i < buena.length; i++) {
          if ((buena[i] - vectorial[i]).abs() > 6) bad++;
        }
        expect(bad / buena.length, lessThan(.002), reason: 'en reposo se ve nítida, igual que el vectorial');

        // editar la hoja: vectorial al instante
        cache.invalidateSheet('h');
        await render(p);
        expect(e.mode, InkPaintMode.vector);
        cache.dispose();
      });
    });

    testWidgets('con franjas a medias: las listas van como imagen y el resto vectorial recortado, sin huecos', (t) async {
      await t.runAsync(() async {
        final doc = armado(1);
        final cache = nuevo();
        final p = painter(doc, cache);
        final e = cache.entry('k-h', 'h');
        await render(p);
        final vectorial = await bytes(await render(p));
        // solo se generan 2 franjas (después "hay lápiz": se posterga)
        cache.busy = () => cache.jobsStarted >= 2;
        cache.protectedSheets = {'h'};
        cache.visibleSheets = {'h'};
        cache.prefetch(['h']);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final listas = e.readyStripKeys.length;
        expect(listas, 2);
        final mixto = await bytes(await render(p));
        expect(e.mode, InkPaintMode.vector);
        var bad = 0;
        for (var i = 0; i < mixto.length; i++) {
          if ((mixto[i] - vectorial[i]).abs() > 6) bad++;
        }
        expect(bad / mixto.length, lessThan(.002));
        cache.dispose();
      });
    });

    testWidgets('desalojo LRU: nunca se suelta una hoja visible/protegida y se respeta el tope', (t) async {
      await t.runAsync(() async {
        final doc = armado(1);
        final cache = nuevo(strips: 2)..maxImages = 3;
        final ps = {for (final id in ['s0', 's1', 's2', 's3', 's4']) id: painter(doc, cache, id: id)};
        for (final p in ps.values) {
          await render(p);
        }
        cache.protectedSheets = {'s0'}; // s0 es la visible: la más vieja, pero no se toca
        for (final id in ps.keys) {
          cache.prefetch([id]);
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
        expect(cache.entriesOf('s0').first.hasImage, isTrue, reason: 'la protegida sigue');
        expect(cache.imageCount, lessThanOrEqualTo(3));
        expect(cache.entriesOf('s4').first.hasImage, isTrue, reason: 'la última pedida entró');
        final sinImagen = [for (final id in ps.keys) if (!cache.entriesOf(id).first.hasImage) id];
        expect(sinImagen, isNotEmpty);
        cache.dispose();
      });
    });

    testWidgets('cada franja tiene su clave en la caché', (t) async {
      await t.runAsync(() async {
        final doc = armado(1);
        final cache = nuevo();
        final p = painter(doc, cache);
        await generar(p, cache);
        expect(cache.stripKeys.toSet(), {'k-h#0', 'k-h#1', 'k-h#2', 'k-h#3'});
        cache.dispose();
      });
    });
  });
}
