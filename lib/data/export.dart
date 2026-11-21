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

/// Arma el PDF del cuaderno: una hoja A4 por cada hoja, cada una con su fondo y su papel.
/// [only]: índices de las hojas a incluir (todas si es null). [onProgress] recibe (hechas, total).
Future<Uint8List> buildNotebookPdf(Storage store, NotebookDoc nb,
    {void Function(int, int)? onProgress, List<int>? only}) async {
  final sheets = [
    for (var k = 0; k < nb.sheetCount; k++)
      if (only == null || only.contains(k)) k
  ];
  final pdf = pw.Document(title: nb.nb.name, creator: 'OpenNote');
  var done = 0;
  for (final k in sheets) {
    // las hojas sin cargar se leen de disco de a una y se sueltan: el PDF no necesita todo el cuaderno en memoria
    final (src, i) = await sheetSource(store, nb, k);
    final images = await loadImages(store, src, sheet: i);
    final Uint8List png;
    try {
      png = await renderSheetPng(src, i, images: images);
    } finally {
      for (final img in images.values) {
        img.dispose();
      }
    }
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill),
    ));
    onProgress?.call(++done, sheets.length);
  }
  return pdf.save();
}

/// De dónde dibujar la hoja [k] de [nb]: el propio documento si está cargada; si no, un documento chico con la hoja
/// de arriba (de memoria o de disco: lo que se le pasa de largo cae en esta) y esta, leída de disco. Devuelve el
/// documento y el índice de la hoja en él. Lo que esté sin guardar de una hoja cargada se ve igual.
Future<(NotebookDoc, int)> sheetSource(Storage store, NotebookDoc nb, int k) async {
  if (nb.isLoadedAt(k)) return (nb, k);
  final metas = [if (k > 0) nb.sheets[k - 1], nb.sheets[k]];
  final contents = <SheetContent>[];
  for (final m in metas) {
    contents.add(nb.isLoaded(m.id) ? (nb.splitSheets({m.id})[m.id] ?? SheetContent()) : await store.readSheetContent(nb.nb, m));
  }
  return (NotebookDoc.fromSheets(Notebook('', '', sheets: metas), contents), metas.length - 1);
}

/// Imágenes insertadas en [doc] (solo las de la hoja [sheet] si se da), decodificadas, por nombre de archivo
/// (las que faltan se saltean).
Future<Map<String, ui.Image>> loadImages(Storage store, NotebookDoc doc, {int? sheet}) async {
  final images = <String, ui.Image>{};
  for (final it in doc.items.values) {
    if (sheet != null && !it.rect.overlaps(ui.Rect.fromLTWH(0, sheet * kSheetStep, kW, kSheetH))) continue;
    if (it.type == 'image' && it.file != null && !images.containsKey(it.file)) {
      final f = store.media(it.file!);
      if (await f.exists()) images[it.file!] = await decodeImage(await f.readAsBytes());
    }
  }
  return images;
}

Future<ui.Image> decodeImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  return (await codec.getNextFrame()).image;
}

Future<Uint8List> renderSheetPng(NotebookDoc doc, int sheet, {Map<String, ui.Image>? images}) async {
  const k = _pxWidth / kW;
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec);
  c.scale(k);
  paintSheet(c, doc, sheet, k, images: images);
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
Future<bool> saveSheetPng(Storage store, NotebookDoc doc, int sheet, String name) async {
  final (src, i) = await sheetSource(store, doc, sheet);
  final png = await renderSheetPng(src, i, images: await loadImages(store, src, sheet: i));
  final uri = await FilePicker.saveFile(
    dialogTitle: 'Guardar imagen',
    fileName: safeFileName('$name.png'),
    bytes: png,
    mimeType: 'image/png',
  );
  return uri != null;
}

/// Abre el selector del sistema para elegir carpeta y nombre, y guarda el `.opennote`. Falso si el usuario canceló.
/// Es una variable para que los tests la reemplacen (no pueden manejar el diálogo del sistema).
Future<bool> Function(Uint8List bytes, String name) saveOpennote = (bytes, name) async {
  final safe = safeFileName(name).trim();
  final uri = await FilePicker.saveFile(
    dialogTitle: 'Guardar cuaderno',
    fileName: '${safe.isEmpty ? 'Cuaderno' : safe}.opennote',
    bytes: bytes,
    mimeType: 'application/octet-stream',
  );
  return uri != null;
};
