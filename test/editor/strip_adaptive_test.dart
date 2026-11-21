import 'dart:math';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/rendering/ink_layers.dart';
import 'package:apuntes/rendering/sheet_image_cache.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Etapa 4 (afinado): franjas según los puntos, hoja no visible sin dibujar, un solo toImage a la vez, prioridad y varios trabajos por cuadro.
void main() {
  const scale = .5;
  final size = Size(kW * scale, kSheetH * scale);
  const sheet = Rect.fromLTWH(0, 0, kW, kSheetH);

  /// [total] puntos repartidos en trazos de 100 puntos por toda la hoja.
  List<Stroke> tinta(int total, {int perStroke = 100}) {
    final r = Random(7);
    return [
      for (var i = 0; i < total ~/ perStroke; i++)
        () {
          final x = 50 + r.nextDouble() * (kW - 300), y = 20 + i * (kSheetH - 80) / (total ~/ perStroke); // reparto parejo
          return Stroke('s$i', 'pen', '#000000', 2, [
            for (var k = 0; k < perStroke; k++) ...[x + k * 2.0, y + sin(k / 8) * 6, .5],
          ]);
        }(),
    ];
  }

  NotebookDoc docDe(List<Stroke> ss) {
    final doc = NotebookDoc(Notebook.create('T'));
    for (final s in ss) {
      doc.strokes[s.id] = s;
    }
    return doc;
  }

  InkPainter painter(NotebookDoc doc, SheetImageCache cache, {String id = 'h'}) =>
      InkPainter(doc, doc.strokes.values.toList(), sheet, scale, ValueNotifier(0), () => const {},
          cache: cache, cacheKey: 'k-$id', sheetId: id, dpr: 1);

  Future<Uint8List> render(InkPainter p) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    c.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
    p.paint(c, size);
    final im = await rec.endRecording().toImage(size.width.round(), size.height.round());
    return (await im.toByteData())!.buffer.asUint8List();
  }

  int ink(Uint8List b) {
    var n = 0;
    for (var i = 0; i < b.length; i += 4) {
      if (b[i] < 128) n++;
    }
    return n;
  }

  group('cantidad de franjas por puntos', () {
    test('1000 / 46000 / 200000 puntos', () {
      expect(SheetImageCache.stripCountFor(tinta(1000), sheet), 4, reason: 'mínimo 4');
      final n46 = SheetImageCache.stripCountFor(tinta(46000), sheet);
      expect(n46, inInclusiveRange(16, 20), reason: '46000 / 3000 = 15,3 y los trazos que cruzan cuentan en dos');
      expect(SheetImageCache.stripCountFor(tinta(200000), sheet), 32, reason: 'máximo 32');
    });

    test('cada franja queda con a lo sumo ~maxPoints (contando los que cruzan)', () {
      final ss = tinta(46000);
      final n = SheetImageCache.stripCountFor(ss, sheet);
      final counts = List.filled(n, 0);
      for (final s in ss) {
        final i0 = ((s.bounds.top / kSheetH) * n).floor().clamp(0, n - 1), i1 = ((s.bounds.bottom / kSheetH) * n).floor().clamp(0, n - 1);
        for (var i = i0; i <= i1; i++) {
          counts[i] += s.n;
        }
      }
      expect(counts.reduce(max), lessThanOrEqualTo(3000 * 1.25));
    });

    testWidgets('el compuesto con franjas adaptativas es igual a la imagen entera', (t) async {
      await t.runAsync(() async {
        final doc = docDe(tinta(1200));
        SheetImageCache nuevo({int? strips}) => SheetImageCache(
            minPoints: 0, quiet: const Duration(milliseconds: 20), stripCount: strips, maxPointsPerStrip: 100)
          ..framePaced = false;
        final c1 = nuevo(strips: 1), cA = nuevo();
        final p1 = painter(doc, c1), pA = painter(doc, cA);
        for (final (p, c) in [(p1, c1), (pA, cA)]) {
          await render(p);
          c.protectedSheets = {'h'};
          c.prefetch(['h']);
          await Future<void>.delayed(const Duration(milliseconds: 1500));
        }
        final n = cA.entriesOf('h').first.stripN;
        expect(n, greaterThan(4), reason: 'con maxPointsPerStrip = 100 hacen falta más de 4');
        expect(cA.stripsReady, n);
        final a = await render(p1), b = await render(pA);
        expect(cA.entriesOf('h').first.mode, InkPaintMode.image);
        var bad = 0;
        for (var i = 0; i < a.length; i++) {
          if ((a[i] - b[i]).abs() > 2) bad++;
        }
        expect(bad / a.length, lessThan(.0005));
        expect(ink(b), greaterThan(200));
        c1.dispose();
        cA.dispose();
      });
    });
  });

  group('hoja no visible', () {
    testWidgets('sin imagen no dibuja trazos; al volverse visible se repinta y se ven', (t) async {
      await t.runAsync(() async {
        final doc = docDe(tinta(1200));
        final cache = SheetImageCache(minPoints: 0, quiet: const Duration(seconds: 30))..framePaced = false;
        final p = painter(doc, cache);
        final e = cache.entry('k-h', 'h');
        cache.visibleSheets = {'otra'};
        final vacio = await render(p);
        expect(ink(vacio), 0, reason: 'no se ve: no se dibuja nada');
        expect(e.mode, InkPaintMode.skipped);
        expect(e.record, isNotNull, reason: 'queda registrada para que el prefetch la genere');
        expect(e.wantW, greaterThan(0));

        var avisos = 0;
        e.addListener(() => avisos++);
        cache.setVisible({'h'});
        expect(avisos, 1, reason: 'al pasar a visible se repinta');
        expect(ink(await render(p)), greaterThan(200), reason: 'visible sin imagen: vectorial, nunca en blanco');
        cache.dispose();
      });
    });

    testWidgets('sin hojas visibles conocidas (primer cuadro) se dibuja como siempre', (t) async {
      await t.runAsync(() async {
        final doc = docDe(tinta(1200));
        final cache = SheetImageCache(minPoints: 0, quiet: const Duration(seconds: 30))..framePaced = false;
        expect(ink(await render(painter(doc, cache))), greaterThan(200));
        cache.dispose();
      });
    });

    testWidgets('visible con franjas a medias nunca usa miniatura: lo que falta se dibuja vectorial', (t) async {
      await t.runAsync(() async {
        final doc = docDe(tinta(1200));
        final cache = SheetImageCache(minPoints: 0, quiet: const Duration(seconds: 30), stripCount: 4)..framePaced = false;
        final p = painter(doc, cache);
        await render(p);
        cache.visibleSheets = {'h'};
        final e = cache.entry('k-h', 'h');
        cache.busy = () => cache.jobsStarted >= 1; // una sola franja lista
        cache.protectedSheets = {'h'};
        cache.prefetch(['h']);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        expect(e.readyStripKeys.length, 1);
        final mixto = await render(p);
        expect(e.mode, InkPaintMode.vector);
        expect(ink(mixto), greaterThan(200));
        cache.dispose();
      });
    });
  });

  group('serie de trabajos', () {
    testWidgets('nunca hay dos toImage en curso a la vez', (t) async {
      await t.runAsync(() async {
        final doc = docDe(tinta(1200));
        final cache = SheetImageCache(minPoints: 0, quiet: const Duration(milliseconds: 20), maxPointsPerStrip: 100)..framePaced = false;
        final ps = [for (var k = 0; k < 3; k++) painter(doc, cache, id: 'h$k')];
        for (final p in ps) {
          await render(p);
        }
        cache.protectedSheets = {'h0', 'h1', 'h2'};
        cache.prefetch(['h0', 'h1', 'h2']);
        await Future<void>.delayed(const Duration(milliseconds: 2500));
        expect(cache.generated, greaterThan(10));
        expect(cache.maxRasterInFlight, 1);
        expect(cache.rasterInFlight, 0);
        cache.dispose();
      });
    });

    InkImage fake(SheetImageCache cache, String key, String sheet, {int strips = 4}) {
      final e = cache.entry(key, sheet);
      e.record = (w, h, y0, y1) {
        final rec = ui.PictureRecorder();
        Canvas(rec).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), (y1 - y0).toDouble()), Paint());
        return rec.endRecording();
      };
      e.recStrokes = const [];
      e.stripN = strips;
      e.want(800, 1100);
      return e;
    }

    test('prioridad: franjas visibles en el viewport, luego el resto de la visible, luego las de adelante', () async {
      final cache = SheetImageCache(minPoints: 0)..framePaced = false;
      final orden = <String>[];
      final v = fake(cache, 'kv', 'v', strips: 8), a = fake(cache, 'ka', 'a', strips: 4);
      for (final (e, n) in [(v, 'v'), (a, 'a')]) {
        final rec = e.record!;
        e.record = (w, h, y0, y1) {
          final i = [for (var k = 0; k < e.stripN; k++) if (SheetImageCache.stripRange(h, e.stripN, k).$1 == y0) k].first;
          orden.add('$n$i');
          return rec(w, h, y0, y1);
        };
      }
      cache.protectedSheets = {'v', 'a'};
      // se ve de 40% a 60% de la hoja v (franjas 3 y 4 de 8)
      cache.setVisible({'v'}, fractions: {'v': (.4, .6)});
      cache.prefetch(['v', 'a'], dir: 1);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(orden.take(2), ['v3', 'v4'], reason: 'primero lo que se ve en pantalla');
      expect(orden.skip(2).take(6).toSet(), {'v0', 'v1', 'v2', 'v5', 'v6', 'v7'}, reason: 'después el resto de la visible');
      expect(orden.skip(8), ['a0', 'a1', 'a2', 'a3'], reason: 'al final las de adelante');
      expect(cache.maxRasterInFlight, 1);
      cache.dispose();
    });

    testWidgets('varios trabajos por cuadro con presupuesto de UI; uno solo sin presupuesto; un toImage en vuelo', (t) async {
      for (final (ms, esperaMuchos) in [(1.0, true), (20.0, false)]) {
        final cache = SheetImageCache(minPoints: 0);
        cache.uiMsProbe = () => ms;
        fake(cache, 'k', 's', strips: 12);
        cache.protectedSheets = {'s'};
        cache.prefetch(['s']);
        var maxPorCuadro = 0, prev = 0;
        await t.runAsync(() async {
          for (var f = 0; f < 6; f++) {
            await t.pump(const Duration(milliseconds: 16));
            await Future<void>.delayed(const Duration(milliseconds: 60));
            maxPorCuadro = max(maxPorCuadro, cache.jobsStarted - prev);
            prev = cache.jobsStarted;
          }
        });
        if (esperaMuchos) {
          expect(maxPorCuadro, greaterThan(1), reason: 'UI de 1 ms: se encadenan trabajos dentro del cuadro');
          expect(maxPorCuadro, lessThanOrEqualTo(cache.maxJobsPerFrame));
        } else {
          expect(maxPorCuadro, lessThanOrEqualTo(1), reason: 'UI de 20 ms: un trabajo por cuadro como mucho');
        }
        expect(cache.maxRasterInFlight, 1);
        cache.dispose();
        await t.pump(const Duration(milliseconds: 100));
      }
    });

    testWidgets('quieto con franjas faltantes en una visible: se generan todas ya, aunque el UI no tenga presupuesto', (t) async {
      final cache = SheetImageCache(minPoints: 0);
      cache.uiMsProbe = () => 20;
      final e = fake(cache, 'k', 's', strips: 12);
      cache.protectedSheets = {'s'};
      cache.still = true;
      await t.runAsync(() async {
        cache.setVisible({'s'});
        cache.prefetch(['s']);
        for (var f = 0; f < 10 && !e.stripCurrentAll; f++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      });
      expect(e.stripCurrentAll, isTrue);
      expect(cache.maxRasterInFlight, 1);
      cache.dispose();
      await t.pump(const Duration(milliseconds: 100));
    });
  });
}
