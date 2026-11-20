import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/domain.dart';
import '../rendering/sheet_render.dart';
import 'storage.dart';

/// Resolución de cada hoja exportada (ancho en píxeles): ~200 ppp en A4.
const _pxWidth = 1654.0;

/// Arma el PDF de un cuaderno: cada hoja de cada página es una hoja A4.
/// [only]: ids de las páginas a incluir (todas si es null). [onProgress] recibe (hechas, total).
Future<Uint8List> buildNotebookPdf(Storage store, Notebook nb,
    {void Function(int, int)? onProgress, List<String>? only}) async {
  final pages = <PageData>[
    for (final ref in nb.pages)
      if (only == null || only.contains(ref.id)) await store.loadPage(ref.id)
  ];
  final images = await loadImages(store, pages);
  final total = pages.fold<int>(0, (n, p) => n + sheetCount(p.h));
  final doc = pw.Document(title: nb.name, creator: 'Apuntes');
  var done = 0;
  for (final page in pages) {
    for (var k = 0; k < sheetCount(page.h); k++) {
      final png = await renderSheetPng(page, k, images: images);
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

/// Imágenes insertadas en [pages], decodificadas, por nombre de archivo (las que faltan se saltean).
Future<Map<String, ui.Image>> loadImages(Storage store, Iterable<PageData> pages) async {
  final images = <String, ui.Image>{};
  for (final p in pages) {
    for (final it in p.items.values) {
      if (it.type == 'image' && it.file != null && !images.containsKey(it.file)) {
        final f = store.media(it.file!);
        if (await f.exists()) images[it.file!] = await decodeImage(await f.readAsBytes());
      }
    }
  }
  return images;
}

Future<ui.Image> decodeImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

Future<Uint8List> renderSheetPng(PageData page, int sheet, {Map<String, ui.Image>? images}) async {
  const k = _pxWidth / kW;
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.scale(k);
  paintSheet(c, page, sheet, k, images: images);
  final img = await rec.endRecording().toImage(_pxWidth.round(), (kSheetH * k).round());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data!.buffer.asUint8List();
}

/// Cambia los caracteres que no se permiten en nombres de archivo.
String safeFileName(String name) => name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-');

/// Abre el selector del sistema para elegir carpeta y nombre, y guarda el PDF.
/// Devuelve false si el usuario canceló.
Future<bool> savePdf(Uint8List bytes, String name) async {
  final safe = safeFileName(name).trim();
  final uri = await FilePicker.saveFile(
    dialogTitle: 'Guardar PDF',
    fileName: '${safe.isEmpty ? 'Cuaderno' : safe}.pdf',
    bytes: bytes,
    mimeType: 'application/pdf',
  );
  return uri != null;
}

/// Guarda la hoja [sheet] como PNG, preguntando dónde. Devuelve false si el usuario canceló.
Future<bool> saveSheetPng(Storage store, PageData page, int sheet, String name) async {
  final png = await renderSheetPng(page, sheet, images: await loadImages(store, [page]));
  final uri = await FilePicker.saveFile(
    dialogTitle: 'Guardar imagen',
    fileName: safeFileName('$name.png'),
    bytes: png,
    mimeType: 'image/png',
  );
  return uri != null;
}
