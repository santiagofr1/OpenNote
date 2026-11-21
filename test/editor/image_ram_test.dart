import 'dart:io';
import 'dart:ui' as ui;

import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/rendering/ink_layers.dart';
import 'package:apuntes/rendering/sheet_image_cache.dart';
import 'package:apuntes/rendering/stroke_painter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// RAM de la caché de imágenes y de las mallas: el presupuesto nunca se pasa, las hojas que salen de la ventana se
/// sueltan y al descargar una hoja no queda nada colgado (mallas, lotes, entradas de la caché).
void main() {
  const scale = .5;
  final size = Size(kW * scale, kSheetH * scale);
  const sheet = Rect.fromLTWH(0, 0, kW, kSheetH);

  setUp(() => SheetImageCache.defaultMinPoints = 0);
  tearDown(() => SheetImageCache.defaultMinPoints = 12000);

  NotebookDoc armado() {
    final doc = NotebookDoc(Notebook.create('T'));
    doc.strokes['a'] = Stroke('a', 'pen', '#000000', 4, [150, 350, .5, 250, 450, .8, 350, 550, .5])..z = 0;
    doc.strokes['b'] = Stroke('b', 'pencil', '#000000', 4, [300, 450, .5, 600, 450, .8, 900, 450, .5])..z = 1;
    return doc;
  }

  InkPainter painter(NotebookDoc doc, SheetImageCache cache, String id) =>
      InkPainter(doc, doc.strokes.values.toList(), sheet, scale, ValueNotifier(0), () => const {},
          cache: cache, cacheKey: 'k-$id', sheetId: id, dpr: 1);

  SheetImageCache nuevo({int max = 99, int bytes = 1 << 30}) =>
      SheetImageCache(minPoints: 0, quiet: const Duration(milliseconds: 20), stripCount: 2, maxImages: max, maxBytes: bytes)..framePaced = false;

  Future<void> render(InkPainter p) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    p.paint(c, size);
    (await rec.endRecording().toImage(4, 4)).dispose();
  }

  test('presupuesto por defecto: 96 MB, 8 tandas, 2 hojas adelante (5 hojas de ventana ~77 MB a 1650 px)', () {
    final c = SheetImageCache();
    expect(c.maxBytes, 96 << 20);
    expect(c.maxImages, 8);
    expect(SheetImageCache.prefetchAhead, 2);
    const hoja = 1650 * 2333 * 4; // bytes de una hoja a ~1650 px de ancho
    const ventana = 2 + SheetImageCache.prefetchAhead + 1;
    expect(ventana * hoja, lessThan(c.maxBytes), reason: 'la ventana protegida entra sin desalojos');
    expect(8 * hoja, greaterThan(c.maxBytes), reason: 'más de ~6 hojas enteras no entran: el techo manda');
    c.dispose();
  });

  testWidgets('la contabilidad nunca pasa el presupuesto de bytes ni de tandas', (t) async {
    await t.runAsync(() async {
      final doc = armado();
      // una hoja a escala .5 son ~ 0,4 MB: el tope de bytes deja entrar solo ~2 hojas
      final one = (kW * scale).ceil() * (kSheetH * scale).ceil() * 4;
      final cache = nuevo(bytes: one * 2 + one ~/ 2, max: 4);
      final ps = {for (var i = 0; i < 8; i++) 's$i': painter(doc, cache, 's$i')};
      var peak = 0, peakN = 0;
      for (final id in ps.keys) {
        await render(ps[id]!);
        cache.protectedSheets = {id};
        cache.prefetch([id]);
        for (var i = 0; i < 6; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          peak = peak > cache.bytes ? peak : cache.bytes;
          peakN = peakN > cache.imageCount ? peakN : cache.imageCount;
          expect(cache.bytes, lessThanOrEqualTo(one * 2 + one ~/ 2));
          expect(cache.imageCount, lessThanOrEqualTo(4));
        }
      }
      expect(peak, greaterThan(0), reason: 'sí se generaron imágenes');
      expect(cache.generated, greaterThan(4));
      cache.dispose();
    });
  });

  testWidgets('las hojas fuera de la ventana se sueltan; las visibles y protegidas se quedan', (t) async {
    await t.runAsync(() async {
      final doc = armado();
      final cache = nuevo();
      final ids = [for (var i = 0; i < 6; i++) 's$i'];
      final ps = {for (final id in ids) id: painter(doc, cache, id)};
      for (final id in ids) {
        await render(ps[id]!);
      }
      cache.protectedSheets = {...ids};
      cache.visibleSheets = {'s0'};
      cache.prefetch(ids);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      for (final id in ids) {
        expect(cache.entriesOf(id).first.hasImage, isTrue, reason: id);
      }
      final antes = cache.bytes;
      // la ventana se corre: ahora solo s4 y s5 (y s0 visible) cuentan
      cache.protectedSheets = {'s4', 's5'};
      final soltadas = cache.releaseOutsideWindow();
      expect(soltadas, 3, reason: 's1, s2 y s3');
      for (final id in ['s0', 's4', 's5']) {
        expect(cache.entriesOf(id).first.hasImage, isTrue, reason: id);
      }
      for (final id in ['s1', 's2', 's3']) {
        expect(cache.entriesOf(id).first.hasImage, isFalse, reason: id);
      }
      expect(cache.bytes, lessThan(antes));
      expect(cache.bytes, antes ~/ 2, reason: 'quedan 3 de 6 hojas iguales');
      // sin regenerar mientras estén fuera de la ventana
      cache.prefetch(['s4', 's5']);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(cache.entriesOf('s2').first.hasImage, isFalse);
      cache.dispose();
    });
  });

  testWidgets('dropSheet suelta las imágenes y las entradas de la hoja', (t) async {
    await t.runAsync(() async {
      final doc = armado();
      final cache = nuevo();
      final p = painter(doc, cache, 'h');
      await render(p);
      cache.protectedSheets = {'h'};
      cache.prefetch(['h']);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(cache.bytes, greaterThan(0));
      cache.dropSheet('h');
      expect(cache.bytes, 0);
      expect(cache.entriesOf('h'), isEmpty);
      expect(cache.stripKeys, isEmpty);
      cache.dispose();
    });
  });

  group('al descargar una hoja', () {
    late Directory root;
    late Storage store;
    setUpAll(() => Storage.useIsolates = false);
    tearDownAll(() => Storage.useIsolates = true);
    setUp(() async {
      root = Directory.systemTemp.createTempSync('apuntes_ram');
      store = Storage(root: root);
      await store.init();
    });
    tearDown(() => root.deleteSync(recursive: true));

    testWidgets('se sueltan mallas y lotes de sus trazos y al volver a cargarla vuelven con malla', (t) async {
      await t.runAsync(() async {
        final nb = Notebook.create('T');
        while (nb.sheets.length < 3) {
          nb.sheets.add(nb.newSheet());
        }
        final d = NotebookDoc(nb);
        for (var k = 0; k < 3; k++) {
          for (var i = 0; i < 4; i++) {
            final id = 's$k$i';
            d.strokes[id] = Stroke(id, 'pen', '#22211e', 3,
                [for (var j = 0; j < 30; j++) ...[100.0 + j * 10, k * kSheetStep + 100 + i * 50 + (j % 3), .6]])
              ..z = d.nextZ();
          }
        }
        await store.saveNotebook(d);
        final doc = await store.openNotebook(Notebook(nb.id, 'T'), around: 1, radius: 2, meshAll: true);
        await store.meshesIdle;
        final cache = nuevo();
        final id1 = doc.sheets[1].id;
        final mine = [for (final s in doc.strokes.values) if (doc.sheetOfElement(s) == 1) s];
        expect(mine, hasLength(4));
        for (final s in mine) {
          expect(s.mesh, isNotNull);
        }
        // se dibuja (arma los lotes y los Vertices nativos) y se pide imagen
        final rec = ui.PictureRecorder();
        paintStrokes(Canvas(rec), mine);
        rec.endRecording().dispose();
        expect(mine.any((s) => s.batchCache != null), isTrue, reason: 'el lote se armó al dibujar');
        // descargar: nada colgado
        doc.addLoadListener((id, loaded) {
          if (!loaded) cache.dropSheet(id);
        });
        final r = await store.unloadSheets(doc, [id1]);
        expect(r.unloaded, [id1]);
        for (final s in mine) {
          expect(s.mesh, isNull, reason: 'malla de ${s.id}');
          expect(s.batchCache, isNull, reason: 'lote de ${s.id}');
          expect(doc.strokes.containsKey(s.id), isFalse);
        }
        expect(cache.entriesOf(id1), isEmpty);
        expect(cache.bytes, 0);
        // volver a cargarla: llegan con malla de nuevo
        await store.loadSheets(doc, [id1]);
        final back = [for (final s in doc.strokes.values) if (doc.sheetOfElement(s) == 1) s];
        expect(back, hasLength(4));
        for (final s in back) {
          expect(s.mesh, isNotNull, reason: 'malla de ${s.id} tras recargar');
        }
        cache.dispose();
      });
    });
  });
}
