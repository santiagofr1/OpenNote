// Prueba en la TABLET del dibujado de hojas para exportar (PNG y PDF).
//
// Contexto: en la Tab S6 Lite (Mali-G72, Flutter 3.50, Impeller/Vulkan) `Picture.toImage` + `toByteData` devolvía a veces la
// imagen ANTERIOR, píxeles transparentes o ruido (flutter/flutter#196627 y #196980). Acá se dibujan N hojas con una marca de
// color única cada una (con la pantalla renderizando de fondo, que es cuando pasa) y se comprueba, hoja por hoja:
//   - el camino VIEJO (toByteData(png) directo): cuántas salen mal (para saber si el dispositivo tiene el problema);
//   - el camino NUEVO (renderSheetPng, lecturas repetidas hasta que coinciden): tiene que salir TODO bien;
//   - el ZIP de PNG y el PDF reales de un cuaderno de N hojas.
// Todo se imprime con el prefijo EXPORTRENDER. Correr:
//   flutter test integration_test/export_render_test.dart -d <tablet>
// Variantes del arreglo para probar (se cambian arriba del test): `rasterStableReads` (1 = sin verificar, 2 = lo normal, 3...)
// y `rasterRetryPause`.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apuntes/data/export.dart';
import 'package:apuntes/data/export_raster.dart';
import 'package:apuntes/data/storage.dart';
import 'package:apuntes/domain/domain.dart';
import 'package:apuntes/rendering/sheet_render.dart';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as im;
import 'package:integration_test/integration_test.dart';

import '../test/helpers/export_check.dart';

void p(String s) => debugPrint('EXPORTRENDER $s');

const _n = 24;

/// El dibujado de antes: PNG directo del motor.
Future<im.Image?> _legacy(NotebookDoc doc, int sheet) async {
  const k = 1654.0 / kW;
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec)..scale(k);
  paintSheet(c, doc, sheet, k);
  final img = await rec.endRecording().toImage(1654, (kSheetH * k).round());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return im.decodePng(data!.buffer.asUint8List());
}

/// ¿La imagen es la hoja [k] y nada más? (su marca, y ninguna de las de las demás)
bool _ok(im.Image? page, int k) => page != null && Marks.found(page, [for (var m = 0; m < _n; m++) m]).join(',') == '$k';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dibujar hojas para exportar: viejo vs nuevo', (t) async {
    // la pantalla tiene que estar renderizando (es cuando el motor se equivoca)
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: CircularProgressIndicator()))));
    final root = await Directory.systemTemp.createTemp('export_render');
    final store = Storage(root: root);
    await store.init();
    final nb = Notebook.create('Render')..bg = 'grid';
    nb.sheets.clear();
    while (nb.sheets.length < _n) {
      nb.sheets.add(nb.newSheet());
    }
    final doc = NotebookDoc(nb);
    for (var k = 0; k < _n; k++) {
      Marks.add(doc, k, k);
    }
    await store.saveNotebook(doc);

    for (var round = 1; round <= 3; round++) {
      var badOld = 0;
      for (var k = 0; k < _n; k++) {
        if (!_ok(await _legacy(doc, k), k)) badOld++;
      }
      p('ronda $round: camino VIEJO (PNG directo): $badOld de $_n hojas mal');
    }

    for (var round = 1; round <= 3; round++) {
      final retries = rasterRetries;
      var badNew = 0;
      final sw = Stopwatch()..start();
      for (var k = 0; k < _n; k++) {
        final png = await renderSheetPng(doc, k);
        if (!_ok(im.decodePng(png), k)) badNew++;
      }
      p('ronda $round: camino NUEVO: $badNew de $_n mal, ${rasterRetries - retries} lecturas repetidas, ${sw.elapsedMilliseconds} ms');
      expect(badNew, 0, reason: 'el camino nuevo no puede dar hojas rotas');
    }

    // el ZIP de PNG de verdad
    final r = (await buildNotebookPngs(store, doc))!;
    final files = ZipDecoder().decodeBytes(r.bytes).where((f) => f.isFile).toList();
    expect(files.length, _n);
    var badZip = 0;
    for (var k = 0; k < _n; k++) {
      if (!_ok(im.decodePng(Uint8List.fromList(files[k].content as List<int>)), k)) badZip++;
    }
    p('ZIP: $badZip de $_n PNG mal');
    expect(badZip, 0);

    // el PDF de verdad: se guarda para mirarlo y se comprueba que tiene las páginas (el contenido se mira en la PC con pdfimages)
    final pdf = await buildNotebookPdf(store, doc);
    expect(pdfPageCount(pdf), _n);
    final out = File('${(await Directory.systemTemp.createTemp('pdfout')).path}/render.pdf');
    await out.writeAsBytes(pdf);
    p('PDF de $_n páginas en ${out.path} (${pdf.length} bytes)');
    await root.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
