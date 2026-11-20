import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'model.dart';
import 'painters.dart';
import 'storage.dart';

/// Resolución de cada hoja en el PDF (ancho en píxeles): ~200 ppp en A4.
const _pxWidth = 1654.0;

/// Arma el PDF de un cuaderno: cada hoja de cada página es una hoja A4.
/// [onProgress] recibe (hechas, total).
Future<Uint8List> buildNotebookPdf(Storage store, Notebook nb, {void Function(int, int)? onProgress}) async {
  final pages = <PageData>[for (final ref in nb.pages) await store.loadPage(ref.id)];
  final total = pages.fold<int>(0, (n, p) => n + sheetCount(p.h));
  final doc = pw.Document(title: nb.name, creator: 'Apuntes');
  var done = 0;
  for (final page in pages) {
    for (var k = 0; k < sheetCount(page.h); k++) {
      final png = await _renderSheet(page, k);
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill),
      ));
      onProgress?.call(++done, total);
    }
  }
  return doc.save();
}

Future<Uint8List> _renderSheet(PageData page, int sheet) async {
  const k = _pxWidth / kW;
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.scale(k);
  paintSheet(c, page, sheet, k);
  final img = await rec.endRecording().toImage(_pxWidth.round(), (kSheetH * k).round());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data!.buffer.asUint8List();
}

/// Abre el selector del sistema para elegir carpeta y nombre, y guarda el PDF.
/// Devuelve false si el usuario canceló.
Future<bool> savePdf(Uint8List bytes, String name) async {
  final safe = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-').trim();
  final uri = await FilePicker.saveFile(
    dialogTitle: 'Guardar PDF',
    fileName: '${safe.isEmpty ? 'Cuaderno' : safe}.pdf',
    bytes: bytes,
    mimeType: 'application/pdf',
  );
  return uri != null;
}
