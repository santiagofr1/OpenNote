// Medición (no es un test de producto): importar PDF hoy vs. prototipo lazy con pdfrx, y qué hoja es "la actual".
// Todo se imprime con el prefijo PDFPERF.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apuntes/app.dart';
import 'package:apuntes/data/media_import.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/editor/page_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdf/pdf.dart' as pd;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';

void p(String s) => debugPrint('PDFPERF $s');

const _lorem = 'La integral definida de una funcion continua sobre un intervalo cerrado se interpreta como el area bajo la curva. '
    'Si f es positiva, el resultado coincide con el area; si cambia de signo, las zonas negativas restan. '
    'El teorema fundamental del calculo conecta la derivada con la integral: la derivada de la integral de f es f misma. '
    'Para calcular areas complejas se parte el intervalo en subintervalos y se suman rectangulos cada vez mas finos.';

Future<Uint8List> buildPdf(int pages) async {
  final doc = pw.Document();
  final rnd = Random(7);
  for (var i = 1; i <= pages; i++) {
    doc.addPage(pw.Page(
      pageFormat: pd.PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (c) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('Tema $i - Integrales y areas', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 10),
        for (var k = 0; k < 4; k++) pw.Paragraph(text: _lorem, style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 10),
        pw.Container(
          height: 150,
          decoration: pw.BoxDecoration(border: pw.Border.all(), color: pd.PdfColors.grey200),
          child: pw.CustomPaint(
            size: const pd.PdfPoint(500, 150),
            painter: (canvas, size) {
              canvas.setStrokeColor(pd.PdfColors.blue800);
              canvas.setLineWidth(1.5);
              canvas.moveTo(0, 20);
              for (var x = 0; x <= 500; x += 10) {
                canvas.lineTo(x.toDouble(), 20 + 100 * (0.5 + 0.5 * sin(x / 40 + i)) + rnd.nextDouble() * 4);
              }
              canvas.strokePath();
              canvas.setStrokeColor(pd.PdfColors.red600);
              for (var x = 0; x < 500; x += 25) {
                canvas.drawRect(x.toDouble(), 0, 20, 10 + rnd.nextDouble() * 80);
              }
              canvas.strokePath();
            },
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Text('Figura $i: aproximacion por rectangulos', style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 10),
        for (var k = 0; k < 3; k++) pw.Paragraph(text: _lorem, style: const pw.TextStyle(fontSize: 11)),
        pw.Divider(),
        pw.Bullet(text: 'Definicion de integral de Riemann', style: const pw.TextStyle(fontSize: 11)),
        pw.Bullet(text: 'Teorema fundamental del calculo', style: const pw.TextStyle(fontSize: 11)),
      ]),
    ));
  }
  return doc.save();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('apuntes_pdfperf'));
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('1 tiempo actual de importPdf (50 pags)', (t) async {
    await t.runAsync(() async {
      final sw = Stopwatch()..start();
      final bytes = await buildPdf(50);
      p('gen-pdf 50 pags: ${sw.elapsedMilliseconds} ms, tamano pdf ${bytes.length} bytes (${(bytes.length / 1024).toStringAsFixed(0)} KB)');
      final store = Storage(root: root);
      await store.init();
      final old = Pickers.pdf;
      Pickers.pdf = () async => (bytes, 'Apuntes');
      sw
        ..reset()
        ..start();
      final res = await importPdf(store);
      final total = sw.elapsedMilliseconds;
      Pickers.pdf = old;
      var png = 0, n = 0;
      for (final f in root.listSync(recursive: true)) {
        if (f is File && f.path.endsWith('.png')) {
          png += f.lengthSync();
          n++;
        }
      }
      p('importPdf total: $total ms para ${res.length} hojas (${(total / res.length).toStringAsFixed(0)} ms/pag)');
      p('PNG guardados: $n archivos, ${(png / 1048576).toStringAsFixed(1)} MB vs PDF ${(bytes.length / 1048576).toStringAsFixed(2)} MB (x${(png / bytes.length).toStringAsFixed(0)})');

      // desglose por pagina (primeras 5), misma secuencia que importPdf
      final s2 = Stopwatch()..start();
      var i = 0;
      var last = 0;
      await for (final r in Printing.raster(bytes, dpi: 150, pages: [0, 1, 2, 3, 4])) {
        final tRaster = s2.elapsedMilliseconds - last; // espera del stream = raster nativo (+ transferencia)
        final a = s2.elapsedMilliseconds;
        final b = await r.toPng();
        final tPng = s2.elapsedMilliseconds - a;
        final c = s2.elapsedMilliseconds;
        await store.addMedia(b, 'png');
        final tWrite = s2.elapsedMilliseconds - c;
        i++;
        p('pag $i: ${r.width}x${r.height} raster=$tRaster ms toPng=$tPng ms write=$tWrite ms png=${(b.length / 1024).toStringAsFixed(0)} KB');
        last = s2.elapsedMilliseconds;
      }
    });
  });

  testWidgets('2 prototipo pdfrx', (t) async {
    await t.runAsync(() async {
      final bytes = await buildPdf(50);
      await pdfrxFlutterInitialize();
      final sw = Stopwatch()..start();
      final d = await PdfDocument.openData(bytes);
      final t0 = sw.elapsedMilliseconds;
      final sizes = [for (final pg in d.pages) (pg.width, pg.height)];
      final t1 = sw.elapsedMilliseconds;
      p('pdfrx abrir=$t0 ms, leer ${d.pages.length} tamanos=${t1 - t0} ms (total $t1 ms), pag1=${sizes.first}');

      Future<PdfImage> render(int i, double w) async {
        final pg = d.pages[i];
        final img = await pg.render(fullWidth: w, fullHeight: w * pg.height / pg.width);
        return img!;
      }

      sw
        ..reset()
        ..start();
      var im = await render(0, 1200);
      p('pdfrx render pag1 1200px (primera, en frio): ${sw.elapsedMilliseconds} ms ${im.width}x${im.height} bytes=${im.pixels.length} (${(im.pixels.length / 1048576).toStringAsFixed(1)} MB)');
      im.dispose();
      for (final w in [1200.0, 2400.0]) {
        final times = <int>[];
        var bytesN = 0;
        for (var i = 1; i <= 5; i++) {
          sw
            ..reset()
            ..start();
          im = await render(i, w);
          times.add(sw.elapsedMilliseconds);
          bytesN = im.pixels.length;
          im.dispose();
        }
        p('pdfrx render ${w.toInt()}px (5 paginas distintas): $times ms, bitmap $bytesN bytes (${(bytesN / 1048576).toStringAsFixed(1)} MB)');
      }
      sw
        ..reset()
        ..start();
      for (var i = 10; i < 13; i++) {
        (await render(i, 1200)).dispose();
      }
      p('pdfrx 3 paginas seguidas 1200px: ${sw.elapsedMilliseconds} ms');
      sw
        ..reset()
        ..start();
      im = await render(20, 1200);
      final ui.Image u = await im.createImage();
      p('pdfrx render+createImage 1200px: ${sw.elapsedMilliseconds} ms');
      u.dispose();
      im.dispose();
      sw
        ..reset()
        ..start();
      final ims = await Future.wait([for (var i = 30; i < 33; i++) render(i, 1200)]);
      p('pdfrx 3 paginas en paralelo 1200px: ${sw.elapsedMilliseconds} ms');
      for (final x in ims) {
        x.dispose();
      }
      sw
        ..reset()
        ..start();
      await for (final r in Printing.raster(bytes, pages: [40], dpi: 144)) {
        p('Printing.raster 1 pagina (dpi 144, ${r.width}x${r.height}): ${sw.elapsedMilliseconds} ms');
      }
      await d.dispose();
    });
  });

  testWidgets('3 posicion de la hoja actual al importar', (t) async {
    Future<void> settle(int ms) async {
      for (var i = 0; i < ms ~/ 50; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    await t.pumpWidget(ApuntesApp(root: root));
    await settle(1500);
    await t.tap(find.byKey(const Key('new')));
    await settle(400);
    await t.tap(find.byKey(const Key('newNotebook')));
    await settle(400);
    await t.enterText(find.byKey(const Key('askText')), 'Pos');
    await t.tap(find.byKey(const Key('askOk')));
    await settle(1500);
    await t.tap(find.byKey(const Key('pagesBtn')));
    await settle(600);
    for (var i = 0; i < 4; i++) {
      await t.tap(find.byKey(const Key('addPage')));
      await settle(900);
    }
    final ed = t.state<PageEditorState>(find.byType(PageEditor));
    expect(ed.doc.sheetCount, 5);
    final notifier = t.widget<PageEditor>(find.byType(PageEditor)).sheetNotifier!;
    final sz = t.view.physicalSize / t.view.devicePixelRatio;
    p('pantalla ${sz.width.toStringAsFixed(0)}x${sz.height.toStringAsFixed(0)} dp (${sz.width > sz.height ? "horizontal" : "vertical"}), scale=${ed.scale.toStringAsFixed(3)}');

    final vh = ed.scroll.position.viewportDimension / ed.scale; // alto visible en coords de pagina
    p('viewport alto en pagina=${vh.toStringAsFixed(0)} (kSheetH=$kSheetH, gap=$kGap, step=$kSheetStep)');

    Future<void> probe(String name, double topPage) async {
      ed.scroll.jumpTo((topPage * ed.scale).clamp(0.0, ed.scroll.position.maxScrollExtent));
      await settle(700);
      final top = ed.scroll.offset / ed.scale;
      final vis = ed.visibleSheet;
      var best = 0;
      var bestA = -1.0;
      final areas = <String>[];
      for (var k = 0; k < ed.doc.sheetCount; k++) {
        final a = max(0.0, min(top + vh, k * kSheetStep + kSheetH) - max(top, k * kSheetStep));
        if (a > 0) areas.add('h${k + 1}=${(100 * a / vh).toStringAsFixed(0)}%');
        if (a > bestA) {
          bestA = a;
          best = k;
        }
      }
      final cur = notifier.value;
      p('pos $name: top=${top.toStringAsFixed(0)} centro=${(top + vh / 2).toStringAsFixed(0)} visibleSheet=h${vis + 1} masArea=h${best + 1} '
          '[${areas.join(' ')}] curSheet(notifier)=h${cur + 1} -> el PDF queda desde la posicion ${cur + 2} (despues de h${cur + 1})');
    }

    final s2 = kSheetStep; // tope de la hoja 2
    await probe('(i) hoja 2 arriba de todo', s2);
    await probe('(ii) mitad de la hoja 2', s2 + kSheetH / 2 - vh / 2);
    await probe('(iii) final de h2 asomando h3 (borde de h2 al 70% de pantalla)', s2 + kSheetH - 0.7 * vh);
    await probe('(iii-b) borde de h2 al 55% (h3 asoma ~45%)', s2 + kSheetH - 0.55 * vh);
    await probe('(iii-c) borde de h2 al 40% (h3 asoma ~60%)', s2 + kSheetH - 0.4 * vh);
    await probe('(iv) centro justo en el hueco h2-h3', s2 + kSheetH + kGap / 2 - vh / 2);
  });
}
